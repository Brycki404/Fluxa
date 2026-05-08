--!nonstrict
-- Example5: Example4-style binding manager demo using Example3's state machine and animations,
-- plus FluxaService registration for players and server-owned NPCs.

local module = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer

local Fluxa = require(ReplicatedStorage.Packages.fluxa)
local FluxaController = Fluxa.FluxaController
local FluxaAssetManager = Fluxa.FluxaAssetManager
local FluxaBindingSetManager = Fluxa.FluxaBindingSetManager
local FluxaReplicationService = Fluxa.FluxaReplicationService
local FluxaService = Fluxa.FluxaService
local Example5BindingCatalog = require(script.Parent.Example5BindingCatalog)

local SLOW_WALK_SPEED = 6.2
local BASE_WALK_SPEED = 6.2
local MAX_RUN_SPEED = 24
local MOMENTUM_BUILD_RATE = 0.8
local MOMENTUM_DECAY_RATE = 0.4
local SHIFT_KEY = Enum.KeyCode.C
local SPEED_SMOOTH_SPEED = 10
local LAND_RETRIGGER_COOLDOWN = 0.12
local LAND_FADE_HALF_SPEED = 9
local LAND_WEIGHT_SPEED_EASE_POWER = 1.5
local MAX_TURN_LEAN_DEG = 14
local TURN_LEAN_SENSITIVITY = 0.2
local TURN_LEAN_SMOOTH_SPEED = 10
local MIN_LEAN_SCALE = 0.2
local LOCOMOTION_MIN_CYCLE_RATE = 0.8
local LOCOMOTION_MAX_CYCLE_RATE = 2.0
local CLIMB_MIN_CYCLE_RATE = 0.8
local CLIMB_MAX_CYCLE_RATE = 1.8
local MAX_DELTA_AIM_PITCH_DEG = 65
local MAX_AIM_PITCH_DEG = 65
local MIN_AIM_PITCH_DEG = -65
local AIM_PITCH_SMOOTH_SPEED = 14
local FLUXA_NPC_TAG = "FluxaNPC"
local FLUXA_NPC_ID_ATTRIBUTE = "FluxaNPCId"

local _controller = nil
local _remoteControllers = {}
local _npcControllers = {}
local _connections = {}
local _localCharacterConnections = {}
local _localControllerReplicationEnabled = true
local _sharedAssetManager = nil
local _sharedBindingSetManager = nil

module.OwnsCharacterLifecycle = true

function module:SetLocalReplicationEnabled(enabled: boolean)
	_localControllerReplicationEnabled = enabled == true
	FluxaReplicationService.SetLocalReplicationEnabled(_localControllerReplicationEnabled)
	-- Debug print for replication enabled/disabled
	print("[Fluxa][DEBUG] Local replication enabled:", _localControllerReplicationEnabled)
end

-- Utility: Create or get LookTarget attachment under Humanoid
local function getOrCreateLookTarget(root)
	local lookTarget = root:FindFirstChild("LookTarget")
	if not lookTarget then
		lookTarget = Instance.new("Attachment")
		lookTarget.Name = "LookTarget"
		lookTarget.Parent = root
	end
	return lookTarget
end

-- Utility: Create IKControl for LookAt
local function createLookAtIKControl(character, humanoid, isPlayer)
	local head = character:FindFirstChild("Head")
	local upperTorso = character:FindFirstChild("UpperTorso")
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not (head and upperTorso and root) then return end

	-- Remove existing LookAt IKControl if present
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("IKControl") and child.Name == "LookAtIK" then
			child:Destroy()
		end
	end

	local ik = Instance.new("IKControl")
	ik.Name = "LookAtIK"
	ik.Type = Enum.IKControlType.LookAt
	ik.EndEffector = head
	ik.ChainRoot = upperTorso
	ik.Parent = humanoid

	local lookTarget = getOrCreateLookTarget(root)
	ik.Target = lookTarget
	ik.Enabled = false
end

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

local function getLandMovingSpeedAlpha(planarSpeed)
	local speed = math.max(0, planarSpeed)
	local half = math.max(1e-3, LAND_FADE_HALF_SPEED)
	return math.clamp(speed / (speed + half), 0, 1)
end

local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(_connections, c)
	return c
end

local function connectLocal(signal, fn)
	local c = signal:Connect(fn)
	table.insert(_localCharacterConnections, c)
	return c
end

local function disconnectLocalCharacterConnections()
	for _, c in ipairs(_localCharacterConnections) do
		c:Disconnect()
	end
	table.clear(_localCharacterConnections)
end

local function disconnectAll()
	for _, c in ipairs(_connections) do
		c:Disconnect()
	end
	table.clear(_connections)
end

local function createBindingSetManager(folder: Instance?)
	if _sharedBindingSetManager ~= nil then
		return _sharedBindingSetManager
	end

	_sharedAssetManager = _sharedAssetManager or FluxaAssetManager.new()
	_sharedBindingSetManager = FluxaBindingSetManager.new({
		Catalog = Example5BindingCatalog,
		AssetManager = _sharedAssetManager,
		SourceContainer = folder,
	})

	return _sharedBindingSetManager
end

local function createInputDriver(controller, connectFn)
	local register = connectFn or connect
	register(UserInputService.InputBegan, function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == SHIFT_KEY then
			setBaseBlend(controller, "ShiftHeld", true)
		end
	end)
	register(UserInputService.InputEnded, function(input: InputObject, _: boolean)
		if input.KeyCode == SHIFT_KEY then
			setBaseBlend(controller, "ShiftHeld", false)
		end
	end)
end

