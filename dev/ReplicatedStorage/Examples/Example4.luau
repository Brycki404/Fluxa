--!nonstrict
-- Example4: binding catalogs + binding set manager for runtime track swapping.

local module = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local Fluxa = require(ReplicatedStorage.Packages.fluxa)
local FluxaService = require(ReplicatedStorage.Packages.fluxa.FluxaService)
local FluxaController = Fluxa.FluxaController
local FluxaBindingSetManager = Fluxa.FluxaBindingSetManager
local FluxaReplicationService = Fluxa.FluxaReplicationService
local Example4BindingCatalog = require(script.Parent.Example4BindingCatalog)

local SLOW_WALK_SPEED = 3
local BASE_WALK_SPEED = 3
local MAX_RUN_SPEED = 24
local MOMENTUM_BUILD_RATE = 0.8
local MOMENTUM_DECAY_RATE = 0.4
local SHIFT_KEY = Enum.KeyCode.C
local WEAPON_SWAP_KEY = Enum.KeyCode.V
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
local MAX_DELTA_AIM_PITCH_DEG = 65
local MAX_AIM_PITCH_DEG = 65
local MIN_AIM_PITCH_DEG = -65
local AIM_PITCH_RISE_SPEED = 12
local AIM_PITCH_FADE_SPEED = 2.5
local AIM_PITCH_SMOOTH_SPEED = 14

local _controller = nil
local _remoteControllers = {}
local _connections = {}
local _localControllerReplicationEnabled = true

function module:SetLocalReplicationEnabled(enabled: boolean)
	_localControllerReplicationEnabled = enabled == true
	FluxaReplicationService.SetLocalReplicationEnabled(_localControllerReplicationEnabled)
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

local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(_connections, c)
	return c
end

local function disconnectAll()
	for _, c in ipairs(_connections) do
		c:Disconnect()
	end
	table.clear(_connections)
end

local function createBindingSetManager(folder: Instance?)
	return FluxaBindingSetManager.new({
		Catalog = Example4BindingCatalog,
		SourceContainer = folder,
	})
end

