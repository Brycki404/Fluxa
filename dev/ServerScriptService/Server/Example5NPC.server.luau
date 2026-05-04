--!nonstrict
-- Example5 NPC demo: spawn a configurable number of server-owned NPCs from a
-- workspace template and run simple wander logic on each one.

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local BASE_WALK_SPEED = 3
local MAX_RUN_SPEED = 24
local MOMENTUM_BUILD_RATE = 0.8
local NPC_WANDER_RADIUS = 36
local SERVER_NPC_COUNT = 20
local SERVER_NPC_SPACING = 12
local SERVER_NPC_TEMPLATE_NAME = "ServerNPC"
local FLUXA_NPC_TAG = "FluxaNPC"
local FLUXA_NPC_ID_ATTRIBUTE = "FluxaNPCId"

-- No FluxaController needed on the server for NPCs
local function startRandomWalkLoop(record)
	task.spawn(function()
		local npc = record.Model
		local humanoid = record.Humanoid
		local root = record.Root
		local origin = record.Origin

		RunService.Heartbeat:Connect(function(dt)
			local vel = root.AssemblyLinearVelocity
			local planarSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			local isMoving = planarSpeed > 0.1
			local momentum = root:GetAttribute("Momentum") or 0

			if not isMoving then
				momentum = 0
			else
				momentum = math.clamp(momentum + MOMENTUM_BUILD_RATE * dt, 0, 1)
			end

			humanoid.WalkSpeed = BASE_WALK_SPEED + (MAX_RUN_SPEED - BASE_WALK_SPEED) * momentum
			root:SetAttribute("Momentum", momentum)
		end)


		while npc.Parent ~= nil and humanoid.Parent ~= nil and root.Parent ~= nil do
			local offset = Vector3.new(
				math.random(-NPC_WANDER_RADIUS, NPC_WANDER_RADIUS),
				0,
				math.random(-NPC_WANDER_RADIUS, NPC_WANDER_RADIUS)
			)
			local destination = origin + offset
			humanoid:MoveTo(destination)
			local reached = humanoid.MoveToFinished:Wait()
			if not reached then
				task.wait(0.25)
			else
				task.wait(math.random() * 0.75 + 0.25)
			end
		end
	end)
end

local function prepareNPCModel(npcCharacter)
	local humanoid = npcCharacter:FindFirstChildOfClass("Humanoid")
	local root = npcCharacter:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		npcCharacter:Destroy()
		return nil
	end

	root:SetNetworkOwner(nil)

	local npcId = HttpService:GenerateGUID(false)
	npcCharacter:SetAttribute(FLUXA_NPC_ID_ATTRIBUTE, npcId)
	CollectionService:AddTag(npcCharacter, FLUXA_NPC_TAG)

	return {
		Id = npcId,
		Model = npcCharacter,
		Humanoid = humanoid,
		Root = root,
		Origin = root.Position,
	}
end

local function getSpawnOffset(index)
	if index <= 1 then
		return Vector3.zero
	end

	local row = math.floor((index - 1) / 3)
	local column = (index - 1) % 3
	return Vector3.new(column * SERVER_NPC_SPACING, 0, row * SERVER_NPC_SPACING)
end

do
	local template = workspace:FindFirstChild(SERVER_NPC_TEMPLATE_NAME)
	if template == nil or not template:IsA("Model") then
		warn(("Example5NPC: No premade %s model found in Workspace!"):format(SERVER_NPC_TEMPLATE_NAME))
		return
	end

	if SERVER_NPC_COUNT <= 0 then
		template:Destroy()
		return
	end

	local templatePivot = template:GetPivot()
	for index = 1, SERVER_NPC_COUNT do
		local npcCharacter = if index == 1 then template else template:Clone()
		npcCharacter.Name = if index == 1 then SERVER_NPC_TEMPLATE_NAME else (`{SERVER_NPC_TEMPLATE_NAME}_{index}`)
		npcCharacter:PivotTo(templatePivot + getSpawnOffset(index))
		npcCharacter.Parent = workspace

		local record = prepareNPCModel(npcCharacter)
		if record ~= nil then
			startRandomWalkLoop(record)
		end
	end
end