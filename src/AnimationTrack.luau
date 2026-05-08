--!strict
-- AnimationTrack: play AnimationAsset instances with speed, looping, fade, and events.

local AnimationTrack = {}
local Signal = require(script.Parent.Signal)
local FluxaTypes = require(script.Parent.FluxaTypes)

-- Type Imports
type AnimationTrackInstance = FluxaTypes.AnimationTrackInstance
type AnimationTrackOptions = FluxaTypes.AnimationTrackOptions
type SignalType = FluxaTypes.SignalType

local function emitStopped(self: AnimationTrackInstance)
	if self._StoppedFired then
		return
	end
	self._StoppedFired = true
	self.Stopped:Fire()
end

local function emitEnded(self: AnimationTrackInstance)
	if self._EndedFired then
		return
	end
	self._EndedFired = true
	self.Ended:Fire()
end

local function fireMarkerSignals(self: AnimationTrackInstance, startTime: number, endTime: number)
	if not self.Asset or not self.Asset.Events then
		return
	end

	for _, event in ipairs(self.Asset.Events) do
		if event.Time > startTime and event.Time <= endTime then
			self.KeyframeReached:Fire(event.Name)
			local markerSignal = self._MarkerSignals[event.Name]
			if markerSignal then
				markerSignal:Fire(event.Value)
			end
		end
	end
end

function AnimationTrack.new(asset: any, options: AnimationTrackOptions?): AnimationTrackInstance
	local self = {} :: AnimationTrackInstance

	self.Asset = asset
	self.Animation = asset
	self.Length = if asset and asset.GetLength then asset:GetLength() else 0
	self.Time = 0
	self.TimePosition = 0
	self.Speed = if options and options.Speed ~= nil then options.Speed else 1
	self.Looped = if options and options.Looped ~= nil then options.Looped else true
	self.FadeInTime = if options and options.FadeInTime ~= nil then options.FadeInTime else 0.2
	self.FadeOutTime = if options and options.FadeOutTime ~= nil then options.FadeOutTime else 0.2
	self.Weight = 0
	self.FadedWeight = 0
	self.IsPlaying = false
	self.Stopped = Signal.new()
	self.Ended = Signal.new()
	self.DidLoop = Signal.new()
	self.KeyframeReached = Signal.new()
	self.FadeWeight = 0
	self._FadeDir = 0
	self._ActiveFadeInTime = self.FadeInTime
	self._ActiveFadeOutTime = self.FadeOutTime
	self._PendingFadeOut = false
	self._MarkerSignals = {}
	self._StoppedFired = false
	self._EndedFired = false

	self.Play = AnimationTrack.Play
	self.Stop = AnimationTrack.Stop
	self.AdjustSpeed = AnimationTrack.AdjustSpeed
	self.GetMarkerReachedSignal = AnimationTrack.GetMarkerReachedSignal
	self.GetTimeOfKeyframe = AnimationTrack.GetTimeOfKeyframe
	self.Destroy = AnimationTrack.Destroy
	self.Update = AnimationTrack.Update

	return self
end

function AnimationTrack.Play(self: AnimationTrackInstance, fadeInTime: number?, weight: number?, speed: number?)
	local resolvedFadeIn = if fadeInTime ~= nil then fadeInTime else self.FadeInTime
	local resolvedWeight = if weight ~= nil then math.clamp(weight, 0, 1) else 1
	self._ActiveFadeInTime = resolvedFadeIn
	self.Weight = resolvedWeight
	if speed ~= nil then
		self.Speed = speed
	end
	self.IsPlaying = true
	self.Time = 0
	self.TimePosition = 0
	self._StoppedFired = false
	self._EndedFired = false
	self._PendingFadeOut = false
	if resolvedFadeIn <= 0 then
		self.FadeWeight = 1
		self.FadedWeight = self.Weight
		self._FadeDir = 0
	else
		self.FadeWeight = 0
		self.FadedWeight = 0
		self._FadeDir = 1
	end
end

function AnimationTrack.Stop(self: AnimationTrackInstance, fadeOutTime: number?)
	if self.FadedWeight <= 0 and self._FadeDir == 0 then
		return
	end
	self.IsPlaying = false
	local resolvedFadeOut = if fadeOutTime ~= nil then fadeOutTime else self.FadeOutTime
	self._ActiveFadeOutTime = resolvedFadeOut
	emitStopped(self)

	if resolvedFadeOut <= 0 or self.FadedWeight <= 0 then
		self._FadeDir = 0
		self.FadeWeight = 0
		self.FadedWeight = 0
		emitEnded(self)
	else
		self._FadeDir = -1
	end
