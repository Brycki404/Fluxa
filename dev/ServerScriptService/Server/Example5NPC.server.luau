--!nonstrict
-- Example5 NPC demo: when a player's first character loads, create one server-owned NPC clone
-- that randomly walks around and replicates Fluxa controller state to relevant clients.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Fluxa = require(ReplicatedStorage.Packages.fluxa)
local FluxaController = Fluxa.FluxaController
local FluxaAssetManager = Fluxa.FluxaAssetManager
local FluxaBindingSetManager = Fluxa.FluxaBindingSetManager
local FluxaService = Fluxa.FluxaService
local Example5BindingCatalog = require(ReplicatedStorage.Examples.Example5BindingCatalog)

local SLOW_WALK_SPEED = 3
local BASE_WALK_SPEED = 3
local MAX_RUN_SPEED = 24
local MOMENTUM_BUILD_RATE = 0.8
local MOMENTUM_DECAY_RATE = 0.4
local SPEED_SMOOTH_SPEED = 10
local LAND_RETRIGGER_COOLDOWN = 0.12
local LAND_FADE_HALF_SPEED = 9
local LAND_LAYER_WEIGHT_SMOOTH_SPEED = 12
local LAND_WEIGHT_SPEED_EASE_POWER = 1.5
local MAX_TURN_LEAN_DEG = 14
local TURN_LEAN_SENSITIVITY = 0.2
local TURN_LEAN_SMOOTH_SPEED = 10
local MIN_LEAN_SCALE = 0.2
local LOCOMOTION_MIN_CYCLE_RATE = 0.8
local LOCOMOTION_MAX_CYCLE_RATE = 2.0
local CLIMB_MIN_CYCLE_RATE = 0.8
local CLIMB_MAX_CYCLE_RATE = 1.8
local NPC_RELEVANCE_RADIUS = 220
local NPC_WANDER_RADIUS = 36
local FLUXA_NPC_TAG = "FluxaNPC"
local FLUXA_NPC_ID_ATTRIBUTE = "FluxaNPCId"

local spawnedPlayers = {}
local npcRecords = {}
local sharedAssetManager = nil
local sharedBindingSetManager = nil

local function getLayerBlend(controller, layerName, paramName, fallback)
	local value = controller:GetLayerDriver(layerName, paramName, false)
	if value ~= nil then
		return value
	end
	return fallback
end

local function setLayerBlend(controller, layerName, paramName, value)
	controller:SetLayerDriver(layerName, paramName, value)
	return value
end

local function getBaseBlend(controller, paramName, fallback)
	return getLayerBlend(controller, "Base", paramName, fallback)
end

local function setBaseBlend(controller, paramName, value)
	return setLayerBlend(controller, "Base", paramName, value)
end

local function getBaseState(controller)
	return getLayerBlend(controller, "Base", "State", "Ground")
end

local function setBaseState(controller, stateName)
	controller:SetLayerDriver("Base", "State", stateName)
	return stateName
end

local function getYaw(cf)
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function deltaAngle(a, b)
	return (a - b + math.pi) % (2 * math.pi) - math.pi
end

local function syncTrackPhase(track, phase)
	if not track then
		return
	end
	local asset = track.Asset
	if not asset or not asset.GetLength then
		return
	end
	local duration = asset:GetLength()
	if duration and duration > 0 and track.Time ~= nil then
		track.Time = phase * duration
	end
end

local function getLandMovingSpeedAlpha(planarSpeed)
	local speed = math.max(0, planarSpeed)
	local half = math.max(1e-3, LAND_FADE_HALF_SPEED)
	return math.clamp(speed / (speed + half), 0, 1)
end

local function createBindingSetManager(folder: Instance?)
	if sharedBindingSetManager ~= nil then
		return sharedBindingSetManager
	end

	sharedAssetManager = sharedAssetManager or FluxaAssetManager.new()
	sharedBindingSetManager = FluxaBindingSetManager.new({
		Catalog = Example5BindingCatalog,
		AssetManager = sharedAssetManager,
		SourceContainer = folder,
	})

	return sharedBindingSetManager
end