local function createMovementDriver(controller, humanoid, root, connectFn)
	local register = connectFn or connect
	return register(RunService.RenderStepped, function(dt)
		local vel = root.AssemblyLinearVelocity
		local planarSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local moveDir = humanoid.MoveDirection
		local isMoving = moveDir.Magnitude > 0.1
		local smoothedPlanarSpeed = getBaseBlend(controller, "SmoothedPlanarSpeed", 0)
		local lastYaw = getBaseBlend(controller, "LastYaw", getYaw(root.CFrame))
		local momentum = getBaseBlend(controller, "Momentum", 0)
		local shiftHeld = getBaseBlend(controller, "ShiftHeld", false) == true
		local airState = getBaseState(controller)
		local turnLean = getBaseBlend(controller, "TurnLean", 0)

		smoothedPlanarSpeed += (planarSpeed - smoothedPlanarSpeed) * math.clamp(dt * SPEED_SMOOTH_SPEED, 0, 1)

		local currentYaw = getYaw(root.CFrame)
		local yawDelta = deltaAngle(currentYaw, lastYaw)
		local turnRate = if dt > 0 then yawDelta / dt else 0
		lastYaw = currentYaw

		if isMoving then
			local targetCFrame = CFrame.lookAt(root.Position, root.Position + moveDir)
			root.CFrame = root.CFrame:Lerp(targetCFrame, math.clamp(dt * 10, 0, 1))
		end

		if not isMoving then
			momentum = 0
		elseif not shiftHeld and airState == "Ground" then
			momentum = math.min(1, momentum + MOMENTUM_BUILD_RATE * dt)
		else
			momentum = math.max(0, momentum - MOMENTUM_DECAY_RATE * dt)
		end

		if shiftHeld then
			humanoid.WalkSpeed = SLOW_WALK_SPEED
		else
			humanoid.WalkSpeed = BASE_WALK_SPEED + (MAX_RUN_SPEED - BASE_WALK_SPEED) * momentum
		end

		local maxLean = math.rad(MAX_TURN_LEAN_DEG)
		local targetLean = 0
		if isMoving then
			local speedAlpha = math.clamp(smoothedPlanarSpeed / MAX_RUN_SPEED, 0, 1)
			local momentumAlpha = momentum
			local leanScale = math.clamp((MIN_LEAN_SCALE + momentumAlpha) * speedAlpha, 0, 1)
			targetLean = math.clamp(-turnRate * TURN_LEAN_SENSITIVITY * leanScale, -maxLean, maxLean)
		end
		turnLean = turnLean + (targetLean - turnLean) * math.clamp(dt * TURN_LEAN_SMOOTH_SPEED, 0, 1)

		setBaseState(controller, airState)
		setBaseBlend(controller, "Speed", planarSpeed)
		setBaseBlend(controller, "Direction", moveDir)
		setBaseBlend(controller, "Moving", isMoving)
		setBaseBlend(controller, "Momentum", momentum)
		setBaseBlend(controller, "ShiftHeld", shiftHeld)
		setBaseBlend(controller, "TurnLean", turnLean)
		setBaseBlend(controller, "SmoothedPlanarSpeed", smoothedPlanarSpeed)
		setBaseBlend(controller, "LastYaw", lastYaw)
	end)
end

-- Movement driver for MoveTo-based NPCs (uses velocity, not MoveDirection)
local function createNPCMovementDriver(controller, root, connectFn, isRemotePlayer)
    local register = connectFn or connect
    return register(RunService.RenderStepped, function(dt)
        local vel = root.AssemblyLinearVelocity
        local planarVel = Vector3.new(vel.X, 0, vel.Z)
        local planarSpeed = planarVel.Magnitude
        local isMoving = planarSpeed > 0.1
        local smoothedPlanarSpeed = getBaseBlend(controller, "SmoothedPlanarSpeed", 0)
        local lastYaw = getBaseBlend(controller, "LastYaw", getYaw(root.CFrame))
        local momentum = getBaseBlend(controller, "Momentum", 0)
        local airState = getBaseState(controller)
        local turnLean = getBaseBlend(controller, "TurnLean", 0)

        smoothedPlanarSpeed += (planarSpeed - smoothedPlanarSpeed) * math.clamp(dt * SPEED_SMOOTH_SPEED, 0, 1)

        local moveDir = if planarSpeed > 0 then planarVel.Unit else Vector3.zero
        local currentYaw = getYaw(root.CFrame)
        local yawDelta = deltaAngle(currentYaw, lastYaw)
        local turnRate = if dt > 0 then yawDelta / dt else 0
        lastYaw = currentYaw

        if isMoving and not isRemotePlayer then
            local targetCFrame = CFrame.lookAt(root.Position, root.Position + moveDir)
            root.CFrame = root.CFrame:Lerp(targetCFrame, math.clamp(dt * 10, 0, 1))
        end

        if not isMoving then
            momentum = 0
        elseif airState == "Ground" then
            momentum = math.min(1, momentum + MOMENTUM_BUILD_RATE * dt)
        else
            momentum = math.max(0, momentum - MOMENTUM_DECAY_RATE * dt)
        end

        local maxLean = math.rad(MAX_TURN_LEAN_DEG)
        local targetLean = 0
        if isMoving then
            local speedAlpha = math.clamp(smoothedPlanarSpeed / MAX_RUN_SPEED, 0, 1)
            local momentumAlpha = momentum
            local leanScale = math.clamp((MIN_LEAN_SCALE + momentumAlpha) * speedAlpha, 0, 1)
            targetLean = math.clamp(-turnRate * TURN_LEAN_SENSITIVITY * leanScale, -maxLean, maxLean)
        end
        turnLean = turnLean + (targetLean - turnLean) * math.clamp(dt * TURN_LEAN_SMOOTH_SPEED, 0, 1)

        setBaseBlend(controller, "Speed", planarSpeed)
        setBaseBlend(controller, "Direction", moveDir)
        setBaseBlend(controller, "Moving", isMoving)
        setBaseBlend(controller, "Momentum", momentum)
        setBaseBlend(controller, "TurnLean", turnLean)
        setBaseBlend(controller, "SmoothedPlanarSpeed", smoothedPlanarSpeed)
        setBaseBlend(controller, "LastYaw", lastYaw)
    end)
end

