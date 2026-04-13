--!strict
-- Animation System Test Script

local X_WEIGHT: number = 0.35
local Z_WEIGHT: number = 0.65

script:GetAttributeChangedSignal("X_WEIGHT"):Connect(function()
	local this = script:GetAttribute("X_WEIGHT")
	local other = script:GetAttribute("Z_WEIGHT")
	if this and other then
		X_WEIGHT = this
		Z_WEIGHT = 1 - this
	elseif this then
		X_WEIGHT = 1
		Z_WEIGHT = 0.5
	else
		X_WEIGHT = 0.5
		Z_WEIGHT = 0.5
	end
end)

script:GetAttributeChangedSignal("Z_WEIGHT"):Connect(function()
	local this = script:GetAttribute("Z_WEIGHT")
	local other = script:GetAttribute("X_WEIGHT")
	if this and other then
		Z_WEIGHT = this
		X_WEIGHT = 1 - this
	elseif this then
		Z_WEIGHT = 1
		X_WEIGHT = 0.5
	else
		Z_WEIGHT = 0.5
		X_WEIGHT = 0.5
	end
end)

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

local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

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
			animAssets[anim.Name] = AnimationAsset.new(anim, anim.Name)
		end
	end
end

-- Create animation players for each direction
local players = {
	Idle = AnimationPlayer.new(animAssets.Idle or {}, { Speed = 1, Loop = true }),
	Forward = AnimationPlayer.new(animAssets.WalkForward or {}, { Speed = 1, Loop = true }),
	Right = AnimationPlayer.new(animAssets.WalkRight or {}, { Speed = 1, Loop = true }),
	Back = AnimationPlayer.new(animAssets.WalkBackward or {}, { Speed = 1, Loop = true }),
	Left = AnimationPlayer.new(animAssets.WalkLeft or {}, { Speed = 1, Loop = true }),
}

local currentDirection: string = "Idle"
local jointMap, retarget = UniversalJointWriter.BuildJointMap(character)

-- Start with Idle
if players[currentDirection] then
	players[currentDirection]:Play()
end

-- Input handling for testing
local UserInputService = game:GetService("UserInputService")

-- Update loop
local runService = game:GetService("RunService")
local _FABRIK = require(ReplicatedStorage.Packages.fluxa.IK.FABRIK)
local blendedPose = Pose.new({})

runService.RenderStepped:Connect(function(deltaTime)
	--blend
	local raw = humanoid.MoveDirection
	local rootCF = humanoidRootPart.CFrame
	local right = rootCF.RightVector
	local forward = rootCF.LookVector

	-- flatten to XZ
	right = Vector3.new(right.X, 0, right.Z).Unit
	forward = Vector3.new(forward.X, 0, forward.Z).Unit

	local moveX = raw:Dot(right)
	local moveZ = raw:Dot(forward)

	-- 2D blend vector
	local dir = Vector2.zero
	local blendVec = Vector2.new(moveX, moveZ)
	local mag = math.min(1, blendVec.Magnitude)
	local idleWeight = 1 - mag
	local movePortion = 0+mag -- total weight avilable for F/B/L/R

	if mag > 0 then
		dir = blendVec / mag
	end

	local weightedX = dir.X * X_WEIGHT
	local weightedZ = dir.Y * Z_WEIGHT

	local _angle = math.atan2(weightedX, weightedZ)
	local forwardRaw = math.max(0, weightedZ)
	local backRaw    = math.max(0, -weightedZ)
	local rightRaw   = math.max(0, weightedX)
	local leftRaw    = math.max(0, -weightedX)

	local dirSum = forwardRaw + backRaw + rightRaw + leftRaw
	local forwardWeight, backWeight, rightWeight, leftWeight = 0, 0, 0, 0
	if dirSum > 0 then
		forwardWeight = movePortion * (forwardRaw / dirSum)
		backWeight    = movePortion * (backRaw    / dirSum)
		rightWeight   = movePortion * (rightRaw   / dirSum)
		leftWeight    = movePortion * (leftRaw    / dirSum)
	end

	local blendWeights = {
		["Idle"] = idleWeight;
		["Forward"] = forwardWeight;
		["Right"] = rightWeight;
		["Back"] = backWeight;
		["Left"] = leftWeight;
	}

	-- Determine direction based on input
	local directionNames = { "Idle", "Forward", "Right", "Back", "Left" }
	for _i: number, directionName: string in ipairs(directionNames) do
		if blendWeights[directionName] == 0 then
			if players[directionName] and players[directionName].Playing then
				players[directionName]:Stop()
			end
		elseif players[directionName] and not players[directionName].Playing then
			players[directionName]:Play()
		end
	end

	local blended: { [string]: CFrame } = {}
	local hasBase: { [string]: boolean } = {}

	for directionName, weight in pairs(blendWeights) do
		if weight > 0 then
			local aplr = players[directionName]
			if aplr and aplr.Playing then
				local sample = aplr:Update(deltaTime)

				for joint, cf in pairs(sample.Transforms) do
					if not hasBase[joint] then
						-- first pose becomes the base
						blended[joint] = cf
						hasBase[joint] = true
					else
						-- lerp from current blended to this sample by weight
						blended[joint] = blended[joint]:Lerp(cf, weight)
					end
				end
			end
		end
	end

	blendedPose = Pose.new(blended)
	UniversalJointWriter.ApplyPose(jointMap, retarget, blendedPose.Data)
	
	testParams.Time = testParams.Time + deltaTime
end)

print("Animation test script loaded!")
print("Controls: W=Forward, S=Back, D=Right, A=Left")
print("Loaded", countDictionary(animAssets), "animations")