local function disableBuiltInCharacterAnimation(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		
		-- Do NOT destroy Animator
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("LocalScript") or descendant:IsA("Script") then
			descendant:Destroy()
		end
	end
end

local function createServerController(character: Model, bindingSetManager)
	local upperBodyMask = {
		"UpperTorso",
		"Torso",
		"LeftUpperArm",
		"LeftLowerArm",
		"LeftHand",
		"RightUpperArm",
		"RightLowerArm",
		"RightHand",
		"Head",
	}

	local landTrack = nil
	local slowWalkTrack = nil
	local walkTrack = nil
	local runTrack = nil
	local climbTrack = nil
	local landingWeightSmoothed = 0
	local locomotionPhase = 0
	local trackConfigs = {
		Idle = { Layer = "Base", AutoManage = true, InitialWeight = 1, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.2, FadeOutTime = 0.2 } },
		Walk = { Layer = "Base", AutoManage = true, PreservePhaseOnSwap = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.2, FadeOutTime = 0.2 } },
		Run = { Layer = "Base", AutoManage = true, PreservePhaseOnSwap = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.18, FadeOutTime = 0.2 } },
		SlowWalk = { Layer = "Base", AutoManage = true, PreservePhaseOnSwap = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.2, FadeOutTime = 0.24 } },
		Jump = { Layer = "Base", AutoManage = false, ReplicationSeekMode = "Never", TrackOptions = { Looped = false, Speed = 1, FadeInTime = 0.08, FadeOutTime = 0.16 } },
		Fall = { Layer = "Base", AutoManage = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.14, FadeOutTime = 0.18 } },
		Land = { Layer = "Landing", AutoManage = false, ReplicationSeekMode = "Never", TrackOptions = { Looped = false, Speed = 1, FadeInTime = 0.08, FadeOutTime = 0.08 } },
		Climb = { Layer = "Base", AutoManage = true, PreservePhaseOnSwap = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.18, FadeOutTime = 0.22 } },
		Attack = { Layer = "UpperBody", AutoManage = false, InitialWeight = 0, ReplicationSeekMode = "Never", TrackOptions = { Looped = false, Speed = 1, FadeInTime = 0.08, FadeOutTime = 0.14 } },
	}

	local controller = FluxaController.new({
		Character = character,
		AutoApplyPose = false,
		AutoStart = true,
		ReplicationSeekMode = "LoopingOnly",
		ReplicateTrackBindings = true,
		ReplicationMode = "ServerOwned",
		OnPreStep = function(innerController, dt)
			local smoothedPlanarSpeed = getLayerBlend(innerController, "Base", "SmoothedPlanarSpeed", 0)
			local moving = getLayerBlend(innerController, "Base", "Moving", false) == true

			local locomotionCycleRate = 0
			if moving then
				locomotionCycleRate = math.clamp(smoothedPlanarSpeed / BASE_WALK_SPEED, LOCOMOTION_MIN_CYCLE_RATE, LOCOMOTION_MAX_CYCLE_RATE)
			end
			locomotionPhase = (locomotionPhase + dt * locomotionCycleRate) % 1
			syncTrackPhase(slowWalkTrack, locomotionPhase)
			syncTrackPhase(walkTrack, locomotionPhase)
			syncTrackPhase(runTrack, locomotionPhase)

			if slowWalkTrack then
				slowWalkTrack.Speed = 0
			end
			if walkTrack then
				walkTrack.Speed = 0
			end
			if runTrack then
				runTrack.Speed = 0
			end
			if climbTrack then
				climbTrack.Speed = math.clamp(smoothedPlanarSpeed / BASE_WALK_SPEED, CLIMB_MIN_CYCLE_RATE, CLIMB_MAX_CYCLE_RATE)
			end

			local landingWeight = 0
			if landTrack and landTrack.IsPlaying then
				local speedAlpha = getLandMovingSpeedAlpha(smoothedPlanarSpeed)
				landingWeight = math.clamp(1 - math.pow(speedAlpha, LAND_WEIGHT_SPEED_EASE_POWER), 0, 1)
			end
			landingWeightSmoothed += (landingWeight - landingWeightSmoothed) * math.clamp(dt * LAND_LAYER_WEIGHT_SMOOTH_SPEED, 0, 1)
			innerController:SetLayerWeight("Landing", landingWeightSmoothed)
			innerController:SetLayerWeight("UpperBody", 0)
		end,
		OnPostBlend = function(innerController, finalPose, _dt)
			local currentBaseState = getBaseState(innerController)
			local turnLean = getLayerBlend(innerController, "Base", "TurnLean", 0)
			if currentBaseState ~= "Jump" and currentBaseState ~= "Fall" and math.abs(turnLean) > 1e-4 then
				local upperLean = CFrame.Angles(0, 0, -turnLean)
				local lowerLean = CFrame.Angles(0, 0, -turnLean * 0.35)
				if finalPose.UpperTorso then
					finalPose.UpperTorso = finalPose.UpperTorso * upperLean
				end
				if finalPose.Torso then
					finalPose.Torso = finalPose.Torso * upperLean
				end
				if finalPose.LowerTorso then
					finalPose.LowerTorso = finalPose.LowerTorso * lowerLean
				end
			end
			return finalPose
		end,
		Layers = {
			Base = { Weight = 1, Order = 0 },
			Landing = { Weight = 0, Order = 1 },
			UpperBody = { Weight = 0, Order = 2, Mask = upperBodyMask },
		},
	})

	controller:SetLayerDriver("Base", "State", "Ground")
	controller:SetLayerDriver("Landing", "State", "Idle")
	controller:SetLayerDriver("UpperBody", "State", "Idle")
	setBaseBlend(controller, "ShiftHeld", false)
	setBaseBlend(controller, "Momentum", 0)
	setBaseBlend(controller, "WasAirborne", false)
	setBaseBlend(controller, "LastLandTriggerTime", -math.huge)
	setBaseBlend(controller, "SmoothedPlanarSpeed", 0)
	setBaseBlend(controller, "LastYaw", getYaw(character:GetPivot()))
	setBaseBlend(controller, "TurnLean", 0)

	bindingSetManager:AttachController(controller)

	local function updateTrackRef(trackName, track)
		if trackName == "Walk" then
			walkTrack = track
		elseif trackName == "Run" then
			runTrack = track
		elseif trackName == "SlowWalk" then
			slowWalkTrack = track
		elseif trackName == "Land" then
			landTrack = track
		elseif trackName == "Climb" then
			climbTrack = track
		end
	end

	for trackName, trackConfig in pairs(trackConfigs) do
		local initialConfig = table.clone(trackConfig)
		initialConfig.BindingId = Example5BindingCatalog:GetInitialTrackBinding(trackName)
		local track = bindingSetManager:LoadTrack(controller, trackName, initialConfig)
		if track ~= nil then
			updateTrackRef(trackName, track)
		end
	end

	controller:CreateBlendTree("Locomotion", function(innerController, _dt)
		local speed = getLayerBlend(innerController, "Base", "Speed", 0)
		local moving = getLayerBlend(innerController, "Base", "Moving", false) == true
		local shiftHeld = getLayerBlend(innerController, "Base", "ShiftHeld", false) == true
		local momentum = getLayerBlend(innerController, "Base", "Momentum", 0)
		local airState = getLayerBlend(innerController, "Base", "State", "Ground")
		local direction = getLayerBlend(innerController, "Base", "Direction", Vector3.zero)
		local moveMag = math.min(1, direction.Magnitude)

		if airState == "Jump" then return { Idle = 0, SlowWalk = 0, Walk = 0, Run = 0, Jump = 1, Fall = 0, Climb = 0 } end
		if airState == "Fall" then return { Idle = 0, SlowWalk = 0, Walk = 0, Run = 0, Jump = 0, Fall = 1, Climb = 0 } end
		if airState == "Climb" then return { Idle = 0, SlowWalk = 0, Walk = 0, Run = 0, Jump = 0, Fall = 0, Climb = 1 } end
		if not moving then return { Idle = 1, SlowWalk = 0, Walk = 0, Run = 0, Jump = 0, Fall = 0, Climb = 0 } end
		if shiftHeld then
			local slowWeight = math.clamp(speed / SLOW_WALK_SPEED, 0, 1)
			return { Idle = 1 - slowWeight, SlowWalk = slowWeight, Walk = 0, Run = 0, Jump = 0, Fall = 0, Climb = 0 }
		end
		return { Idle = 1 - moveMag, SlowWalk = 0, Walk = moveMag * (1 - momentum), Run = moveMag * momentum, Jump = 0, Fall = 0, Climb = 0 }
	end)

	return controller
