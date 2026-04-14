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
	Play: (self: AnimationPlayerInstance) -> nil,
	Stop: (self: AnimationPlayerInstance) -> nil,
	Update: (self: AnimationPlayerInstance, dt: number) -> any,
}

function AnimationPlayer.new(asset: any, options: AnimationPlayerOptions?): AnimationPlayerInstance
	local self = {} :: AnimationPlayerInstance

	self.Asset = asset
	self.Time = 0
	self.Speed = options and options.Speed or 1
	self.Loop = options and options.Loop or true
	self.FadeInTime = options and options.FadeInTime or 0.2
	self.FadeOutTime = options and options.FadeOutTime or 0.2
	self.Weight = 0
	self.Playing = false
	self._FadeDir = 0

	self.Play = AnimationPlayer.Play
	self.Stop = AnimationPlayer.Stop
	self.Update = AnimationPlayer.Update

	return self
end

function AnimationPlayer.Play(self: AnimationPlayerInstance)
	self.Playing = true
	self.Time = 0
	self.Weight = 0
	self._FadeDir = 1
end

function AnimationPlayer.Stop(self: AnimationPlayerInstance)
	if self.Weight <= 0 then
		self.Playing = false
		self._FadeDir = 0
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
		self.Weight = if self.FadeInTime > 0
			then math.min(1, self.Weight + dt / self.FadeInTime)
			else 1
		if self.Weight >= 1 then
			self._FadeDir = 0
		end
	elseif self._FadeDir == -1 then
		self.Weight = if self.FadeOutTime > 0
			then math.max(0, self.Weight - dt / self.FadeOutTime)
			else 0
		if self.Weight <= 0 then
			self.Playing = false
			self._FadeDir = 0
			return { Transforms = {}, Curves = {} }
		end
	end

	if not self.Asset or not self.Asset.GetLength then
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
		-- Fade out on natural completion instead of instant stop
		if self._FadeDir ~= -1 then
			self._FadeDir = -1
		end
	end

	local sample = self.Asset:Sample(self.Time)
	return sample
end

return AnimationPlayer