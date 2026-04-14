--!nonstrict
-- Example3: single controller script with external-style drivers that only call Set/Play.

local module = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local Fluxa = require(ReplicatedStorage.Packages.fluxa)
local AnimationAsset = Fluxa.AnimationAsset
local FluxaController = Fluxa.FluxaController

local SLOW_WALK_SPEED = 6
local BASE_WALK_SPEED = 10
local MAX_RUN_SPEED = 22
local MOMENTUM_BUILD_RATE = 0.8
local MOMENTUM_DECAY_RATE = 0.4
local SHIFT_KEY = Enum.KeyCode.C
local SPEED_SMOOTH_SPEED = 10
local LAND_RETRIGGER_COOLDOWN = 0.12
local LAND_BLEND_DURATION = 0.16
local LAND_GROUND_START_ALPHA = 0.45
local MAX_TURN_LEAN_DEG = 14
local TURN_LEAN_SENSITIVITY = 0.2
local TURN_LEAN_SMOOTH_SPEED = 10
local MIN_LEAN_SCALE = 0.2
local MAX_DELTA_AIM_PITCH_DEG = 65
local MAX_AIM_PITCH_DEG = 65
local MIN_AIM_PITCH_DEG = -65
local AIM_PITCH_RISE_SPEED = 12   -- how fast influence rises while attack plays
local AIM_PITCH_FADE_SPEED = 2.5  -- how fast influence decays after (~0.4s tail)
local AIM_PITCH_SMOOTH_SPEED = 14 -- smooth camera pitch input to avoid jittery tail artifacts

local _controller = nil
local _connections = {}

local function getYaw(cf)
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function deltaAngle(a, b)
	return (a - b + math.pi) % (2 * math.pi) - math.pi
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

local function loadAssets(folder: Instance?)
	local assets = {}
	if not folder then
		return assets
	end

	for _, inst in ipairs(folder:GetChildren()) do
		if inst:IsA("KeyframeSequence") then
			assets[inst.Name] = AnimationAsset.new(inst, inst.Name)
		end
	end

	return assets
end

local function createMovementDriver(controller, humanoid, root, state)
	return connect(RunService.RenderStepped, function(dt)
		local vel = root.AssemblyLinearVelocity
		local planarSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local moveDir = humanoid.MoveDirection
		local isMoving = moveDir.Magnitude > 0.1

		state.SmoothedPlanarSpeed += (planarSpeed - state.SmoothedPlanarSpeed) * math.clamp(dt * SPEED_SMOOTH_SPEED, 0, 1)

		local currentYaw = getYaw(root.CFrame)
		local yawDelta = deltaAngle(currentYaw, state.LastYaw)
		local turnRate = if dt > 0 then yawDelta / dt else 0
		state.LastYaw = currentYaw

		if isMoving then
			local targetCFrame = CFrame.lookAt(root.Position, root.Position + moveDir)
			root.CFrame = root.CFrame:Lerp(targetCFrame, math.clamp(dt * 10, 0, 1))
		end

		if not isMoving then
			state.Momentum = 0
		elseif not state.ShiftHeld and state.AirState == "Ground" then
			state.Momentum = math.min(1, state.Momentum + MOMENTUM_BUILD_RATE * dt)
		else
			state.Momentum = math.max(0, state.Momentum - MOMENTUM_DECAY_RATE * dt)
		end

		if state.ShiftHeld then
			humanoid.WalkSpeed = SLOW_WALK_SPEED
		else
			humanoid.WalkSpeed = BASE_WALK_SPEED + (MAX_RUN_SPEED - BASE_WALK_SPEED) * state.Momentum
		end

		local maxLean = math.rad(MAX_TURN_LEAN_DEG)
		local targetLean = 0
		if isMoving then
			local speedAlpha = math.clamp(state.SmoothedPlanarSpeed / MAX_RUN_SPEED, 0, 1)
			local momentumAlpha = if state.ShiftHeld then 0 else state.Momentum
			local leanScale = math.clamp((MIN_LEAN_SCALE + momentumAlpha) * speedAlpha, 0, 1)
			targetLean = math.clamp(-turnRate * TURN_LEAN_SENSITIVITY * leanScale, -maxLean, maxLean)
		end
		state.TurnLean = state.TurnLean
			+ (targetLean - state.TurnLean) * math.clamp(dt * TURN_LEAN_SMOOTH_SPEED, 0, 1)

		if state.AirState == "Land" then
			state.LandBlendTime += dt
			if state.LandBlendTime >= LAND_BLEND_DURATION then
				state.AirState = "Ground"
				state.LandBlendTime = 0
			end
		else
			state.LandBlendTime = 0
		end

		controller:Set("Speed", planarSpeed)
		controller:Set("Direction", moveDir)
		controller:Set("Moving", isMoving)
		controller:Set("Momentum", state.Momentum)
		controller:Set("ShiftHeld", state.ShiftHeld)
		controller:Set("AirState", state.AirState)
		controller:Set("LandBlendTime", state.LandBlendTime)
		controller:Set("TurnLean", state.TurnLean)
	end)