end

local function attachMovementDriver(controller, humanoid, root)
	return RunService.Heartbeat:Connect(function(dt)
		local vel = root.AssemblyLinearVelocity
		local planarSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local isMoving = planarSpeed > 0.1
		local moveDir = if isMoving then Vector3.new(vel.X, 0, vel.Z).Unit else Vector3.zero
		local smoothedPlanarSpeed = getBaseBlend(controller, "SmoothedPlanarSpeed", 0)
		local lastYaw = getBaseBlend(controller, "LastYaw", getYaw(root.CFrame))
		local momentum = getBaseBlend(controller, "Momentum", 0)
		local airState = getBaseState(controller)
		local turnLean = getBaseBlend(controller, "TurnLean", 0)

		smoothedPlanarSpeed += (planarSpeed - smoothedPlanarSpeed) * math.clamp(dt * SPEED_SMOOTH_SPEED, 0, 1)

		local currentYaw = getYaw(root.CFrame)
		local yawDelta = deltaAngle(currentYaw, lastYaw)
		local turnRate = if dt > 0 then yawDelta / dt else 0
		lastYaw = currentYaw

		if not isMoving then
			momentum = 0
		elseif airState == "Ground" then
			momentum = math.min(1, momentum + MOMENTUM_BUILD_RATE * dt)
		else
			momentum = math.max(0, momentum - MOMENTUM_DECAY_RATE * dt)
		end

		humanoid.WalkSpeed = BASE_WALK_SPEED + (MAX_RUN_SPEED - BASE_WALK_SPEED) * momentum

		local maxLean = math.rad(MAX_TURN_LEAN_DEG)
		local targetLean = 0
		if isMoving then
			local speedAlpha = math.clamp(smoothedPlanarSpeed / MAX_RUN_SPEED, 0, 1)
			local leanScale = math.clamp((MIN_LEAN_SCALE + momentum) * speedAlpha, 0, 1)
			targetLean = math.clamp(-turnRate * TURN_LEAN_SENSITIVITY * leanScale, -maxLean, maxLean)
		end
		turnLean = turnLean + (targetLean - turnLean) * math.clamp(dt * TURN_LEAN_SMOOTH_SPEED, 0, 1)

		setBaseState(controller, airState)
		setBaseBlend(controller, "Speed", planarSpeed)
		setBaseBlend(controller, "Direction", moveDir)
		setBaseBlend(controller, "Moving", isMoving)
		setBaseBlend(controller, "Momentum", momentum)
		setBaseBlend(controller, "ShiftHeld", false)
		setBaseBlend(controller, "TurnLean", turnLean)
		setBaseBlend(controller, "SmoothedPlanarSpeed", smoothedPlanarSpeed)
		setBaseBlend(controller, "LastYaw", lastYaw)
	end)
