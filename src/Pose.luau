--!strict
-- Pose module: represents a joint transform dictionary and provides pose math.

local FluxaTypes = require(script.Parent.FluxaTypes)
type PoseData = FluxaTypes.PoseData
type PoseInstance = FluxaTypes.PoseInstance

local Pose = {}

local function new(data: PoseData?): PoseInstance
	local i = {} :: PoseInstance

	i.Data = data or {}
	i.Clone = Pose.Clone
	i.Lerp = Pose.Lerp
	i.Additive = Pose.Additive
	i.ApplyMask = Pose.ApplyMask

	return i
end

function Pose.Clone(self: PoseInstance)
	local clone: PoseData = table.clone(self.Data)
	return new(clone)
end

function Pose.Lerp(self: PoseInstance, other: PoseInstance, alpha: number)
	local result: PoseData = {}
	for joint: string, transform: CFrame in pairs(self.Data) do
		local target = other.Data[joint]
		if target then
			result[joint] = transform:Lerp(target, alpha)
		else
			result[joint] = transform
		end
	end
	for joint: string, transform: CFrame in pairs(other.Data) do
		result[joint] = transform
	end
	return new(result)
end

function Pose.Additive(self: PoseInstance, addPose: PoseInstance, weight: number)
	local result = {}
	for joint, transform in pairs(self.Data) do
		local addTransform = addPose.Data[joint]
		if addTransform then
			result[joint] = self.Data[joint] * CFrame.new((addTransform.Position - self.Data[joint].Position) * weight)
		else
			result[joint] = transform
		end
	end
	return new(result)
end

function Pose.ApplyMask(self: PoseInstance, mask: { [string]: boolean })
	local result = {}
	for joint, transform in pairs(self.Data) do
		if mask[joint] then
			result[joint] = transform
		end
	end
	return new(result)
end

return {
	new = new,
}