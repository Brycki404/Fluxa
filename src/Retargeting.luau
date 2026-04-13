--!strict
-- Retargeting: map joints between rigs and scale animation poses for retargeted skeletons.

local Retargeting = {}

export type RetargetMap = { [string]: string }

export type RetargetOptions = {
	Scale: number?,
}

function Retargeting.MapPose(pose: { [string]: CFrame }, map: RetargetMap, options: RetargetOptions?)
	local result: { [string]: CFrame } = {}
	local scale = options and options.Scale or 1
	for sourceJoint, targetJoint in pairs(map) do
		local transform = pose[sourceJoint]
		if transform then
			result[targetJoint] = CFrame.new(transform.Position * scale) * CFrame.Angles(transform:ToEulerAnglesXYZ())
		end
	end
	return result
end

return Retargeting