--!strict
-- AnimationAsset: Clean, correct KeyframeSequence parser + sampler.

local AnimationAsset = {}

export type AnimationKeyframe = {
	Name: string,
	Time: number;
	Value: CFrame;
}

export type AnimationTrack = {
	Name: string;
	Keyframes: { AnimationKeyframe };
}

export type AnimationEvent = {
	Time: number;
	Name: string;
	Value: string;
}

export type AnimationSample = {
	Transforms: { [string]: CFrame };
}

export type AnimationAssetInstance = {
	Name: string;
	Duration: number;
	Tracks: { [string]: {AnimationKeyframe} };
	Events: { AnimationEvent };

	Sample: (self: AnimationAssetInstance, time: number) -> AnimationSample;
	GetLength: (self: AnimationAssetInstance) -> number;
	GetEventsAt: (self: AnimationAssetInstance, time: number, window: number?) -> { AnimationEvent };
}

---------------------------------------------------------------------
-- UTILITIES
---------------------------------------------------------------------

local function safeGetRootPoses(keyframe: Keyframe): { Instance }
	-- Try modern API
	local ok, poses = pcall(function()
		return keyframe:GetPoses()
	end)

	if ok and typeof(poses) == "table" then
		return poses
	end

	-- Fallback: legacy KeyframeSequence format
	local results: { Instance } = {}
	for _, child: Instance in ipairs(keyframe:GetChildren()) do
		if child:IsA("Pose") then
			table.insert(results, child)
		end
	end

	return results
end

local function safeGetSubPoses(pose: Pose): { Instance }
	local ok, sub = pcall(function()
		return pose:GetSubPoses()
	end)

	if ok and typeof(sub) == "table" then
		return sub
	end

	-- Fallback: legacy format
	local results: { Instance } = {}
	for _, child: Instance in ipairs(pose:GetChildren()) do
		if child:IsA("Pose") then
			table.insert(results, child)
		end
	end

	return results
end

---------------------------------------------------------------------
-- POSE TREE PARSING
---------------------------------------------------------------------

local function collectPosesRecursive(
	pose: Pose,
	time: number,
	tracks: { [string]: { AnimationKeyframe } }
)
	local jointName = pose.Name
	if jointName and pose.CFrame then
		tracks[jointName] = tracks[jointName] or {}
		table.insert(tracks[jointName], {
			Name = pose.Name;
			Time = time;
			Value = pose.CFrame;
		})
	end

	for _, subPose: Instance in ipairs(safeGetSubPoses(pose)) do
		if subPose:IsA("Pose") then
			collectPosesRecursive(subPose, time, tracks)
		end
	end
end

local function parseKeyframeSequence(sequence: KeyframeSequence)
	local tracks: { [string]: { AnimationKeyframe } } = {}

	for _, keyframe: Instance in ipairs(sequence:GetKeyframes()) do
		if not keyframe:IsA("Keyframe") then
			continue
		end
		local time = keyframe.Time

		for _, pose: Instance in ipairs(safeGetRootPoses(keyframe)) do
			if pose:IsA("Pose") then
				collectPosesRecursive(pose, time, tracks)
			end
		end
	end

	-- Sort each track by time
	for _, keyframes in pairs(tracks) do
		table.sort(keyframes, function(a, b)
			return a.Time < b.Time
		end)
	end

	return tracks
end

---------------------------------------------------------------------
-- SAMPLING
---------------------------------------------------------------------

local function sampleTrack(keyframes: { AnimationKeyframe }, time: number): CFrame
	local count = #keyframes
	if count == 0 then
		return CFrame.new()
	end

	if time <= keyframes[1].Time then
		return keyframes[1].Value
	end

	if time >= keyframes[count].Time then
		return keyframes[count].Value
	end

	for i = 1, count - 1 do
		local a = keyframes[i]
		local b = keyframes[i + 1]

		if time >= a.Time and time <= b.Time then
			local alpha = (time - a.Time) / (b.Time - a.Time)
			return a.Value:Lerp(b.Value, alpha)
		end
	end

	return keyframes[count].Value
end

---------------------------------------------------------------------
-- EVENTS
---------------------------------------------------------------------

local function extractEvents(sequence: KeyframeSequence): { AnimationEvent }
	local events = {}

	for _, keyframe: Instance in ipairs(sequence:GetKeyframes()) do
		if not keyframe:IsA("Keyframe") then
			continue
		end
		for _, marker: Instance in ipairs(keyframe:GetMarkers()) do
			if not marker:IsA("KeyframeMarker") then
				continue
			end
			table.insert(events, {
				Time = keyframe.Time;
				Name = marker.Name;
				Value = marker.Value;
			})
		end
	end

	table.sort(events, function(a, b)
		return a.Time < b.Time
	end)

	return events
end

---------------------------------------------------------------------
-- CONSTRUCTOR
---------------------------------------------------------------------

function AnimationAsset.new(sequence: KeyframeSequence, nameOverride: string?): AnimationAssetInstance
	assert(sequence:IsA("KeyframeSequence"), "AnimationAsset.new requires a KeyframeSequence")

	local self = {}  :: AnimationAssetInstance

	self.Name = nameOverride or sequence.Name
	self.Tracks = parseKeyframeSequence(sequence)
	self.Events = extractEvents(sequence)

	-- Duration = last keyframe time
	local last = 0
	for _, keyframe: Instance in ipairs(sequence:GetKeyframes()) do
		if not keyframe:IsA("Keyframe") then
			continue
		end
		if keyframe.Time > last then
			last = keyframe.Time
		end
	end
	self.Duration = last
	
	self.GetLength = AnimationAsset.GetLength
	self.GetEventsAt = AnimationAsset.GetEventsAt
	self.Sample = AnimationAsset.Sample

	return self
end

---------------------------------------------------------------------
-- API
---------------------------------------------------------------------

function AnimationAsset.GetLength(self: AnimationAssetInstance)
	return self.Duration
end

function AnimationAsset.GetEventsAt(self: AnimationAssetInstance, time: number, window: number?): { AnimationEvent }
	local safeWindow: number = window or 0.033
	local lower = math.max(0, time - safeWindow)
	local upper = time

	local results = {}
	for _, event in ipairs(self.Events) do
		if event.Time >= lower and event.Time <= upper then
			table.insert(results, event)
		elseif event.Time > upper then
			break
		end
	end

	return results
end

function AnimationAsset.Sample(self: AnimationAssetInstance, time: number): AnimationSample
	local t = math.clamp(time, 0, self.Duration)
	local transforms: { [string]: CFrame } = {}

	for joint, track in pairs(self.Tracks) do
		transforms[joint] = sampleTrack(track, t)
	end

	return {
		Transforms = transforms,
	}
end

return AnimationAsset