--!strict
-- FootPlanting: simple foot placement helper for contact and ground alignment.

local FootPlanting = {}

function FootPlanting.AlignFoot(footCFrame: CFrame, groundNormal: Vector3, targetPosition: Vector3)
	local up = groundNormal.Unit
	local forward = (footCFrame.LookVector - up * footCFrame.LookVector:Dot(up)).Unit
	local rotation = CFrame.fromMatrix(targetPosition, forward, up)
	return rotation
end

return FootPlanting