end

local function createInputDriver(controller, state)
	connect(UserInputService.InputBegan, function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == SHIFT_KEY then
			state.ShiftHeld = true
			controller:Set("ShiftHeld", true)
		end
	end)
end

local function createHumanoidStateDriver(controller, humanoid, state)
	connect(humanoid.StateChanged, function(_old, new)
		local now = os.clock()

		if new == Enum.HumanoidStateType.Jumping then
			state.WasAirborne = true
			state.AirState = "Jump"
			controller:Set("AirState", "Jump")
			controller:Play("Jump")
		elseif new == Enum.HumanoidStateType.Freefall then
			state.WasAirborne = true
			state.AirState = "Fall"
			controller:Set("AirState", "Fall")
			controller:Play("Fall")
		elseif new == Enum.HumanoidStateType.Climbing then
			state.AirState = "Climb"
			state.WasAirborne = false
			controller:Set("AirState", "Climb")
			controller:Play("Climb")
		elseif new == Enum.HumanoidStateType.Landed
			or new == Enum.HumanoidStateType.Running
			or new == Enum.HumanoidStateType.RunningNoPhysics then

			controller:StopTrack("Fall")
			controller:StopTrack("Jump")
			controller:StopTrack("Climb")

			local canTriggerLand = state.WasAirborne
				and (now - state.LastLandTriggerTime) >= LAND_RETRIGGER_COOLDOWN

			if canTriggerLand then
				state.AirState = "Land"
				state.WasAirborne = false
				state.LastLandTriggerTime = now
				state.LandBlendTime = 0
				controller:Set("AirState", "Land")
				controller:Set("LandBlendTime", 0)
				controller:Play("Land")
			elseif state.AirState ~= "Land" then
				state.AirState = "Ground"
				state.WasAirborne = false
				controller:Set("AirState", "Ground")
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
			controller:Play("Attack")
		end
	end)
end

local function createCameraDriver(controller)
	return connect(RunService.RenderStepped, function()
		local look = Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame.LookVector or Vector3.new(0, 0, -1)
		controller:Set("AimPitch", look.Y)
	end)
end