local function createHumanoidStateDriver(controller, humanoid, flushPacket, connectFn)
	local register = connectFn or connect
	register(humanoid.StateChanged, function(_old, new)
		local now = os.clock()
		local wasAirborne = getBaseBlend(controller, "WasAirborne", false) == true
		local lastLandTriggerTime = getBaseBlend(controller, "LastLandTriggerTime", -math.huge)
		local airState = getBaseState(controller)

		if new == Enum.HumanoidStateType.Jumping then
			wasAirborne = setBaseBlend(controller, "WasAirborne", true)
			airState = setBaseState(controller, "Jump")
			controller:MarkLayerAnimationStart("Base", "Jump")
			controller:Play("Jump")
			if flushPacket then
				flushPacket()
			end
			controller:Stop("Land")
			controller:Stop("Fall")
			controller:Stop("Climb")
		elseif new == Enum.HumanoidStateType.Freefall then
			wasAirborne = setBaseBlend(controller, "WasAirborne", true)
			airState = setBaseState(controller, "Fall")
			controller:MarkLayerAnimationStart("Base", "Fall")
			controller:Play("Fall")
			controller:Stop("Jump")
			controller:Stop("Land")
			controller:Stop("Climb")
		elseif new == Enum.HumanoidStateType.Climbing then
			airState = setBaseState(controller, "Climb")
			wasAirborne = setBaseBlend(controller, "WasAirborne", false)
			controller:MarkLayerAnimationStart("Base", "Climb")
			controller:Play("Climb")
			controller:Stop("Fall")
			controller:Stop("Jump")
			controller:Stop("Land")
		elseif new == Enum.HumanoidStateType.Landed then
			controller:Stop("Fall")
			controller:Stop("Jump")
			controller:Stop("Climb")

			local canTriggerLand = wasAirborne and (now - lastLandTriggerTime) >= LAND_RETRIGGER_COOLDOWN
			if canTriggerLand then
				airState = setBaseState(controller, "Ground")
				wasAirborne = setBaseBlend(controller, "WasAirborne", false)
				lastLandTriggerTime = setBaseBlend(controller, "LastLandTriggerTime", now)
				controller:MarkLayerAnimationStart("Landing", "Land")
				controller:Play("Land")
				if flushPacket then
					flushPacket()
				end
			elseif airState ~= "Jump" and airState ~= "Fall" then
				airState = setBaseState(controller, "Ground")
				wasAirborne = setBaseBlend(controller, "WasAirborne", false)
			end
		elseif new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.RunningNoPhysics then
			controller:Stop("Fall")
			controller:Stop("Jump")
			controller:Stop("Climb")
			if airState ~= "Jump" and airState ~= "Fall" then
				airState = setBaseState(controller, "Ground")
				wasAirborne = setBaseBlend(controller, "WasAirborne", false)
			end
		end
	end)
end

-- Custom state driver for client-only NPCs (does not rely on Humanoid.StateChanged)
local function createNPCStateDriver(controller, humanoid, root, connectFn)
	local register = connectFn or connect
	local lastAirState = "Ground"
	local wasAirborne = false
	local lastLandTriggerTime = -math.huge
	register(RunService.RenderStepped, function(dt)
		local vel = root.AssemblyLinearVelocity
		local planarSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local grounded = humanoid:GetState() ~= Enum.HumanoidStateType.Freefall and humanoid.FloorMaterial ~= Enum.Material.Air
		local climbing = humanoid:GetState() == Enum.HumanoidStateType.Climbing
		local jumping = humanoid:GetState() == Enum.HumanoidStateType.Jumping
		local now = os.clock()
		local airState = getBaseState(controller)

		if climbing then
			airState = setBaseState(controller, "Climb")
			wasAirborne = false
			controller:MarkLayerAnimationStart("Base", "Climb")
			controller:Play("Climb")
			controller:Stop("Fall")
			controller:Stop("Jump")
			controller:Stop("Land")
		elseif not grounded then
			if not wasAirborne then
				wasAirborne = true
				airState = setBaseState(controller, "Fall")
				controller:MarkLayerAnimationStart("Base", "Fall")
				controller:Play("Fall")
				controller:Stop("Jump")
				controller:Stop("Land")
				controller:Stop("Climb")
			end
		elseif jumping then
			wasAirborne = true
			airState = setBaseState(controller, "Jump")
			controller:MarkLayerAnimationStart("Base", "Jump")
			controller:Play("Jump")
			controller:Stop("Land")
			controller:Stop("Fall")
			controller:Stop("Climb")
		else
			if wasAirborne then
				local canTriggerLand = (now - lastLandTriggerTime) >= LAND_RETRIGGER_COOLDOWN
				if canTriggerLand then
					airState = setBaseState(controller, "Ground")
					wasAirborne = false
					lastLandTriggerTime = now
					controller:MarkLayerAnimationStart("Landing", "Land")
					controller:Play("Land")
				else
					airState = setBaseState(controller, "Ground")
					wasAirborne = false
				end
			elseif airState ~= "Jump" and airState ~= "Fall" then
				airState = setBaseState(controller, "Ground")
				wasAirborne = false
			end
		end
	end)
end

local function createCombatDriver(controller, connectFn)
	local register = connectFn or connect
	return register(UserInputService.InputBegan, function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			controller:SetLayerDriver("UpperBody", "State", "Attack")
			controller:MarkLayerAnimationStart("UpperBody", "Attack")
			controller:Play("Attack")
			FluxaReplicationService.SendLocalPacket()
		end
	end)
end

