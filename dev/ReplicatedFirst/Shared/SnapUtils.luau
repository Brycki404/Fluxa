local module = {}

function module.snapPosition(v: Vector3): Vector3
	return Vector3.new(
		math.round(v.X * 1000) / 1000,
		math.round(v.Y * 1000) / 1000,
		math.round(v.Z * 1000) / 1000
	)
end

function module.snapAngle(radians: number): number
	local degrees = math.deg(radians)
	local snapped = math.round(degrees * 2) / 2 -- 0.5° increments
	return math.rad(snapped)
end

function module.snapCFrame(cf: CFrame): CFrame
	local pos = module.snapPosition(cf.Position)

	local _, _, _, 
	r00, r01, r02,
	r10, r11, r12,
	r20, r21, r22 = cf:GetComponents()

	local sx, sy, sz = cf:ToEulerAnglesXYZ()

	local rx = module.snapAngle(sx)
	local ry = module.snapAngle(sy)
	local rz = module.snapAngle(sz)

	return CFrame.new(pos) * CFrame.Angles(rx, ry, rz)
end

return module
