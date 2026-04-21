--!strict
-- LookAt: compute a transform that orients a joint toward a target.

local LookAt = {}

function LookAt.Solve(origin: CFrame, target: Vector3, up: Vector3?)
	up = up or Vector3.new(0, 1, 0)
	local direction = (target - origin.Position).Unit
	local right = up:Cross(direction).Unit
	local adjustedUp = direction:Cross(right)
	return CFrame.fromMatrix(origin.Position, direction, adjustedUp)
end

return LookAt