function module:Start(_clientScript: LocalScript)
	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local root = character:WaitForChild("HumanoidRootPart")

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		animator:Destroy()
	end

	local animFolder = ReplicatedStorage:FindFirstChild("Example3Animations_R15")
	if not animFolder then
		animFolder = ReplicatedStorage:FindFirstChild("Example2Animations_R15")
	end
	local assets = loadAssets(animFolder)

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
	local attackPoseInfluence = 0
	local smoothedAimPitch = 0

	_controller = FluxaController.new({
		Character = character,
		AutoApplyPose = true,
		AutoStart = true,
		OnPreStep = function(controller, dt)
			local rawAimPitch = math.clamp(controller:Get("AimPitch") or 0, -1, 1)
			smoothedAimPitch += (rawAimPitch - smoothedAimPitch) * math.clamp(dt * AIM_PITCH_SMOOTH_SPEED, 0, 1)

			local isAttackPlaying = attackTrack and attackTrack.Playing
			local targetInfluence = 0
			if isAttackPlaying then
				local trackWeight = math.clamp(attackTrack.Weight, 0, 1)
				-- Bootstrap from zero: with layer weight at 0, track weight cannot rise until layer runs once.
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

			-- Keep Override mode, but gate how much this layer can override Base.
			controller:SetLayerWeight("UpperBody", attackPoseInfluence)
		end,
		OnPostBlend = function(controller, finalPose, _dt)
			local turnLean = controller:Get("TurnLean") or 0
			if math.abs(turnLean) > 1e-4 then
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
				-- Blend arm reset with influence instead of hard overriding, so it fades out cleanly.
				if finalPose.RightLowerArm then
					finalPose.RightLowerArm = finalPose.RightLowerArm:Lerp(CFrame.identity, attackPoseInfluence)
				end
				if finalPose.RightHand then
					finalPose.RightHand = finalPose.RightHand:Lerp(CFrame.identity, attackPoseInfluence)
				end

				local aimPitch = smoothedAimPitch
				local desiredPitch = math.clamp(math.rad(MAX_DELTA_AIM_PITCH_DEG) * aimPitch, math.rad(MIN_AIM_PITCH_DEG), math.rad(MAX_AIM_PITCH_DEG))
				local pitchRadians = desiredPitch * attackPoseInfluence
				local pitchOffset = CFrame.Angles(pitchRadians, 0, 0)

				if finalPose.UpperTorso then
					-- Blend out lower-torso compensation during fade so upper torso returns smoothly without snapping.
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
		Drivers = {
			Speed = 0,
			Direction = Vector3.zero,
			Moving = false,
			Momentum = 0,
			ShiftHeld = false,
			AirState = "Ground",
			LandBlendTime = 0,
			TurnLean = 0,
			AimPitch = 0,
		},
		Layers = {
			Base = { Weight = 1, Order = 0 },
			UpperBody = { Weight = 0, Order = 1, Mask = upperBodyMask },
		},
	})

	_controller:AddTrack("Idle", assets.Idle or {}, {
		Layer = "Base",
		AutoManage = true,
		InitialWeight = 1,
		TrackOptions = { Loop = true, Speed = 1, FadeInTime = 0.2, FadeOutTime = 0.2 },
	})
	_controller:AddTrack("Walk", assets.Walk or {}, {
		Layer = "Base",
		AutoManage = true,
		TrackOptions = { Loop = true, Speed = 1, FadeInTime = 0.2, FadeOutTime = 0.2 },
	})
	_controller:AddTrack("Run", assets.Run or {}, {
		Layer = "Base",
		AutoManage = true,
		TrackOptions = { Loop = true, Speed = 1, FadeInTime = 0.18, FadeOutTime = 0.2 },
	})
	_controller:AddTrack("SlowWalk", assets.SlowWalk or assets.Walk or {}, {
		Layer = "Base",
		AutoManage = true,
		TrackOptions = { Loop = true, Speed = 1, FadeInTime = 0.2, FadeOutTime = 0.24 },
	})
	_controller:AddTrack("Jump", assets.Jump or {}, {
		Layer = "Base",
		AutoManage = false,
		IsOneShot = true,
		TrackOptions = { Loop = false, Speed = 1, FadeInTime = 0.08, FadeOutTime = 0.16 },
	})
	_controller:AddTrack("Fall", assets.Fall or {}, {
		Layer = "Base",
		AutoManage = true,
		TrackOptions = { Loop = true, Speed = 1, FadeInTime = 0.14, FadeOutTime = 0.18 },
	})
	_controller:AddTrack("Land", assets.Land or {}, {
		Layer = "Base",
		AutoManage = false,
		IsOneShot = true,
		TrackOptions = { Loop = false, Speed = 1, FadeInTime = 0.08, FadeOutTime = 0.16 },
	})
	_controller:AddTrack("Climb", assets.Climb or {}, {
		Layer = "Base",
		AutoManage = true,
		TrackOptions = { Loop = true, Speed = 1, FadeInTime = 0.18, FadeOutTime = 0.22 },
	})
	attackTrack = _controller:AddTrack("Attack", assets.Attack or assets.Jump or {}, {
		Layer = "UpperBody",
		AutoManage = false,
		IsOneShot = true,
		InitialWeight = 0,
		TrackOptions = { Loop = false, Speed = 1, FadeInTime = 0.08, FadeOutTime = 0.14 },
	})

	_controller:CreateBlendTree("Locomotion", function(controller, _dt)
		local speed = controller:Get("Speed") or 0
		local moving = controller:Get("Moving") == true
		local shiftHeld = controller:Get("ShiftHeld") == true
		local momentum = controller:Get("Momentum") or 0
		local airState = controller:Get("AirState") or "Ground"
		local landBlendTime = controller:Get("LandBlendTime") or 0

		if airState == "Jump" then
			return {
				Idle = 0,
				SlowWalk = 0,
				Walk = 0,
				Run = 0,
				Jump = 1,
				Fall = 0,
				Land = 0,
				Climb = 0,
			}
		elseif airState == "Fall" then
			return {
				Idle = 0,
				SlowWalk = 0,
				Walk = 0,
				Run = 0,
				Jump = 0,
				Fall = 1,
				Land = 0,
				Climb = 0,
			}
		elseif airState == "Climb" then
			return {
				Idle = 0,
				SlowWalk = 0,
				Walk = 0,
				Run = 0,
				Jump = 0,
				Fall = 0,
				Land = 0,
				Climb = 1,
			}
		elseif airState == "Land" then
			local landProgress = math.clamp(landBlendTime / LAND_BLEND_DURATION, 0, 1)
			local groundAlpha = math.clamp(
				LAND_GROUND_START_ALPHA + (1 - LAND_GROUND_START_ALPHA) * landProgress,
				0,
				1
			)
			local landAlpha = 1 - groundAlpha
			local moveMag = math.min(1, humanoid.MoveDirection.Magnitude)

			if shiftHeld then
				return {
					Idle = (1 - moveMag) * groundAlpha,
					SlowWalk = moveMag * groundAlpha,
					Walk = 0,
					Run = 0,
					Jump = 0,
					Fall = 0,
					Land = landAlpha,
					Climb = 0,
				}
			end

			return {
				Idle = (1 - moveMag) * groundAlpha,
				SlowWalk = 0,
				Walk = moveMag * (1 - momentum) * groundAlpha,
				Run = moveMag * momentum * groundAlpha,
				Jump = 0,
				Fall = 0,
				Land = landAlpha,
				Climb = 0,
			}
		end

		if not moving then
			return {
				Idle = 1,
				SlowWalk = 0,
				Walk = 0,
				Run = 0,
				Jump = 0,
				Fall = 0,
				Land = 0,
				Climb = 0,
			}
		end

		if shiftHeld then
			local slowWeight = math.clamp(speed / SLOW_WALK_SPEED, 0, 1)
			return {
				Idle = 1 - slowWeight,
				SlowWalk = slowWeight,
				Walk = 0,
				Run = 0,
				Jump = 0,
				Fall = 0,
				Land = 0,
				Climb = 0,
			}
		end

		local moveMag = math.min(1, humanoid.MoveDirection.Magnitude)
		return {
			Idle = 1 - moveMag,
			SlowWalk = 0,
			Walk = moveMag * (1 - momentum),
			Run = moveMag * momentum,
			Jump = 0,
			Fall = 0,
			Land = 0,
			Climb = 0,
		}
	end)

	local movementState = {
		ShiftHeld = false,
		Momentum = 0,
		AirState = "Ground",
		WasAirborne = false,
		LandBlendTime = 0,
		LastLandTriggerTime = -math.huge,
		SmoothedPlanarSpeed = 0,
		LastYaw = getYaw(root.CFrame),
		TurnLean = 0,
	}

	createInputDriver(_controller, movementState)
	createHumanoidStateDriver(_controller, humanoid, movementState)
	createMovementDriver(_controller, humanoid, root, movementState)
	createCombatDriver(_controller)
	createCameraDriver(_controller)

	print("Example3 loaded! Set StarterPlayerScripts.Client.ex = 3 to use this controller demo.")
end

function module:Destroy()
	disconnectAll()

	if _controller then
		_controller:Destroy()
		_controller = nil
	end
end

return module