local function createCameraDriver(controller, connectFn)
	local register = connectFn or connect
	-- Throttle packet sending to 10 Hz and only on significant change
	local lastSend = 0
	local lastPitch = nil
	local lastYawRel = nil
	local SEND_INTERVAL = 0.1 -- 10 Hz
	local PITCH_EPSILON = 0.01
	local YAW_EPSILON = 0.01
	return register(RunService.RenderStepped, function()
		local now = os.clock()
		local look = Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame.LookVector or Vector3.new(0, 0, -1)
		controller:SetLayerDriver("UpperBody", "AimPitchInput", look.Y)
		local camera = Workspace.CurrentCamera
		local character = controller.Character
		if camera and character then
			local camCFrame = camera.CFrame
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			local camYawRel = 0
			local camPitch = 0
			if rootPart then
				local charLook = rootPart.CFrame.LookVector
				local camLookLocal = rootPart.CFrame:VectorToObjectSpace(camCFrame.LookVector)
				if charLook:Dot(camCFrame.LookVector) < 0 then
					camLookLocal = Vector3.new(camLookLocal.X, camLookLocal.Y, -camLookLocal.Z)
				end
				camYawRel = math.atan2(-camLookLocal.X, -camLookLocal.Z)
				camPitch = math.asin(camLookLocal.Y)
				if camYawRel > math.pi then camYawRel = camYawRel - 2 * math.pi end
				if camYawRel < -math.pi then camYawRel = camYawRel + 2 * math.pi end
			end
			controller:SetGlobalDriver("LookCamPitch", camPitch)
			controller:SetGlobalDriver("LookCamYawRel", camYawRel)
			-- Only send if changed enough or enough time has passed
			local pitchChanged = not lastPitch or math.abs(camPitch - lastPitch) > PITCH_EPSILON
			local yawChanged = not lastYawRel or math.abs(camYawRel - lastYawRel) > YAW_EPSILON
			if (pitchChanged or yawChanged) and (now - lastSend > SEND_INTERVAL) then
				-- FluxaReplicationService.SendLocalPacket()
				lastSend = now
				lastPitch = camPitch
				lastYawRel = camYawRel
			end
		end
	end)
end

