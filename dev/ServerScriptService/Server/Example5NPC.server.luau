--!nonstrict
-- Example5 NPC demo: when a player's first character loads, create one server-owned NPC clone
-- that randomly walks around and replicates Fluxa controller state to relevant clients.

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local BASE_WALK_SPEED = 3
local MAX_RUN_SPEED = 24
local MOMENTUM_BUILD_RATE = 0.8
local NPC_WANDER_RADIUS = 36
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

do
	-- Use premade ServerNPC from Workspace
	local npcCharacter = workspace:FindFirstChild("ServerNPC")
	if not npcCharacter then
		warn("Example5NPC: No premade ServerNPC found in Workspace!")
		return
	end

	local humanoid = npcCharacter:FindFirstChildOfClass("Humanoid")
	local root = npcCharacter:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		npcCharacter:Destroy()
		return
	end

	root:SetNetworkOwner(nil)

	local npcId = game:GetService("HttpService"):GenerateGUID(false)
	local record = {
		Id = npcId;
		Model = npcCharacter;
		Humanoid = humanoid;
		Root = root;
		Origin = root.Position;
	}

	npcCharacter:SetAttribute(FLUXA_NPC_ID_ATTRIBUTE, npcId)
	CollectionService:AddTag(npcCharacter, FLUXA_NPC_TAG)

	-- No Fluxa replication, only momentum and movement logic
	startRandomWalkLoop(record)
end