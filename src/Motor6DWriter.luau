--!strict
-- Motor6DWriter: apply a final pose to a model using Motor6D.Transform.

local Motor6DWriter = {}

export type JointMap = { [string]: Motor6D }

export type PoseData = { [string]: CFrame }

function Motor6DWriter.ApplyPose(root: Model, pose: PoseData)
	for _, motor in ipairs(root:GetDescendants()) do
		if motor:IsA("Motor6D") then
			local transform = pose[motor.Name]
			if transform then
				motor.Transform = transform
			end
		end
	end
end

function Motor6DWriter.BuildJointMap(root: Model)
	local map: JointMap = {}
	for _, motor in ipairs(root:GetDescendants()) do
		if motor:IsA("Motor6D") then
			map[motor.Name] = motor
		end
	end
	return map
end

return Motor6DWriter