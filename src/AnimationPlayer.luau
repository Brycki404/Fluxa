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

	self.Play = AnimationPlayer.Play
	self.Stop = AnimationPlayer.Stop
	self.Update = AnimationPlayer.Update

	return self
end

function AnimationPlayer.Play(self: AnimationPlayerInstance)
	self.Playing = true
	self.Time = 0
	self.Weight = 0
end

function AnimationPlayer.Stop(self: AnimationPlayerInstance)
	self.Playing = false
	self.Weight = 0
end

function AnimationPlayer.Update(self: AnimationPlayerInstance, dt: number)
	if not self.Playing or not self.Asset or not self.Asset.GetLength then
		return { Transforms = {}, Curves = {} }
	end

	self.Time = self.Time + dt * self.Speed
	local duration = self.Asset:GetLength()
	if self.Loop and duration > 0 then
		self.Time = self.Time % duration
	elseif self.Time > duration then
		self.Time = duration
		self.Playing = false
	end

	local sample = self.Asset:Sample(self.Time)
	return sample
end

return AnimationPlayer