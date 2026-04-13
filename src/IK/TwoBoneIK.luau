--!strict
-- TwoBoneIK: simple two-bone solver for chains like upper arm -> lower arm.

local TwoBoneIK = {}

export type TwoBoneIKResult = {
	JointAngles: { [number]: number },
	ElbowDirection: Vector3,
}

function TwoBoneIK.Solve(rootCFrame: CFrame, midLength: number, endLength: number, target: Vector3, poleVector: Vector3): TwoBoneIKResult
	local rootPos = rootCFrame.Position
	local toTarget = target - rootPos
	local targetDistance = math.clamp(toTarget.Magnitude, 0.0001, midLength + endLength - 0.0001)
	local cosAngle = (midLength^2 + endLength^2 - targetDistance^2) / (2 * midLength * endLength)
	local elbowAngle = math.acos(math.clamp(cosAngle, -1, 1))
	return {
		JointAngles = { math.pi - elbowAngle, 0 },
		ElbowDirection = poleVector.Unit,
	}
end

return TwoBoneIK