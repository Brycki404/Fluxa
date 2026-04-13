--!strict
-- Animation System Test Script
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationAsset = require(ReplicatedStorage.Packages.fluxa.AnimationAsset)
local AnimationPlayer = require(ReplicatedStorage.Packages.fluxa.AnimationPlayer)
local Pose = require(ReplicatedStorage.Packages.fluxa.Pose)
local UniversalJointWriter = require(ReplicatedStorage.Packages.fluxa.UniversalJointWriter)

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

local humanoid = character:FindFirstChildOfClass("Humanoid")
local animator = humanoid:FindFirstChildOfClass("Animator")
if animator then
	animator:Destroy()
end

local _humanoidRootPart = character:WaitForChild("HumanoidRootPart")

-- Test parameters
local testParams = {
	Speed = 0,
	Direction = 0, -- 0=Idle, 1=Forward, 2=Right, 3=Back, 4=Left
	Time = 0,
}

local function countDictionary(d: {[any]: any}): number
	local count: number = 0
	for _i: any, _v: any in pairs(d) do
		count += 1
	end
	return count
end

-- Load or create test animations (replace with your actual KeyframeSequences)
local animAssets = {}

-- Try to load animations from ReplicatedStorage
local animFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Animations")
if animFolder then
	for _: number, anim: Instance in ipairs(animFolder:GetChildren()) do
		if anim:IsA("KeyframeSequence") then
			print("Loading animation:", anim.Name)
			animAssets[anim.Name] = AnimationAsset.new(anim, { Name = anim.Name })
		end
	end
end

-- Create animation players for each direction
local players = {
	Idle = AnimationPlayer.new(animAssets.Idle or {}, { Speed = 1, Loop = true }),
	Forward = AnimationPlayer.new(animAssets.WalkForward or {}, { Speed = 1, Loop = true }),
	Right = AnimationPlayer.new(animAssets.WalkRight or {}, { Speed = 1, Loop = true }),
	Back = AnimationPlayer.new(animAssets.WalkBack or {}, { Speed = 1, Loop = true }),
	Left = AnimationPlayer.new(animAssets.WalkLeft or {}, { Speed = 1, Loop = true }),
}

local currentDirection = "Idle"
local jointMap, retarget = UniversalJointWriter.BuildJointMap(character)

-- Start with Idle
if players[currentDirection] then
	players[currentDirection]:Play()
end

-- Input handling for testing
local UserInputService = game:GetService("UserInputService")

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.W then
		testParams.Direction = 1
		testParams.Speed = 1
	elseif input.KeyCode == Enum.KeyCode.S then
		testParams.Direction = 3
		testParams.Speed = 1
	elseif input.KeyCode == Enum.KeyCode.D then
		testParams.Direction = 2
		testParams.Speed = 1
	elseif input.KeyCode == Enum.KeyCode.A then
		testParams.Direction = 4
		testParams.Speed = 1
	end
end)

UserInputService.InputEnded:Connect(function(_input, _gameProcessed)
	testParams.Direction = 0
	testParams.Speed = 0
end)

-- Update loop
local runService = game:GetService("RunService")
local _FABRIK = require(ReplicatedStorage.Packages.fluxa.IK.FABRIK)
local blendedPose = Pose.new({})

runService.RenderStepped:Connect(function(deltaTime)
	-- Determine direction based on input
	local directionNames = { "Idle", "Forward", "Right", "Back", "Left" }
	local newDirection = directionNames[testParams.Direction + 1]
	
	-- Transition if direction changed
	if newDirection ~= currentDirection then
		if players[currentDirection] then
			players[currentDirection]:Stop()
		end
		if players[newDirection] then
			players[newDirection]:Play()
		end
		currentDirection = newDirection
	end
	
	-- Update active player
	local activeSample = players[currentDirection]:Update(deltaTime)

	local blendWeights = {
		[currentDirection] = 1,
	}

	warn("Motor6Ds:", jointMap)

	blendedPose = Pose.new({})
	for _direction, weight in pairs(blendWeights) do
		warn("Sample joints:", activeSample.Transforms)
		for joint: string, transform: Pose.PoseData in pairs(activeSample.Transforms) do
			if not blendedPose.Data[joint] then
				blendedPose.Data[joint] = transform
			else
				blendedPose.Data[joint] = blendedPose.Data[joint]:Lerp(transform, weight)
			end
		end
	end
	
	-- -- Use the active animation's sample
	-- blendedPose.Data = activeSample.Transforms
	
	-- -- Apply to character
	-- Motor6DWriter.ApplyPose(character, blendedPose.Data)

	-- Apply blended pose
	UniversalJointWriter.ApplyPose(jointMap, retarget, blendedPose.Data)
	
	testParams.Time = testParams.Time + deltaTime
end)

print("Animation test script loaded!")
print("Controls: W=Forward, S=Back, D=Right, A=Left")
print("Loaded", countDictionary(animAssets), "animations")