end

local function attachHumanoidStateDriver(controller, humanoid)
	return humanoid.StateChanged:Connect(function(_old, new)
		local now = os.clock()
		local wasAirborne = getBaseBlend(controller, "WasAirborne", false) == true
		local lastLandTriggerTime = getBaseBlend(controller, "LastLandTriggerTime", -math.huge)
		local airState = getBaseState(controller)

		if new == Enum.HumanoidStateType.Jumping then
			wasAirborne = setBaseBlend(controller, "WasAirborne", true)
			airState = setBaseState(controller, "Jump")
			controller:MarkLayerAnimationStart("Base", "Jump")
			controller:Play("Jump")
			controller:Stop("Land", 0.2)
			controller:Stop("Fall", 0.2)
			controller:Stop("Climb", 0.2)
		elseif new == Enum.HumanoidStateType.Freefall then
			wasAirborne = setBaseBlend(controller, "WasAirborne", true)
			airState = setBaseState(controller, "Fall")
			controller:MarkLayerAnimationStart("Base", "Fall")
			controller:Play("Fall")
			controller:Stop("Jump", 0.2)
			controller:Stop("Land", 0.2)
			controller:Stop("Climb", 0.2)
		elseif new == Enum.HumanoidStateType.Climbing then
			airState = setBaseState(controller, "Climb")
			wasAirborne = setBaseBlend(controller, "WasAirborne", false)
			controller:MarkLayerAnimationStart("Base", "Climb")
			controller:Play("Climb")
			controller:Stop("Fall", 0.2)
			controller:Stop("Jump", 0.2)
			controller:Stop("Land", 0.2)
		elseif new == Enum.HumanoidStateType.Landed then
			controller:Stop("Fall", 0.2)
			controller:Stop("Jump", 0.2)
			controller:Stop("Climb", 0.2)

			local canTriggerLand = wasAirborne and (now - lastLandTriggerTime) >= LAND_RETRIGGER_COOLDOWN
			if canTriggerLand then
				airState = setBaseState(controller, "Ground")
				wasAirborne = setBaseBlend(controller, "WasAirborne", false)
				lastLandTriggerTime = setBaseBlend(controller, "LastLandTriggerTime", now)
				controller:MarkLayerAnimationStart("Landing", "Land")
				controller:Play("Land")
			elseif airState ~= "Jump" and airState ~= "Fall" then
				airState = setBaseState(controller, "Ground")
				wasAirborne = setBaseBlend(controller, "WasAirborne", false)
			end
		elseif new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.RunningNoPhysics then
			controller:Stop("Fall", 0.2)
			controller:Stop("Jump", 0.2)
			controller:Stop("Climb", 0.2)
			if airState ~= "Jump" and airState ~= "Fall" then
				airState = setBaseState(controller, "Ground")
				wasAirborne = setBaseBlend(controller, "WasAirborne", false)
			end
		end
	end)
