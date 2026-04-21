--!strict
-- FABRIK: iterative inverse kinematics solver for multi-bone chains.

local FABRIK = {}

local function sum(nums: {number}): number
	local total = 0
	for _: number, num: number in ipairs(nums) do
		total += num
	end
	return total
end

function FABRIK.Solve(points: { Vector3 }, target: Vector3, iterations: number?, tolerance: number?)
	local safeIterations: number = iterations or 10
	local safeTolerance: number = tolerance or 0.001
	local positions: { Vector3 } = table.clone(points)
	local root = positions[1]
	local distances = {}
	for i = 1, #positions - 1 do
		distances[i] = (positions[i + 1] - positions[i]).Magnitude
	end

	if (root - target).Magnitude > sum(distances) then
		for i = 1, #positions - 1 do
			local direction = (target - positions[i]).Unit
			positions[i + 1] = positions[i] + direction * distances[i]
		end
		return positions
	end

	for _ = 1, safeIterations do
		positions[#positions] = target
		for i = #positions - 1, 1, -1 do
			local direction = (positions[i] - positions[i + 1]).Unit
			positions[i] = positions[i + 1] + direction * distances[i]
		end
		positions[1] = root
		for i = 1, #positions - 1 do
			local direction = (positions[i + 1] - positions[i]).Unit
			positions[i + 1] = positions[i] + direction * distances[i]
		end
		if (positions[#positions] - target).Magnitude <= safeTolerance then
			break
		end
	end

	return positions
end

return FABRIK