local function disableBuiltInCharacterAnimation(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Do NOT destroy Animator
		humanoid.AutoRotate = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	end

	local animateScript = character:FindFirstChild("Animate")
	if animateScript and animateScript:IsA("LocalScript") then
		animateScript.Disabled = true
	end
end

local function createFluxaController(character: Model, bindingSetManager, isLocalController: boolean?, isNPCController: boolean?)
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
	local smoothedAimPitch = 0
	local lastObservedBaseState = "Ground"
	local trackConfigs = {
		Idle = { Layer = "Base", AutoReplicate = true, InitialWeight = 1, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.2, FadeOutTime = 0.2 } },
		Walk = { Layer = "Base", AutoReplicate = true, PreservePhaseOnSwap = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.2, FadeOutTime = 0.2 } },
		Run = { Layer = "Base", AutoReplicate = true, PreservePhaseOnSwap = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.18, FadeOutTime = 0.2 } },
		SlowWalk = { Layer = "Base", AutoReplicate = true, PreservePhaseOnSwap = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.2, FadeOutTime = 0.24 } },
		Jump = { Layer = "Base", AutoReplicate = true, ReplicationSeekMode = "Never", TrackOptions = { Looped = false, Speed = 1, FadeInTime = 0.08, FadeOutTime = 0.16 } },
		Fall = { Layer = "Base", AutoReplicate = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.14, FadeOutTime = 0.18 } },
		Land = { Layer = "Landing", AutoReplicate = true, ReplicationSeekMode = "Never", TrackOptions = { Looped = false, Speed = 1, FadeInTime = 0.08, FadeOutTime = 0.8 } },
		Climb = { Layer = "Base", AutoReplicate = true, PreservePhaseOnSwap = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.18, FadeOutTime = 0.22 } },
		Attack = { Layer = "UpperBody", AutoReplicate = true, ReplicationSeekMode = "Never",  TrackOptions = { Looped = false, Speed = 1, FadeInTime = 0.08, FadeOutTime = 0.4 } },
		-- 0.08 and 0.14
	}

	-- NPC controllers are serverowned, so we don't need to replicate them here
	local controller = FluxaController.new({
		Character = character,
		AutoApplyPose = true,
		ReplicationSeekMode = isNPCController and "Never" or "LoopingOnly",
		ReplicateTrackBindings = isNPCController ~= true,
		ReplicationMode = isNPCController and "LocalOnly" or "ClientOwned",
		OnPreStep = function(innerController, dt)
			local currentBaseState = getBaseState(innerController)
			local smoothedPlanarSpeed = getLayerBlend(innerController, "Base", "SmoothedPlanarSpeed", 0)
			local moving = getLayerBlend(innerController, "Base", "Moving", false) == true
			if not isLocalController and currentBaseState ~= lastObservedBaseState then
				if currentBaseState == "Jump" then
					innerController:Play("Jump")
				end
				lastObservedBaseState = currentBaseState
			end

			local locomotionCycleRate = 0
			if moving then
				locomotionCycleRate = math.clamp(smoothedPlanarSpeed / BASE_WALK_SPEED, LOCOMOTION_MIN_CYCLE_RATE, LOCOMOTION_MAX_CYCLE_RATE)
			end

			if slowWalkTrack then
				slowWalkTrack.Speed = locomotionCycleRate
			end
			if walkTrack then
				walkTrack.Speed = locomotionCycleRate
			end
			if runTrack then
				runTrack.Speed = locomotionCycleRate
			end
			if climbTrack then
				climbTrack.Speed = math.clamp(smoothedPlanarSpeed / BASE_WALK_SPEED, CLIMB_MIN_CYCLE_RATE, CLIMB_MAX_CYCLE_RATE)
			end

			local landingWeight = 0
			if landTrack and landTrack.IsPlaying then
				local speedAlpha = getLandMovingSpeedAlpha(smoothedPlanarSpeed)
				landingWeight = math.clamp(1 - math.pow(speedAlpha, LAND_WEIGHT_SPEED_EASE_POWER), 0, 1)
			end
			innerController:SetTrackWeight("Land", landingWeight)
			innerController:SetLayerWeight("Landing", 1)

			if not isNPCController then
				if isLocalController then
					local rawAimPitch = math.clamp(getLayerBlend(innerController, "UpperBody", "AimPitchInput", 0), -1, 1)
					smoothedAimPitch += (rawAimPitch - smoothedAimPitch) * math.clamp(dt * AIM_PITCH_SMOOTH_SPEED, 0, 1)

					local smoothedTrackWeights = (innerController :: any)._smoothedTrackWeights
					local smoothedAttackWeight = 0
					if type(smoothedTrackWeights) == "table" then
						smoothedAttackWeight = math.clamp(smoothedTrackWeights.Attack or 0, 0, 1)
					end

					if smoothedAttackWeight > 1e-4 then
						innerController:SetLayerDriver("UpperBody", "State", "Attack")
					else
						innerController:SetLayerDriver("UpperBody", "State", "Idle")
					end
					innerController:SetLayerDriver("UpperBody", "AimPitch", smoothedAimPitch)
				else
					local replicatedAimPitch = math.clamp(getLayerBlend(innerController, "UpperBody", "AimPitch", 0), -1, 1)
					smoothedAimPitch += (replicatedAimPitch - smoothedAimPitch) * math.clamp(dt * AIM_PITCH_SMOOTH_SPEED, 0, 1)
				end

				innerController:SetLayerWeight("UpperBody", 1)
			end
		end,
		OnPostBlend = function(innerController, finalPose, dt)
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

			if not isNPCController then
				local smoothedTrackWeights = (innerController :: any)._smoothedTrackWeights
				local aimPitchWeight = 0
				if type(smoothedTrackWeights) == "table" then
					aimPitchWeight = math.clamp(smoothedTrackWeights.Attack or 0, 0, 1)
				end

				-- Complementary weighting: AimPitch vs LookAt
				local lookAtWeight = 1 - aimPitchWeight

				-- AimPitch effect (as before, but weighted)
				if aimPitchWeight > 0 then
					if finalPose.RightLowerArm then
						finalPose.RightLowerArm = finalPose.RightLowerArm:Lerp(CFrame.identity, aimPitchWeight)
					end
					if finalPose.RightHand then
						finalPose.RightHand = finalPose.RightHand:Lerp(CFrame.identity, aimPitchWeight)
					end

					local aimPitch = getLayerBlend(innerController, "UpperBody", "AimPitch", smoothedAimPitch)
					local desiredPitch = math.clamp(math.rad(MAX_DELTA_AIM_PITCH_DEG) * aimPitch, math.rad(MIN_AIM_PITCH_DEG), math.rad(MAX_AIM_PITCH_DEG))
					local pitchRadians = desiredPitch * aimPitchWeight
					local pitchOffset = CFrame.Angles(pitchRadians, 0, 0)

					if finalPose.UpperTorso then
						if finalPose.LowerTorso then
							local upperBase = finalPose.UpperTorso
							local compensatedUpper = finalPose.LowerTorso.Rotation:Inverse() * upperBase
							local compensationAlpha = math.clamp(aimPitchWeight * aimPitchWeight, 0, 1)
							local blendedUpper = upperBase:Lerp(compensatedUpper, compensationAlpha)
							finalPose.UpperTorso = blendedUpper * pitchOffset
						else
							finalPose.UpperTorso = finalPose.UpperTorso * pitchOffset
						end
					elseif finalPose.Torso then
						finalPose.Torso = finalPose.Torso * pitchOffset
					end
				end

				-- LookAt effect (complementary to AimPitch, replicated via GlobalDriver)
				local isLocalPlayerCharacter = false
				if Players and Players.LocalPlayer and innerController and innerController.Character then
					isLocalPlayerCharacter = (Players.LocalPlayer.Character == innerController.Character)
				end

				-- Get the rest pose (original, unmodified pose) for Head and UpperTorso
				local restPose = innerController.RestPose or {}

				if lookAtWeight > 0 then
					-- Smoothing state (persist across calls)
					innerController._smoothedLookCamPitch = innerController._smoothedLookCamPitch or 0
					innerController._smoothedLookCamYawRel = innerController._smoothedLookCamYawRel or 0
					local SMOOTH_SPEED = 14 -- higher = snappier, lower = smoother
					local function smoothAngle(current, target, dt)
						-- Handles wraparound for angles
						local delta = target - current
						if delta > math.pi then delta = delta - 2 * math.pi end
						if delta < -math.pi then delta = delta + 2 * math.pi end
						return current + (delta * math.clamp(dt * SMOOTH_SPEED, 0, 1))
					end
					-- Exponential curve for yaw influence
					local function yawInfluenceCurve(yaw)
						-- Influence is 1 in the central region, drops to 0 in the last 40 degrees near perpendicular
						local maxInfluenceAngle = math.rad(90)
						local cutoff = math.rad(50) -- start reducing at 50deg
						local absYaw = math.abs(yaw)
						if absYaw >= maxInfluenceAngle then
							return 0
						elseif absYaw <= cutoff then
							return 1
						else
							-- Smoothly drop from 1 to 0 between 50 and 90 degrees
							local t = (absYaw - cutoff) / (maxInfluenceAngle - cutoff)
							-- Use a smoothstep for a gentle curve
							return 1 - (3*t^2 - 2*t^3)
						end
					end
					if isLocalPlayerCharacter then
						local camera = Workspace.CurrentCamera
						local character = innerController.Character
						if camera and character then
							local camCFrame = camera.CFrame
							local rootPart = character:FindFirstChild("HumanoidRootPart")
							local camYawRel = 0
							local camPitch = 0
							if rootPart then
								local charLook = rootPart.CFrame.LookVector
								-- Get camera look in rootPart's object space
								local camLookLocal = rootPart.CFrame:VectorToObjectSpace(camCFrame.LookVector)
								-- If facing opposite, flip only the Z axis
								if charLook:Dot(camCFrame.LookVector) < 0 then
									camLookLocal = Vector3.new(camLookLocal.X, camLookLocal.Y, -camLookLocal.Z)
								end
								-- Compute yaw and pitch from local camera look
								camYawRel = math.atan2(-camLookLocal.X, -camLookLocal.Z)
								camPitch = math.asin(camLookLocal.Y)
								-- Normalize to [-pi, pi]
								if camYawRel > math.pi then camYawRel = camYawRel - 2 * math.pi end
								if camYawRel < -math.pi then camYawRel = camYawRel + 2 * math.pi end
							end
							-- Smooth the pitch and yaw
							innerController._smoothedLookCamPitch = innerController._smoothedLookCamPitch or camPitch
							innerController._smoothedLookCamYawRel = innerController._smoothedLookCamYawRel or camYawRel
							innerController._smoothedLookCamPitch = innerController._smoothedLookCamPitch + (camPitch - innerController._smoothedLookCamPitch) * math.clamp(dt * SMOOTH_SPEED, 0, 1)
							local yawInfluence = 1 --yawInfluenceCurve(camYawRel)
							-- if yawInfluence == 0 then
							-- 	innerController._smoothedLookCamYawRel = 0
							-- else
								innerController._smoothedLookCamYawRel = smoothAngle(innerController._smoothedLookCamYawRel, camYawRel, dt)
							-- end
							-- Set global drivers for replication
							innerController:SetGlobalDriver("LookCamPitch", innerController._smoothedLookCamPitch)
							innerController:SetGlobalDriver("LookCamYawRel", innerController._smoothedLookCamYawRel)
							-- Blend the angles for UpperTorso and Head
							if finalPose.UpperTorso and (restPose.UpperTorso or finalPose.UpperTorso) then
								local base = restPose.UpperTorso or finalPose.UpperTorso
								finalPose.UpperTorso = base * CFrame.Angles(innerController._smoothedLookCamPitch * 0.15 * lookAtWeight * yawInfluence, innerController._smoothedLookCamYawRel * 0.15 * lookAtWeight * yawInfluence, 0)
							end
							if finalPose.Head and (restPose.Head or finalPose.Head) then
								local base = restPose.Head or finalPose.Head
								finalPose.Head = base * CFrame.Angles(innerController._smoothedLookCamPitch * 0.85 * lookAtWeight * yawInfluence, innerController._smoothedLookCamYawRel * 0.85 * lookAtWeight * yawInfluence, 0)
							end
						end
					else
						-- For remote players, get camPitch and camYawRel from global drivers and smooth
						local camPitch = innerController:GetGlobalDriver("LookCamPitch") or 0
						local camYawRel = innerController:GetGlobalDriver("LookCamYawRel") or 0
						innerController._smoothedLookCamPitch = innerController._smoothedLookCamPitch or camPitch
						innerController._smoothedLookCamYawRel = innerController._smoothedLookCamYawRel or camYawRel
						innerController._smoothedLookCamPitch = innerController._smoothedLookCamPitch + (camPitch - innerController._smoothedLookCamPitch) * math.clamp(dt * SMOOTH_SPEED, 0, 1)
						innerController._smoothedLookCamYawRel = smoothAngle(innerController._smoothedLookCamYawRel, camYawRel, dt)
						local yawInfluence = yawInfluenceCurve(innerController._smoothedLookCamYawRel)
						-- Blend the angles for UpperTorso and Head
						if finalPose.UpperTorso and (restPose.UpperTorso or finalPose.UpperTorso) then
							local base = restPose.UpperTorso or finalPose.UpperTorso
							finalPose.UpperTorso = base * CFrame.Angles(innerController._smoothedLookCamPitch * 0.15 * lookAtWeight * yawInfluence, innerController._smoothedLookCamYawRel * 0.15 * lookAtWeight * yawInfluence, 0)
						end
						if finalPose.Head and (restPose.Head or finalPose.Head) then
							local base = restPose.Head or finalPose.Head
							finalPose.Head = base * CFrame.Angles(innerController._smoothedLookCamPitch * 0.85 * lookAtWeight * yawInfluence, innerController._smoothedLookCamYawRel * 0.85 * lookAtWeight * yawInfluence, 0)
						end
					end
				end
			end

			return finalPose
		end,
		OnPostStep = function(_ctrl, _dt, _finalPose)
			-- Runtime IK is layered into finalPose in OnPostBlend.
		end,
		Layers = {
			Base = { Weight = 1, Order = 0 },
			Landing = { Weight = 0, Order = 1 },
			UpperBody = { Weight = 1, Order = 2, Mask = upperBodyMask },
		},
	})

	-- Always initialize all relevant drivers to non-nil defaults
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
	setBaseBlend(controller, "Speed", 0)
	setBaseBlend(controller, "Direction", Vector3.zero)
	setBaseBlend(controller, "Moving", false)
	setBaseBlend(controller, "AimPitch", 0)
	setBaseBlend(controller, "AimPitchInput", 0)
	-- Global drivers for LookCamPitch and LookCamYawRel (for remote player aiming)
	controller:SetGlobalDriver("LookCamPitch", 0)
	controller:SetGlobalDriver("LookCamYawRel", 0)
	-- Debug print for driver initialization
	print("[Fluxa][DEBUG] Initialized drivers for", character:GetFullName())
	-- NOTE: The replication system does NOT clear values unless explicitly told to. Drivers retain their last value until overwritten.

	bindingSetManager:AttachController(controller)

	local function updateTrackRef(trackName: string, track: any)
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
		-- if not isLocalController then
		-- 	if track then
		-- 		print("[Fluxa][DEBUG][Remote] Loaded track:", trackName, "Asset:", tostring(track.Asset))
		-- 	else
		-- 		warn("[Fluxa][DEBUG][Remote] Failed to load track:", trackName)
		-- 	end
		-- end
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

		if airState == "Jump" then
			return { Idle = 0, SlowWalk = 0, Walk = 0, Run = 0, Jump = 1, Fall = 0, Climb = 0 }
		end
		if airState == "Fall" then
			return { Idle = 0, SlowWalk = 0, Walk = 0, Run = 0, Jump = 0, Fall = 1, Climb = 0 }
		end
		if airState == "Climb" then
			return { Idle = 0, SlowWalk = 0, Walk = 0, Run = 0, Jump = 0, Fall = 0, Climb = 1 }
		end
		if not moving then
			return { Idle = 1, SlowWalk = 0, Walk = 0, Run = 0, Jump = 0, Fall = 0, Climb = 0 }
		end
		if shiftHeld then
			local slowWeight = math.clamp(speed / SLOW_WALK_SPEED, 0, 1)
			return { Idle = 1 - slowWeight, SlowWalk = slowWeight, Walk = 0, Run = 0, Jump = 0, Fall = 0, Climb = 0 }
		end
		local result = { Idle = 1 - moveMag, SlowWalk = 0, Walk = moveMag * (1 - momentum), Run = moveMag * momentum, Jump = 0, Fall = 0, Climb = 0 }
		return result
	end)

	-- Disable replication for velocity-based drivers on local player
	-- controller:SetLayerDriverReplication("Base", "Moving", false)
	-- controller:SetLayerDriverReplication("Base", "SmoothedPlanarSpeed", false)
	-- controller:SetLayerDriverReplication("Base", "Speed", false)
	-- controller:SetLayerDriverReplication("Base", "LastYaw", false)
	-- controller:SetLayerDriverReplication("Base", "TurnLean", false)
	-- controller:SetLayerDriverReplication("Base", "WasAirborne", false)
	-- controller:SetLayerDriverReplication("Base", "LastLandTriggerTime", false)

	return controller
