--!strict
-- Retargeting: map joints between rigs and scale animation poses for retargeted skeletons.

local FluxaTypes = require(script.Parent.FluxaTypes)
type RetargetMap = FluxaTypes.RetargetMap
type RetargetOptions = FluxaTypes.RetargetOptions

local Retargeting = {}

function Retargeting.MapPose(pose: { [string]: CFrame }, map: RetargetMap, options: RetargetOptions?)
	local result: { [string]: CFrame } = {}
	local scale = if options ~= nil and options.Scale ~= nil then options.Scale else 1
	for sourceJoint, targetJoint in pairs(map) do
		local transform = pose[sourceJoint]
		if transform then
			result[targetJoint] = CFrame.new(transform.Position * scale) * CFrame.Angles(transform:ToEulerAnglesXYZ())
		end
	end
	return result
end

return Retargeting