end

local function startRandomWalkLoop(record)
	task.spawn(function()
		local npc = record.Model
		local humanoid = record.Humanoid
		local root = record.Root
		local origin = record.Origin
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

local function destroyNPCForPlayer(player)
	local record = npcRecords[player]
	if record == nil then
		return
	end

	if record.MovementConnection then
		record.MovementConnection:Disconnect()
	end
	if record.StateConnection then
		record.StateConnection:Disconnect()
	end
	FluxaService.StopNPCReplication(record.Id)
	if record.Controller then
		record.Controller:Destroy()
	end
	if record.Model and record.Model.Parent then
		if CollectionService:HasTag(record.Model, FLUXA_NPC_TAG) then
			CollectionService:RemoveTag(record.Model, FLUXA_NPC_TAG)
		end
		record.Model:Destroy()
	end
	npcRecords[player] = nil
end

local function cloneCharacterAsNPC(sourceCharacter: Model): Model?
	local oldArchivable = sourceCharacter.Archivable
	sourceCharacter.Archivable = true
	local ok, clone = pcall(function()
		return sourceCharacter:Clone()
	end)
	sourceCharacter.Archivable = oldArchivable
	if not ok or clone == nil then
		warn("Example5NPC: failed to clone player character for NPC")
		return nil
	end
	return clone
end


local function createNPCForPlayer(player: Player, sourceCharacter: Model)
	if npcRecords[player] ~= nil then
		return
	end

	local sourceRoot = sourceCharacter:FindFirstChild("HumanoidRootPart")
	if sourceRoot == nil or not sourceRoot:IsA("BasePart") then
		return
	end

	-- Use premade ServerNPC from Workspace
	local premade = Workspace:FindFirstChild("ServerNPC")
	if not premade then
		warn("Example5NPC: No premade ServerNPC found in Workspace!")
		return
	end
	local npcCharacter = premade:Clone()
	npcCharacter.Name = player.Name .. "_ServerNPC"
	npcCharacter.Parent = Workspace
	npcCharacter:PivotTo(sourceRoot.CFrame * CFrame.new(12, 0, 12))
	disableBuiltInCharacterAnimation(npcCharacter)

	local humanoid = npcCharacter:FindFirstChildOfClass("Humanoid")
	local root = npcCharacter:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		npcCharacter:Destroy()
		return
	end

	root:SetNetworkOwner(nil)

	-- Update LookTarget every frame
	local radius = 32
	local runConn
	runConn = RunService.Heartbeat:Connect(function()
		if not npcCharacter.Parent or not humanoid.Parent then
			if runConn then runConn:Disconnect() end
			return
		end
		updateNPCLookTarget(npcCharacter, humanoid, radius)
	end)
	humanoid.Destroying:Connect(function()
		if runConn then runConn:Disconnect() end
	end)

	local animFolder = ReplicatedStorage:FindFirstChild("Example3Animations_R15") or ReplicatedStorage:FindFirstChild("Example2Animations_R15")
	if animFolder == nil then
		warn("Example5NPC: missing Example3Animations_R15 / Example2Animations_R15")
		npcCharacter:Destroy()
		return
	end

	local bindingSetManager = createBindingSetManager(animFolder)
	local controller = createServerController(npcCharacter, bindingSetManager)
	local npcId = ("example5_npc_%d"):format(player.UserId)
	local record = {
		Id = npcId,
		Model = npcCharacter,
		Humanoid = humanoid,
		Root = root,
		Controller = controller,
		Origin = root.Position,
		MovementConnection = attachMovementDriver(controller, humanoid, root),
		StateConnection = attachHumanoidStateDriver(controller, humanoid),
	}

	npcCharacter:SetAttribute(FLUXA_NPC_ID_ATTRIBUTE, npcId)
	CollectionService:AddTag(npcCharacter, FLUXA_NPC_TAG)

	npcRecords[player] = record
	FluxaService.StartNPCReplication(npcId, controller, {
		Character = npcCharacter,
		RelevanceRadius = NPC_RELEVANCE_RADIUS,
	})
	startRandomWalkLoop(record)
end

local function onPlayer(player: Player)
	if spawnedPlayers[player] then
		return
	end

	player.CharacterAdded:Connect(function(character)
		if spawnedPlayers[player] then
			return
		end
		spawnedPlayers[player] = true
		character:WaitForChild("Humanoid")
		character:WaitForChild("HumanoidRootPart")
		createNPCForPlayer(player, character)
	end)

	player.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			destroyNPCForPlayer(player)
			spawnedPlayers[player] = nil
		end
	end)

	if player.Character and not spawnedPlayers[player] then
		spawnedPlayers[player] = true
		createNPCForPlayer(player, player.Character)
	end