end

function AnimationTrack.AdjustSpeed(self: AnimationTrackInstance, speed: number)
	self.Speed = speed
end

function AnimationTrack.GetMarkerReachedSignal(self: AnimationTrackInstance, markerName: string): SignalType
	local existing = self._MarkerSignals[markerName]
	if existing then
		return existing
	end

	local signal = Signal.new()
	self._MarkerSignals[markerName] = signal
	return signal
end

function AnimationTrack.GetTimeOfKeyframe(self: AnimationTrackInstance, keyframeName: string): number
	if not self.Asset or not self.Asset.Events then
		error(("No keyframes available for '%s'"):format(keyframeName), 2)
	end

	for _, event in ipairs(self.Asset.Events) do
		if event.Name == keyframeName then
			return event.Time
		end
	end

	error(("Keyframe '%s' not found"):format(keyframeName), 2)
end

function AnimationTrack.Destroy(self: AnimationTrackInstance)
	self:Stop(0)
	self.Stopped:DisconnectAll()
	self.Ended:DisconnectAll()
	self.DidLoop:DisconnectAll()
	self.KeyframeReached:DisconnectAll()
	for _, signal in pairs(self._MarkerSignals) do
		signal:DisconnectAll()
	end
	self._MarkerSignals = {}
end

function AnimationTrack.Update(self: AnimationTrackInstance, dt: number)
	-- Looped tracks always advance time. Non-looped skip if there is no fade activity.
	if not self.Looped and self.FadedWeight <= 0 and self._FadeDir == 0 then
		return { Transforms = {}, Curves = {} }
	end

	-- Advance fade weight
	if self._FadeDir == 1 then
		self.FadeWeight = if self._ActiveFadeInTime > 0
			then math.min(1, self.FadeWeight + dt / self._ActiveFadeInTime)
			else 1
		if self.FadeWeight >= 1 then
			self._FadeDir = 0
			if self._PendingFadeOut then
				self._PendingFadeOut = false
				self._FadeDir = -1
			end
		end
	elseif self._FadeDir == -1 then
		self.FadeWeight = if self._ActiveFadeOutTime > 0
			then math.max(0, self.FadeWeight - dt / self._ActiveFadeOutTime)
			else 0
		if self.FadeWeight <= 0 then
			self._FadeDir = 0
			self.FadeWeight = 0
			self.FadedWeight = 0
			emitEnded(self)
			return { Transforms = {}, Curves = {} }
		end
	end
	self.FadedWeight = self.Weight * self.FadeWeight

	if not self.Asset or not self.Asset.GetLength then
		self._FadeDir = 0
		self.FadeWeight = 0
		self.FadedWeight = 0
		emitStopped(self)
		emitEnded(self)
		return { Transforms = {}, Curves = {} }
	end

	local duration = self.Asset:GetLength()
	local previousTime = self.Time
	local newTime = self.Time

	-- Advance time; freeze at end for completed non-looping animations
	if self.Looped or self.Time < duration then
		newTime = self.Time + dt * self.Speed
	end

	if self.Looped and duration > 0 then
		local oldLoops = math.floor(previousTime / duration)
		local newLoops = math.floor(newTime / duration)
		for _ = 1, math.max(0, newLoops - oldLoops) do
			self.DidLoop:Fire()
		end

		local wrappedTime = newTime % duration
		if wrappedTime < previousTime then
			fireMarkerSignals(self, previousTime, duration)
			fireMarkerSignals(self, 0, wrappedTime)
		else
			fireMarkerSignals(self, previousTime, wrappedTime)
		end
		self.Time = wrappedTime
	elseif newTime >= duration then
		self.Time = duration
		fireMarkerSignals(self, previousTime, duration)
		-- Natural completion: if still fading in, defer the fade-out until fade-in finishes.
		if self._FadeDir == 1 then
			self._PendingFadeOut = true
		elseif self._FadeDir == 0 then
			self._FadeDir = -1
		end
		emitStopped(self)
	else
		self.Time = newTime
		fireMarkerSignals(self, previousTime, self.Time)
	end

	self.TimePosition = self.Time

	local sample = self.Asset:Sample(self.Time)
	return sample
end

return AnimationTrack