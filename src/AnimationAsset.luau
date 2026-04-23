--!strict
-- AnimationAsset: Clean, correct KeyframeSequence parser + sampler.

local AnimationAsset = {}

export type AnimationKeyframe = {
	Name: string,
	Time: number;
	Value: CFrame;
}

export type AnimationChannel = {
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
	Channels: { [string]: {AnimationKeyframe} };
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
	channels: { [string]: { AnimationKeyframe } }
)
	local jointName = pose.Name

	-- Bug Fix from @silentgalaxzy on Discord:
	-- Skip poses authored as "no data at this keyframe" (Weight == 0).
    -- These are placeholder markers on parent joints used by the Roblox
    -- animation editor when only some joints are keyed on a given frame.
    -- Treating them as real (identity) keyframes causes visible snap-back
    -- on sparsely-keyframed animations.

	if jointName and pose.CFrame and pose.Weight and pose.Weight > 0 then
		channels[jointName] = channels[jointName] or {}
		table.insert(channels[jointName], {
			Name = pose.Name;
			Time = time;
			Value = pose.CFrame;
		})
	end

	for _, subPose: Instance in ipairs(safeGetSubPoses(pose)) do
		if subPose:IsA("Pose") then
			collectPosesRecursive(subPose, time, channels)
		end
	end
end

local function parseKeyframeSequence(sequence: KeyframeSequence)
	local channels: { [string]: { AnimationKeyframe } } = {}

	for _, keyframe: Instance in ipairs(sequence:GetKeyframes()) do
		if not keyframe:IsA("Keyframe") then
			continue
		end
		local time = keyframe.Time

		for _, pose: Instance in ipairs(safeGetRootPoses(keyframe)) do
			if pose:IsA("Pose") then
				collectPosesRecursive(pose, time, channels)
			end
		end
	end

	-- Sort each channel by time
	for _, keyframes in pairs(channels) do
		table.sort(keyframes, function(a, b)
			return a.Time < b.Time
		end)
	end

	return channels
end

---------------------------------------------------------------------
-- SAMPLING
---------------------------------------------------------------------

local function sampleChannel(keyframes: { AnimationKeyframe }, time: number): CFrame
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

-- Parsed-asset cache keyed by (KeyframeSequence, Name).
--
-- parseKeyframeSequence + extractEvents do a full recursive walk of every
-- keyframe and sub-pose in the sequence.  For a rig with ~20 tracks this is
-- non-trivial synchronous work, and is commonly triggered every time a
-- character spawns -- including every peer respawn.
--
-- The AnimationAsset is a read-only view of the sequence's static data
-- (Channels, Events, Duration), so we memoize by sequence instance and share
-- the parsed result across every caller for the lifetime of the sequence.
--
-- Weak keys: FluxaAssetManager.Load destroys the source KeyframeSequence
-- after parsing (when the caller owns it or it came from GetKeyframeSequence-
-- Async).  A weak-keyed cache lets those destroyed sequences drop out as
-- soon as Lua GCs them so we don't leak their parse trees.
--
-- Inner table keyed by Name because the same sequence could in principle be
-- requested with different nameOverrides.
local assetCache: { [KeyframeSequence]: { [string]: AnimationAssetInstance } } = setmetatable({}, { __mode = "k" }) :: any

function AnimationAsset.new(sequence: KeyframeSequence, nameOverride: string?): AnimationAssetInstance
	assert(sequence:IsA("KeyframeSequence"), "AnimationAsset.new requires a KeyframeSequence")

	local name = nameOverride or sequence.Name

	local bySequence = assetCache[sequence]
	if bySequence ~= nil then
		local cached = bySequence[name]
		if cached ~= nil then
			return cached
		end
	else
		bySequence = {}
		assetCache[sequence] = bySequence
	end

	local self = {} :: AnimationAssetInstance

	self.Name = name
	self.Channels = parseKeyframeSequence(sequence)
	self.Events = extractEvents(sequence)

	-- Duration = last keyframe time
	local last = 0
	local hasKeyframes = false
	for _, keyframe: Instance in ipairs(sequence:GetKeyframes()) do
		if not keyframe:IsA("Keyframe") then
			continue
		end
		hasKeyframes = true
		if keyframe.Time > last then
			last = keyframe.Time
		end
	end
	-- Single-frame clips authored only at t=0 have a computed duration of 0,
	-- which causes tracks to instantly complete. Give them a minimal duration.
	if hasKeyframes and last <= 0 then
		last = 1 / 30
	end
	self.Duration = last
	
	self.GetLength = AnimationAsset.GetLength
	self.GetEventsAt = AnimationAsset.GetEventsAt
	self.Sample = AnimationAsset.Sample

	bySequence[name] = self

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

	for joint, channel in pairs(self.Channels) do
		transforms[joint] = sampleChannel(channel, t)
	end

	return {
		Transforms = transforms,
	}
end

return AnimationAsset