end

local function destroyRemoteController(player)
	local controller = _remoteControllers[player]
	if controller then
		FluxaReplicationService.ClearRemoteController(player)
		FluxaService.UnregisterController(player)
		controller:Destroy()
		_remoteControllers[player] = nil
	end
end

local function destroyNPCController(id)
	local controller = _npcControllers[id]
	if controller then
		FluxaService.UnregisterController(id)
		controller:Destroy()
		_npcControllers[id] = nil
	end
end

local function getNpcIdFromModel(npcCharacter: Model): string?
	local value = npcCharacter:GetAttribute(FLUXA_NPC_ID_ATTRIBUTE)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function destroyNPCControllerByModel(npcCharacter: Model)
	local id = getNpcIdFromModel(npcCharacter)
	if id ~= nil then
		destroyNPCController(id)
		return
	end

	for npcId, controller in pairs(_npcControllers) do
		if controller ~= nil and controller.Character == npcCharacter then
			destroyNPCController(npcId)
			break
		end
	end
end

-- Only create a Fluxa controller for visual NPCs (not server dummies)
local function bootstrapTaggedNPC(npcCharacter: Model, bindingSetManager)
	local id = getNpcIdFromModel(npcCharacter)
	if id == nil then
		return
	end

	-- Find or create the visual NPC in workspace.CurrentCamera
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local visualNPC = nil
	for _, child in ipairs(camera:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute(FLUXA_NPC_ID_ATTRIBUTE) == id then
			visualNPC = child
			break
		end
	end
	if not visualNPC then
		-- Clone the server NPC as the visual NPC
		visualNPC = ReplicatedStorage:FindFirstChild("ServerNPC"):Clone()
		visualNPC.Parent = camera
		visualNPC:SetAttribute(FLUXA_NPC_ID_ATTRIBUTE, id)
		visualNPC.Name = "ClientVisualNPC_" .. id
		-- Mark as client visual
		visualNPC:SetAttribute("ClientVisual", true)
	end

	visualNPC:WaitForChild("Humanoid")
	visualNPC:WaitForChild("HumanoidRootPart")
	visualNPC:WaitForChild("Head")
	disableBuiltInCharacterAnimation(visualNPC)

	local npcController = createFluxaController(visualNPC, bindingSetManager, false, true)
	_npcControllers[id] = npcController
	FluxaService.RegisterController(id, npcController)

	-- Set up following logic: sync position/velocity from server NPC to visual NPC
	local function followServerNPC()
		local serverRoot = npcCharacter:WaitForChild("HumanoidRootPart")
		local serverHumanoid = npcCharacter:WaitForChild("Humanoid")
		local clientRoot = visualNPC:FindFirstChild("HumanoidRootPart")
		local clientHumanoid = visualNPC:FindFirstChild("Humanoid")
		if not (serverRoot and clientRoot) then return end

		serverRoot.CanCollide = false
		setBaseBlend(npcController, "LastYaw", getYaw(serverRoot.CFrame))
		-- Use custom state driver and movement driver for client-only NPCs
		createNPCStateDriver(npcController, clientHumanoid, clientRoot, connect)
		createNPCMovementDriver(npcController, clientRoot, connect)

		createLookAtIKControl(visualNPC, clientHumanoid, false)
    
		RunService.RenderStepped:Connect(function()
			if not (serverRoot.Parent and clientRoot.Parent) then return end
			clientRoot.CFrame = serverRoot.CFrame
			clientRoot.AssemblyLinearVelocity = serverRoot.AssemblyLinearVelocity

			-- Update LookTarget every frame
			local radius = 32
			local head = visualNPC:FindFirstChild("Head")
			local root = clientRoot or visualNPC:FindFirstChild("HumanoidRootPart") or visualNPC.PrimaryPart
			if not head or not root then return end
			local closest, closestDist = nil, radius
			for _, other in ipairs(workspace:GetDescendants()) do
				if other:IsA("Humanoid") and other ~= clientHumanoid and other.Health > 0 then
					local otherRoot = other.Parent and other.Parent:FindFirstChild("HumanoidRootPart")
					if otherRoot and otherRoot ~= serverRoot then
						local dist = (serverRoot.Position - otherRoot.Position).Magnitude
						-- Angle check: only consider targets in front of the NPC (e.g., within 90 degrees)
						local toOther = (otherRoot.Position - serverRoot.Position).Unit
						local forward = serverRoot.CFrame.LookVector.Unit
						local dot = forward:Dot(toOther)
						local angle = math.acos(math.clamp(dot, -1, 1))
						local maxAngle = math.rad(45) -- 45 degrees in front
						if dist < closestDist and angle <= maxAngle then
							closest = otherRoot
							closestDist = dist
						end
					end
				end
			end
			local ikControl = clientHumanoid:FindFirstChildOfClass("IKControl")
			if ikControl then
				ikControl.Enabled = true
				local targetWeight = 0
				if closest then
					local att = closest:FindFirstChild("RootAttachment") or closest:FindFirstChild("RootRigAttachment")
					if att then
						ikControl.Target = att
						targetWeight = 1
					end
				end
				-- Lerp current weight toward targetWeight
				ikControl.Weight = ikControl.Weight and (ikControl.Weight + (targetWeight - ikControl.Weight) * 0.2) or targetWeight
			end
		end)
	end
	followServerNPC()
end

local function bootstrapRemotePlayer(player, bindingSetManager)
    if player == LocalPlayer then
        return
    end

    local function spawnForCharacter(character)
        destroyRemoteController(player)

        character:WaitForChild("Humanoid")
        character:WaitForChild("HumanoidRootPart")
        character:WaitForChild("Head")
        disableBuiltInCharacterAnimation(character)

        local remoteController = createFluxaController(character, bindingSetManager, false)
        _remoteControllers[player] = remoteController
        FluxaService.RegisterController(player, remoteController)
        FluxaReplicationService.StartRemoteReplication(remoteController, player)

        -- Use velocity-based drivers for remote players
        local humanoid = character:FindFirstChild("Humanoid")
        local root = character:FindFirstChild("HumanoidRootPart")
        if humanoid and root then
            createNPCStateDriver(remoteController, humanoid, root, connect)
            createNPCMovementDriver(remoteController, root, connect, true)
        end
    end

    connect(player.CharacterAdded, function(character)
        spawnForCharacter(character)
    end)

    connect(player.CharacterRemoving, function()
        destroyRemoteController(player)
    end)

    if player.Character then
        spawnForCharacter(player.Character)
    end
end

function module:Start(_clientScript: LocalScript)
	FluxaService.Start()
	
	if #_connections > 0 then
		return
	end

	local animFolder = ReplicatedStorage:FindFirstChild("Example3Animations_R15")
	if not animFolder then
		animFolder = ReplicatedStorage:FindFirstChild("Example2Animations_R15")
	end
	if not animFolder then
		warn("Example5 requires Example3Animations_R15 or Example2Animations_R15 in ReplicatedStorage.")
		return
	end

	local bindingSetManager = createBindingSetManager(animFolder)

	local function destroyLocalController()
		disconnectLocalCharacterConnections()
		FluxaReplicationService.StopLocalReplication()

		if _controller then
			FluxaService.UnregisterController(LocalPlayer)
			_controller:Destroy()
			_controller = nil
		end
	end

	local function setupLocalCharacter(character: Model)
		destroyLocalController()
		disableBuiltInCharacterAnimation(character)

		local humanoid = character:WaitForChild("Humanoid")
		local root = character:WaitForChild("HumanoidRootPart")

		-- Do NOT destroy Animator

		_controller = createFluxaController(character, bindingSetManager, true)
		FluxaService.RegisterController(LocalPlayer, _controller)

		setBaseBlend(_controller, "LastYaw", getYaw(root.CFrame))
		createInputDriver(_controller, connectLocal)
		createHumanoidStateDriver(_controller, humanoid, function()
			FluxaReplicationService.SendLocalPacket()
		end, connectLocal)
		createMovementDriver(_controller, humanoid, root, connectLocal)
		createCombatDriver(_controller, connectLocal)
		createCameraDriver(_controller, connectLocal)
		FluxaReplicationService.SetLocalReplicationEnabled(_localControllerReplicationEnabled)
		if _localControllerReplicationEnabled then
			FluxaReplicationService.StartLocalReplication(_controller)
		end

		-- Add LookAt IKControl for player
		createLookAtIKControl(character, humanoid, true)
	end

	for _, inst in ipairs(CollectionService:GetTagged(FLUXA_NPC_TAG)) do
		if inst:IsA("Model") then
			bootstrapTaggedNPC(inst, bindingSetManager)
		end
	end

	connect(CollectionService:GetInstanceAddedSignal(FLUXA_NPC_TAG), function(inst)
		if inst:IsA("Model") then
			bootstrapTaggedNPC(inst, bindingSetManager)
		end
	end)

	connect(CollectionService:GetInstanceRemovedSignal(FLUXA_NPC_TAG), function(inst)
		if inst:IsA("Model") then
			destroyNPCControllerByModel(inst)
		end
	end)

	connect(LocalPlayer.CharacterAdded, function(character)
		setupLocalCharacter(character)
	end)

	connect(LocalPlayer.CharacterRemoving, function()
		destroyLocalController()
	end)

	local currentCharacter = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	setupLocalCharacter(currentCharacter)

	for _, player in ipairs(Players:GetPlayers()) do
		bootstrapRemotePlayer(player, bindingSetManager)
	end
	connect(Players.PlayerAdded, function(player)
		bootstrapRemotePlayer(player, bindingSetManager)
	end)
	connect(Players.PlayerRemoving, function(player)
		destroyRemoteController(player)
	end)
	
	print("Example5 loaded! Set StarterPlayerScripts.Client.ex = 5 to use binding-manager + FluxaService demo with server NPCs.")
end

function module:Destroy()
	disconnectLocalCharacterConnections()
	disconnectAll()
	FluxaReplicationService.StopLocalReplication()

	if _controller then
		FluxaService.UnregisterController(LocalPlayer)
		_controller:Destroy()
		_controller = nil
	end

	for player in pairs(_remoteControllers) do
		destroyRemoteController(player)
	end
	for id in pairs(_npcControllers) do
		destroyNPCController(id)
	end
end

-- -- Patch FluxaController.ApplyReplicationPacket for debug
-- local origApplyReplicationPacket = FluxaController.ApplyReplicationPacket
-- FluxaController.ApplyReplicationPacket = function(self, packet)
-- 	if packet and packet.Layers and packet.Layers.UpperBody and packet.Layers.UpperBody.AnimationStartTimes then
-- 		for anim, time in pairs(packet.Layers.UpperBody.AnimationStartTimes) do
-- 			print("[Fluxa][DEBUG][Replication] UpperBody AnimationStartTimes:", anim, time)
-- 		end
-- 	end
-- 	origApplyReplicationPacket(self, packet)
-- 	-- After applying, check if Attack track exists and is playing
-- 	local attackTrack = self.GetTrack and self:GetTrack("Attack")
-- 	if attackTrack then
-- 		print("[Fluxa][DEBUG][Replication] Attack track exists. IsPlaying:", attackTrack.IsPlaying, "Weight:", attackTrack.Weight)
-- 	else
-- 		warn("[Fluxa][DEBUG][Replication] Attack track missing on controller:", tostring(self.Character and self.Character:GetFullName() or self))
-- 	end
-- end

return module
