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

local _controller = nil
local _connections = {}

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

local function createMovementDriver(controller, humanoid, root)
	return connect(RunService.RenderStepped, function()
		local vel = root.AssemblyLinearVelocity
		local planarSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local moveDir = humanoid.MoveDirection

		controller:Set("Speed", planarSpeed)
		controller:Set("Direction", moveDir)
		controller:Set("Moving", moveDir.Magnitude > 0.1)
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
		UpperTorso = true,
		Torso = true,
		LowerTorso = true,
		LeftUpperArm = true,
		LeftLowerArm = true,
		LeftHand = true,
		RightUpperArm = true,
		RightLowerArm = true,
		RightHand = true,
		Head = true,
	}

	_controller = FluxaController.new({
		Character = character,
		AutoApplyPose = true,
		AutoStart = true,
		Params = {
			Speed = 0,
			Direction = Vector3.zero,
			Moving = false,
			AimPitch = 0,
		},
		Layers = {
			Base = { Weight = 1, Order = 0 },
			UpperBody = { Weight = 1, Order = 1, Mask = upperBodyMask },
		},
	})

	_controller:AddTrack("Idle", assets.Idle or {}, {
		Layer = "Base",
		AutoManage = true,
		InitialWeight = 1,
		PlayerOptions = { Loop = true, Speed = 1, FadeInTime = 0.2, FadeOutTime = 0.2 },
	})
	_controller:AddTrack("Walk", assets.Walk or {}, {
		Layer = "Base",
		AutoManage = true,
		PlayerOptions = { Loop = true, Speed = 1, FadeInTime = 0.2, FadeOutTime = 0.2 },
	})
	_controller:AddTrack("Run", assets.Run or {}, {
		Layer = "Base",
		AutoManage = true,
		PlayerOptions = { Loop = true, Speed = 1, FadeInTime = 0.18, FadeOutTime = 0.2 },
	})
	_controller:AddTrack("Attack", assets.Attack or assets.Jump or {}, {
		Layer = "UpperBody",
		AutoManage = false,
		IsOneShot = true,
		InitialWeight = 0,
		PlayerOptions = { Loop = false, Speed = 1, FadeInTime = 0.08, FadeOutTime = 0.14 },
	})

	_controller:CreateBlendTree("Locomotion", function(controller, _dt)
		local speed = controller:Get("Speed") or 0
		local moving = controller:Get("Moving") == true

		if not moving then
			return {
				Idle = 1,
				Walk = 0,
				Run = 0,
			}
		end

		local walkSpeed = math.clamp(speed / 10, 0, 1)
		local runWeight = math.clamp((speed - 8) / 10, 0, 1)
		local walkWeight = math.clamp(walkSpeed - runWeight * 0.25, 0, 1)
		local idleWeight = math.clamp(1 - math.max(walkWeight, runWeight), 0, 1)

		return {
			Idle = idleWeight,
			Walk = walkWeight,
			Run = runWeight,
		}
	end)

	_controller:CreateBlendTree("AimLayer", function(controller, _dt)
		local pitch = controller:Get("AimPitch") or 0
		local targetWeight = math.abs(math.clamp(pitch, -1, 1))

		controller:SetLayerWeight("UpperBody", targetWeight)
		return nil
	end)

	createMovementDriver(_controller, humanoid, root)
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
