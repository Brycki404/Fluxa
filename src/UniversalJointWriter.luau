--!strict
-- UniversalJointWriter: applies poses to Motor6Ds AND Bones with auto-retargeting.

local UniversalJointWriter = {}

export type PoseData = { [string]: CFrame }

export type JointInfo = {
	Joint: Motor6D | Bone,
	Name: string,         -- canonical joint name
	Type: "Motor6D" | "Bone",
}

export type JointMap = { [string]: JointInfo }

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------

-- Derive a stable joint name for Motor6Ds:
-- Prefer Motor6D.Name, but fall back to Part1.Name.
local function getMotor6DName(motor: Motor6D): string
	if motor.Name and motor.Name ~= "" then
		return motor.Name
	end
	if motor.Part1 then
		return motor.Part1.Name
	end
	return "UnknownMotor6D"
end

local function getBoneName(bone: Bone): string
	return bone.Name
end

---------------------------------------------------------------------
-- BUILD JOINT MAP + RETARGET MAP
---------------------------------------------------------------------

function UniversalJointWriter.BuildJointMap(root: Model)
	local jointMap: JointMap = {}
	local retarget: { [string]: string } = {}

	-- First pass: collect joints
	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("Motor6D") then
			local name = getMotor6DName(inst)
			jointMap[name] = {
				Joint = inst,
				Name = name,
				Type = "Motor6D",
			}

			-- Auto-retarget: map Part1.Name → Motor6D.Name
			if inst.Part1 then
				retarget[inst.Part1.Name] = name
			end

		elseif inst:IsA("Bone") then
			local name = getBoneName(inst)
			jointMap[name] = {
				Joint = inst,
				Name = name,
				Type = "Bone",
			}

			-- Bones already match animation names
			retarget[name] = name
		end
	end

	return jointMap, retarget
end

---------------------------------------------------------------------
-- APPLY POSE WITH RETARGETING
---------------------------------------------------------------------

function UniversalJointWriter.ApplyPose(jointMap: JointMap, retarget: { [string]: string }, pose: PoseData)
	for poseName, cf in pairs(pose) do
		-- Convert animation joint name → rig joint name
		local rigName = retarget[poseName]
		if rigName then
			local info = jointMap[rigName]
			if info then
				if info.Type == "Motor6D" then
					(info.Joint :: Motor6D).Transform = cf
				else
					(info.Joint :: Bone).Transform = cf
				end
			end
		end
	end
end

return UniversalJointWriter