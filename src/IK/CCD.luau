--!strict
-- CCD: cyclic coordinate descent solver for robotic-style joint chains.

local CCD = {}

function CCD.Solve(positions: { Vector3 }, target: Vector3, maxIterations: number?, tolerance: number?)
	local safeMaxIterations: number = maxIterations or 12
	local safeTolerance: number = tolerance or 0.01
	local points: { Vector3 } = table.clone(positions)

	for _: number = 1, safeMaxIterations do
		for i: number = #points - 1, 1, -1 do
			local current = points[i]
			local endEffector = points[#points]
			local targetDir = (target - current).Unit
			local effectorDir = (endEffector - current).Unit
			local angle = math.acos(math.clamp(targetDir:Dot(effectorDir), -1, 1))
			if angle > safeTolerance then
				local axis = targetDir:Cross(effectorDir).Unit
				local rotation = CFrame.fromAxisAngle(axis, angle)
				for j = i + 1, #points do
					points[j] = (rotation * CFrame.new(points[j] - current)).Position + current
				end
			end
		end
		if (points[#points] - target).Magnitude <= safeTolerance then
			break
		end
	end

	return points
end

return CCD