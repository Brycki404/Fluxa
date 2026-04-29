--!strict
-- UniversalJointWriter: applies poses to arbitrary rigs with Motor6Ds and Bones.

local UniversalJointWriter = {}

export type PoseData = { [string]: CFrame }

export type JointInfo = {
	Joint: Motor6D | Bone | AnimationConstraint,
	Name: string,
	Type: "Motor6D" | "Bone" | "AnimationConstraint",
	Aliases: { string },
}

export type JointMap = { [string]: JointInfo }
export type RetargetMap = { [string]: string }

local AMBIGUOUS_ALIAS = ""

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------

local function normalizeName(name: string): string
	return string.lower((name:gsub("[%s%p_]", "")))
end

local function joinPath(parts: { string }): string
	return table.concat(parts, "/")
end

local function getRelativePath(root: Instance, inst: Instance): string
	local parts = {}
	local cursor: Instance? = inst

	while cursor and cursor ~= root do
		table.insert(parts, 1, cursor.Name)
		cursor = cursor.Parent
	end

	if #parts == 0 then
		return inst.Name
	end

	return joinPath(parts)
end

local function getBoneChainPath(bone: Bone): string
	local parts = { bone.Name }
	local cursor = bone.Parent

	while cursor and cursor:IsA("Bone") do
		table.insert(parts, 1, cursor.Name)
		cursor = cursor.Parent
	end

	return joinPath(parts)
end

local function appendAlias(aliases: { string }, seen: { [string]: boolean }, alias: string?)
	if not alias or alias == "" or seen[alias] then
		return
	end

	seen[alias] = true
	table.insert(aliases, alias)

	local normalized = normalizeName(alias)
	if normalized ~= "" and not seen[normalized] then
		seen[normalized] = true
		table.insert(aliases, normalized)
	end
end

local function addRetargetAlias(retarget: RetargetMap, alias: string, canonicalName: string)
	local existing = retarget[alias]
	if existing == nil then
		retarget[alias] = canonicalName
	elseif existing ~= canonicalName then
		retarget[alias] = AMBIGUOUS_ALIAS
	end
end

local function registerAliases(retarget: RetargetMap, canonicalName: string, aliases: { string })
	for _, alias in ipairs(aliases) do
		addRetargetAlias(retarget, alias, canonicalName)
	end
end

local function getCanonicalMotorName(root: Model, motor: Motor6D): string
	-- KeyframeSequence pose channels are authored against the effector part name,
	-- not the Motor6D instance name. Treat Part1 as the motor's canonical target.
	if motor.Part1 then
		return getRelativePath(root, motor.Part1)
	end

	return getRelativePath(root, motor)
end

local function getMotorAliases(root: Model, motor: Motor6D): { string }
	local aliases = {}
	local seen: { [string]: boolean } = {}

	if motor.Part1 then
		appendAlias(aliases, seen, motor.Part1.Name)
		appendAlias(aliases, seen, getRelativePath(root, motor.Part1))
	end

	appendAlias(aliases, seen, motor.Name)
	appendAlias(aliases, seen, getRelativePath(root, motor))

	if motor.Part0 and motor.Part1 then
		appendAlias(aliases, seen, string.format("%s/%s", motor.Part0.Name, motor.Part1.Name))
		appendAlias(aliases, seen, string.format("%s.%s", motor.Part0.Name, motor.Part1.Name))
		appendAlias(aliases, seen, string.format("%s->%s", motor.Part0.Name, motor.Part1.Name))
	end

	return aliases
end

local function getCanonicalAnimConstraintName(root: Model, ac: AnimationConstraint): string
	-- Attachment1 is the effector side; its parent part is the canonical target,
	-- matching how KeyframeSequence channels are named.
	if ac.Attachment1 and ac.Attachment1.Parent then
		return getRelativePath(root, ac.Attachment1.Parent)
	end

	return getRelativePath(root, ac)
end