local function createMovementDriver(controller, humanoid, root)
	return connect(RunService.RenderStepped, function(dt)
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
			local momentumAlpha = if shiftHeld then 0 else momentum
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

local function createInputDriver(controller)
	connect(UserInputService.InputBegan, function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == SHIFT_KEY then
			setBaseBlend(controller, "ShiftHeld", true)
		end
	end)
	connect(UserInputService.InputEnded, function(input: InputObject, _: boolean)
		if input.KeyCode == SHIFT_KEY then
			setBaseBlend(controller, "ShiftHeld", false)
		end
	end)
end

local function createHumanoidStateDriver(controller, humanoid)
	connect(humanoid.StateChanged, function(_old, new)
		local now = os.clock()
		local wasAirborne = getBaseBlend(controller, "WasAirborne", false) == true
		local lastLandTriggerTime = getBaseBlend(controller, "LastLandTriggerTime", -math.huge)
		local airState = getBaseState(controller)

		if new == Enum.HumanoidStateType.Jumping then
			wasAirborne = setBaseBlend(controller, "WasAirborne", true)
			airState = setBaseState(controller, "Jump")
			controller:MarkLayerAnimationStart("Base", "Jump")
			controller:Play("Jump")
			FluxaReplicationService.SendLocalPacket()
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
				FluxaReplicationService.SendLocalPacket()
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

local function createCombatDriver(controller)
	return connect(UserInputService.InputBegan, function(input, gameProcessed)
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

local function createCameraDriver(controller)
	return connect(RunService.RenderStepped, function()
		local look = Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame.LookVector or Vector3.new(0, 0, -1)
		controller:SetLayerDriver("UpperBody", "AimPitchInput", look.Y)
	end)
end

local function disableBuiltInCharacterAnimation(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			animator:Destroy()
		end

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

local function createFluxaController(character: Model, bindingSetManager, isLocalController: boolean)
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

	local attackTrack = nil
	local landTrack = nil
	local slowWalkTrack = nil
	local walkTrack = nil
	local runTrack = nil
	local climbTrack = nil
	local attackPoseInfluence = 0
	local landingWeightSmoothed = 0
	local locomotionPhase = 0
	local smoothedAimPitch = 0
	local lastObservedBaseState = "Ground"
	local rifleEquipped = false
	local swapTrackConfigs = {
		Idle = { Layer = "Base", AutoManage = true, InitialWeight = 1, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.2, FadeOutTime = 0.2 } },
		Walk = { Layer = "Base", AutoManage = true, PreservePhaseOnSwap = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.2, FadeOutTime = 0.2 } },
		Run = { Layer = "Base", AutoManage = true, PreservePhaseOnSwap = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.18, FadeOutTime = 0.2 } },
		SlowWalk = { Layer = "Base", AutoManage = true, PreservePhaseOnSwap = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.2, FadeOutTime = 0.24 } },
		Jump = { Layer = "Base", AutoManage = false, ReplicationSeekMode = "Never", TrackOptions = { Looped = false, Speed = 1, FadeInTime = 0.08, FadeOutTime = 0.16 } },
		Fall = { Layer = "Base", AutoManage = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.14, FadeOutTime = 0.18 } },
		Land = { Layer = "Landing", AutoManage = false, ReplicationSeekMode = "Never", TrackOptions = { Looped = false, Speed = 1, FadeInTime = 0.08, FadeOutTime = 0.08 } },
		Climb = { Layer = "Base", AutoManage = true, PreservePhaseOnSwap = true, TrackOptions = { Looped = true, Speed = 1, FadeInTime = 0.18, FadeOutTime = 0.22 } },
		Attack = { Layer = "UpperBody", AutoManage = false, InitialWeight = 0, PreservePhaseOnSwap = false, ReplicationSeekMode = "Never", TrackOptions = { Looped = false, Speed = 1, FadeInTime = 0.08, FadeOutTime = 0.14 } },
	}

	local controller = FluxaController.new({
		Character = character,
		AutoApplyPose = true,
		ReplicationSeekMode = "LoopingOnly",
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

			if isLocalController then
				local rawAimPitch = math.clamp(getLayerBlend(innerController, "UpperBody", "AimPitchInput", 0), -1, 1)
				smoothedAimPitch += (rawAimPitch - smoothedAimPitch) * math.clamp(dt * AIM_PITCH_SMOOTH_SPEED, 0, 1)

				local isAttackPlaying = attackTrack and attackTrack.IsPlaying
				local targetInfluence = 0
				if isAttackPlaying then
					local trackWeight = math.clamp(attackTrack.Weight, 0, 1)
					if trackWeight <= 0 and attackPoseInfluence <= 0 then
						targetInfluence = math.max(targetInfluence, math.min(1, dt * AIM_PITCH_RISE_SPEED))
					end
					targetInfluence = math.max(targetInfluence, trackWeight)
				end

				if targetInfluence > attackPoseInfluence then
					attackPoseInfluence = math.min(targetInfluence, attackPoseInfluence + dt * AIM_PITCH_RISE_SPEED)
				else
					attackPoseInfluence = math.max(targetInfluence, attackPoseInfluence - dt * AIM_PITCH_FADE_SPEED)
				end

				if isAttackPlaying then
					innerController:SetLayerDriver("UpperBody", "State", "Attack")
				else
					innerController:SetLayerDriver("UpperBody", "State", "Idle")
				end
				innerController:SetLayerDriver("UpperBody", "AttackInfluence", attackPoseInfluence)
				innerController:SetLayerDriver("UpperBody", "AimPitch", smoothedAimPitch)
			else
				local replicatedAimPitch = math.clamp(getLayerBlend(innerController, "UpperBody", "AimPitch", 0), -1, 1)
				smoothedAimPitch += (replicatedAimPitch - smoothedAimPitch) * math.clamp(dt * AIM_PITCH_SMOOTH_SPEED, 0, 1)

				local targetAttackInfluence = math.clamp(getLayerBlend(innerController, "UpperBody", "AttackInfluence", 0), 0, 1)
				if targetAttackInfluence > attackPoseInfluence then
					attackPoseInfluence = math.min(targetAttackInfluence, attackPoseInfluence + dt * AIM_PITCH_RISE_SPEED)
				else
					attackPoseInfluence = math.max(targetAttackInfluence, attackPoseInfluence - dt * AIM_PITCH_FADE_SPEED)
				end
			end

			innerController:SetLayerWeight("UpperBody", attackPoseInfluence)
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

			if attackPoseInfluence > 0 then
				if finalPose.RightLowerArm then
					finalPose.RightLowerArm = finalPose.RightLowerArm:Lerp(CFrame.identity, attackPoseInfluence)
				end
				if finalPose.RightHand then
					finalPose.RightHand = finalPose.RightHand:Lerp(CFrame.identity, attackPoseInfluence)
				end

				local aimPitch = getLayerBlend(innerController, "UpperBody", "AimPitch", smoothedAimPitch)
				local desiredPitch = math.clamp(math.rad(MAX_DELTA_AIM_PITCH_DEG) * aimPitch, math.rad(MIN_AIM_PITCH_DEG), math.rad(MAX_AIM_PITCH_DEG))
				local pitchRadians = desiredPitch * attackPoseInfluence
				local pitchOffset = CFrame.Angles(pitchRadians, 0, 0)

				if finalPose.UpperTorso then
					if finalPose.LowerTorso then
						local upperBase = finalPose.UpperTorso
						local compensatedUpper = finalPose.LowerTorso.Rotation:Inverse() * upperBase
						local compensationAlpha = math.clamp(attackPoseInfluence * attackPoseInfluence, 0, 1)
						local blendedUpper = upperBase:Lerp(compensatedUpper, compensationAlpha)
						finalPose.UpperTorso = blendedUpper * pitchOffset
					else
						finalPose.UpperTorso = finalPose.UpperTorso * pitchOffset
					end
				elseif finalPose.Torso then
					finalPose.Torso = finalPose.Torso * pitchOffset
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

	local function updateTrackRef(trackName: string, track: any)
		if trackName == "Walk" then
			walkTrack = track
		elseif trackName == "Run" then
			runTrack = track
		elseif trackName == "SlowWalk" then
			slowWalkTrack = track
		elseif trackName == "Attack" then
			attackTrack = track
		elseif trackName == "Land" then
			landTrack = track
		elseif trackName == "Climb" then
			climbTrack = track
		end
	end

	local function loadTrackFromBinding(trackName: string, trackConfig)
		local track = bindingSetManager:LoadTrack(controller, trackName, trackConfig)
		updateTrackRef(trackName, track)
		return track
	end

	local function applyWeaponLayer()
		local loadedTracks = nil
		if rifleEquipped then
			loadedTracks = bindingSetManager:SetCatalogLayer("EquippedWeapon", "Rifle", controller, swapTrackConfigs)
		else
			loadedTracks = bindingSetManager:RemoveBindingLayer("EquippedWeapon", controller, swapTrackConfigs)
		end

		for trackName, track in pairs(loadedTracks or {}) do
			updateTrackRef(trackName, track)
		end
	end

	for trackName, trackConfig in pairs(swapTrackConfigs) do
		local initialConfig = table.clone(trackConfig)
		initialConfig.BindingId = Example4BindingCatalog:GetInitialTrackBinding(trackName)
		loadTrackFromBinding(trackName, initialConfig)
	end

	if isLocalController then
		connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then return end
			if input.KeyCode == WEAPON_SWAP_KEY then
				rifleEquipped = not rifleEquipped
				applyWeaponLayer()
				FluxaReplicationService.SendLocalPacket()
			end
		end)
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

local function destroyRemoteController(player)
	local controller = _remoteControllers[player]
	if controller then
		controller:Destroy()
		_remoteControllers[player] = nil
	end
end

local function bootstrapRemotePlayer(player, bindingSetManager)
	if player == LocalPlayer then return end

	local function spawnForCharacter(character)
		destroyRemoteController(player)
		character:WaitForChild("Humanoid")
		character:WaitForChild("HumanoidRootPart")
		character:WaitForChild("Head")
		disableBuiltInCharacterAnimation(character)
		local remoteController = createFluxaController(character, bindingSetManager, false)
		_remoteControllers[player] = remoteController
		FluxaReplicationService.StartRemoteReplication(remoteController, player)
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
	
	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local root = character:WaitForChild("HumanoidRootPart")

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		animator:Destroy()
	end

	local animFolder = ReplicatedStorage:FindFirstChild("Example4Animations_R15")
	if not animFolder then
		warn("Example4 requires ReplicatedStorage.Example4Animations_R15 with both base and rifle bindings. This demo is not configured in the dev place by default.")
		return
	end

	local bindingSetManager = createBindingSetManager(animFolder)
	_controller = createFluxaController(character, bindingSetManager, true)

	setBaseBlend(_controller, "LastYaw", getYaw(root.CFrame))
	createInputDriver(_controller)
	createHumanoidStateDriver(_controller, humanoid)
	createMovementDriver(_controller, humanoid, root)
	createCombatDriver(_controller)
	createCameraDriver(_controller)
	FluxaReplicationService.SetLocalReplicationEnabled(_localControllerReplicationEnabled)
	if _localControllerReplicationEnabled then
		FluxaReplicationService.StartLocalReplication(_controller)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		bootstrapRemotePlayer(player, bindingSetManager)
	end
	connect(Players.PlayerAdded, function(player)
		bootstrapRemotePlayer(player, bindingSetManager)
	end)
	connect(Players.PlayerRemoving, function(player)
		destroyRemoteController(player)
	end)

	print("Example4 loaded! This binding-set demo expects a dedicated Example4Animations_R15 folder and is not wired into the dev place by default.")
end

function module:Destroy()
	disconnectAll()
	if _controller then
		_controller:Destroy()
		_controller = nil
	end
	for player, _ in pairs(_remoteControllers) do
		destroyRemoteController(player)
	end
end

return module