end

-- for _, player in ipairs(Players:GetPlayers()) do
-- 	onPlayer(player)
-- end

-- Players.PlayerAdded:Connect(onPlayer)
-- Players.PlayerRemoving:Connect(function(player)
-- 	destroyNPCForPlayer(player)
-- 	spawnedPlayers[player] = nil
-- end)


do
	-- Use premade ServerNPC from Workspace
	local npcCharacter = workspace:FindFirstChild("ServerNPC")
	if not npcCharacter then
		warn("Example5NPC: No premade ServerNPC found in Workspace!")
		return
	end

	disableBuiltInCharacterAnimation(npcCharacter)

	local humanoid = npcCharacter:FindFirstChildOfClass("Humanoid")
	local root = npcCharacter:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		npcCharacter:Destroy()
		return
	end

	root:SetNetworkOwner(nil)

	local animFolder = ReplicatedStorage:FindFirstChild("Example3Animations_R15") or ReplicatedStorage:FindFirstChild("Example2Animations_R15")
	if animFolder == nil then
		warn("Example5NPC: missing Example3Animations_R15 / Example2Animations_R15")
		npcCharacter:Destroy()
		return
	end

	local bindingSetManager = createBindingSetManager(animFolder)
	local controller = createServerController(npcCharacter, bindingSetManager)
	local npcId = game:GetService("HttpService"):GenerateGUID(false)
	local record = {
		Id = npcId,
		Model = npcCharacter,
		Humanoid = humanoid,
		Root = root,
		Controller = controller,
		Origin = root.Position,
		MovementConnection = attachMovementDriver(controller, humanoid, root),
		StateConnection = attachHumanoidStateDriver(controller, humanoid),
	}

	npcCharacter:SetAttribute(FLUXA_NPC_ID_ATTRIBUTE, npcId)
	CollectionService:AddTag(npcCharacter, FLUXA_NPC_TAG)

	FluxaService.StartNPCReplication(npcId, controller, {
		Character = npcCharacter,
		RelevanceRadius = NPC_RELEVANCE_RADIUS,
	})
	startRandomWalkLoop(record)
end