local function getAnimConstraintAliases(root: Model, ac: AnimationConstraint): { string }
	local aliases = {}
	local seen: { [string]: boolean } = {}

	if ac.Attachment1 and ac.Attachment1.Parent then
		local effector = ac.Attachment1.Parent
		appendAlias(aliases, seen, effector.Name)
		appendAlias(aliases, seen, getRelativePath(root, effector))
	end

	appendAlias(aliases, seen, ac.Name)
	appendAlias(aliases, seen, getRelativePath(root, ac))

	if ac.Attachment0 and ac.Attachment1 then
		local p0 = if ac.Attachment0.Parent then ac.Attachment0.Parent.Name else ac.Attachment0.Name
		local p1 = if ac.Attachment1.Parent then ac.Attachment1.Parent.Name else ac.Attachment1.Name
		appendAlias(aliases, seen, string.format("%s/%s", p0, p1))
		appendAlias(aliases, seen, string.format("%s.%s", p0, p1))
		appendAlias(aliases, seen, string.format("%s->%s", p0, p1))
	end

	return aliases
end

local function getCanonicalBoneName(bone: Bone): string
	return getBoneChainPath(bone)
end

local function getBoneAliases(root: Model, bone: Bone): { string }
	local aliases = {}
	local seen: { [string]: boolean } = {}

	appendAlias(aliases, seen, bone.Name)
	appendAlias(aliases, seen, getBoneChainPath(bone))
	appendAlias(aliases, seen, getRelativePath(root, bone))

	return aliases
end

---------------------------------------------------------------------
-- BUILD JOINT MAP + RETARGET MAP
---------------------------------------------------------------------

function UniversalJointWriter.BuildJointMap(root: Model): (JointMap, RetargetMap)
	local jointMap: JointMap = {}
	local retarget: RetargetMap = {}

	local descendants = root:GetDescendants()
	local classCounts: { [string]: number } = {}
	for _, inst in ipairs(descendants) do
		local cn = inst.ClassName
		classCounts[cn] = (classCounts[cn] or 0) + 1
	end
	-- print("BuildJointMap: root =", root.Name, "| total descendants =", #descendants)
	-- for cn, count in pairs(classCounts) do
		-- print(string.format("  class %-30s x%d", cn, count))
	-- end

	for _, inst in ipairs(descendants) do
		if inst:IsA("Motor6D") then
			local canonicalName = getCanonicalMotorName(root, inst)
			local aliases = getMotorAliases(root, inst)

			jointMap[canonicalName] = {
				Joint = inst,
				Name = canonicalName,
				Type = "Motor6D",
				Aliases = aliases,
			}

			registerAliases(retarget, canonicalName, aliases)
			addRetargetAlias(retarget, canonicalName, canonicalName)

		elseif inst:IsA("AnimationConstraint") then
			local canonicalName = getCanonicalAnimConstraintName(root, inst)
			local aliases = getAnimConstraintAliases(root, inst)

			jointMap[canonicalName] = {
				Joint = inst,
				Name = canonicalName,
				Type = "AnimationConstraint",
				Aliases = aliases,
			}

			registerAliases(retarget, canonicalName, aliases)
			addRetargetAlias(retarget, canonicalName, canonicalName)

		elseif inst:IsA("Bone") then
			local canonicalName = getCanonicalBoneName(inst)
			local aliases = getBoneAliases(root, inst)

			jointMap[canonicalName] = {
				Joint = inst,
				Name = canonicalName,
				Type = "Bone",
				Aliases = aliases,
			}

			registerAliases(retarget, canonicalName, aliases)
			addRetargetAlias(retarget, canonicalName, canonicalName)
		end
	end

	-- print(jointMap, retarget)

	return jointMap, retarget
end

---------------------------------------------------------------------
-- APPLY POSE WITH RETARGETING
---------------------------------------------------------------------

function UniversalJointWriter.ApplyPose(jointMap: JointMap, retarget: RetargetMap, pose: PoseData)
	for poseName, cf in pairs(pose) do
		local normalizedPoseName = normalizeName(poseName)
		local rigName = retarget[poseName] or retarget[normalizedPoseName] or poseName

		if rigName ~= AMBIGUOUS_ALIAS then
			local info = jointMap[rigName]
			if info then
				if info.Type == "Motor6D" then
					(info.Joint :: Motor6D).Transform = cf
				elseif info.Type == "AnimationConstraint" then
					(info.Joint :: AnimationConstraint).Transform = cf
				else
					(info.Joint :: Bone).Transform = cf
				end
			end
		end
	end
end

return UniversalJointWriter