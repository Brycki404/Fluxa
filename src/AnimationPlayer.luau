--!strict
-- AnimationPlayer: play AnimationAsset instances with speed, looping, fade, and events.

local AnimationPlayer = {}

export type AnimationPlayerOptions = {
	Speed: number?,
	Loop: boolean?,
	FadeInTime: number?,
	FadeOutTime: number?,
}

export type AnimationPlayerInstance = {
	Asset: any,
	Time: number,
	Speed: number,
	Loop: boolean,
	FadeInTime: number,
	FadeOutTime: number,
	Weight: number,
	Playing: boolean,
	_FadeDir: number,
	_ActiveFadeInTime: number,
	_ActiveFadeOutTime: number,
	Play: (self: AnimationPlayerInstance, fadeInTime: number?) -> nil,
	Stop: (self: AnimationPlayerInstance, fadeOutTime: number?) -> nil,
	Update: (self: AnimationPlayerInstance, dt: number) -> any,
}

function AnimationPlayer.new(asset: any, options: AnimationPlayerOptions?): AnimationPlayerInstance
	local self = {} :: AnimationPlayerInstance

	self.Asset = asset
	self.Time = 0
	self.Speed = if options and options.Speed ~= nil then options.Speed else 1
	self.Loop = if options and options.Loop ~= nil then options.Loop else true
	self.FadeInTime = if options and options.FadeInTime ~= nil then options.FadeInTime else 0.2
	self.FadeOutTime = if options and options.FadeOutTime ~= nil then options.FadeOutTime else 0.2
	self.Weight = 0
	self.Playing = false
	self._FadeDir = 0
	self._ActiveFadeInTime = self.FadeInTime
	self._ActiveFadeOutTime = self.FadeOutTime

	self.Play = AnimationPlayer.Play
	self.Stop = AnimationPlayer.Stop
	self.Update = AnimationPlayer.Update

	return self
end

function AnimationPlayer.Play(self: AnimationPlayerInstance, fadeInTime: number?)
	local resolvedFadeIn = if fadeInTime ~= nil then fadeInTime else self.FadeInTime
	self._ActiveFadeInTime = resolvedFadeIn
	self.Playing = true
	self.Time = 0
	if resolvedFadeIn <= 0 then
		self.Weight = 1
		self._FadeDir = 0
	else
		self.Weight = 0
		self._FadeDir = 1
	end
end

function AnimationPlayer.Stop(self: AnimationPlayerInstance, fadeOutTime: number?)
	local resolvedFadeOut = if fadeOutTime ~= nil then fadeOutTime else 0
	self._ActiveFadeOutTime = resolvedFadeOut

	if resolvedFadeOut <= 0 or self.Weight <= 0 then
		self.Playing = false
		self._FadeDir = 0
		self.Weight = 0
	else
		self._FadeDir = -1
	end
end

function AnimationPlayer.Update(self: AnimationPlayerInstance, dt: number)
	if not self.Playing then
		return { Transforms = {}, Curves = {} }
	end

	-- Advance fade weight
	if self._FadeDir == 1 then
		self.Weight = if self._ActiveFadeInTime > 0
			then math.min(1, self.Weight + dt / self._ActiveFadeInTime)
			else 1
		if self.Weight >= 1 then
			self._FadeDir = 0
		end
	elseif self._FadeDir == -1 then
		self.Weight = if self._ActiveFadeOutTime > 0
			then math.max(0, self.Weight - dt / self._ActiveFadeOutTime)
			else 0
		if self.Weight <= 0 then
			self.Playing = false
			self._FadeDir = 0
			self.Weight = 0
			return { Transforms = {}, Curves = {} }
		end
	end

	if not self.Asset or not self.Asset.GetLength then
		self.Playing = false
		self._FadeDir = 0
		self.Weight = 0
		return { Transforms = {}, Curves = {} }
	end

	local duration = self.Asset:GetLength()

	-- Advance time; freeze at end for completed non-looping animations
	if self.Loop or self.Time < duration then
		self.Time = self.Time + dt * self.Speed
	end

	if self.Loop and duration > 0 then
		self.Time = self.Time % duration
	elseif self.Time >= duration then
		self.Time = duration
		-- Fade out on natural completion instead of instant stop.
		if self._FadeDir ~= -1 then
			self._FadeDir = -1
		end
	end

	local sample = self.Asset:Sample(self.Time)
	return sample
end

return AnimationPlayer