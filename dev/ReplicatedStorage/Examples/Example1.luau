--!nonstrict
local module = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Shared = ReplicatedFirst:WaitForChild("Shared")
local ConnectionRegistry = require(Shared.ConnectionRegistry)
local temp = ConnectionRegistry.new()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- You can require Fluxa and grab modules this way:
-- local Fluxa = require(ReplicatedStorage.Packages.fluxa)
-- local AnimationAsset = Fluxa.AnimationAsset
-- but I prefer the method of just requiring modules manually for TypeScript-ability
local AnimationAsset = require(ReplicatedStorage.Packages.fluxa.AnimationAsset)
local AnimationTrack = require(ReplicatedStorage.Packages.fluxa.AnimationTrack)
local Pose = require(ReplicatedStorage.Packages.fluxa.Pose)
local UniversalJointWriter = require(ReplicatedStorage.Packages.fluxa.UniversalJointWriter)

local X_WEIGHT_ATTRIBUTE: string = "xweight"
local Z_WEIGHT_ATTRIBUTE: string = "zweight"

function module:Start(clientScript: LocalScript)
    if not clientScript then
        warn("Example1: No client script provided!")
        return
    end

    local X_WEIGHT: number = 0.35
    local Z_WEIGHT: number = 0.65

    if not clientScript:GetAttribute(X_WEIGHT_ATTRIBUTE) then
        clientScript:SetAttribute(X_WEIGHT_ATTRIBUTE, X_WEIGHT)
    else
        local got = clientScript:GetAttribute(X_WEIGHT_ATTRIBUTE)
        if type(got) == "number" then
            X_WEIGHT = got
        else
            warn("Example1: Invalid xweight attribute, expected number but got", type(got))
        end
    end

    if not clientScript:GetAttribute(Z_WEIGHT_ATTRIBUTE) then
        clientScript:SetAttribute(Z_WEIGHT_ATTRIBUTE, Z_WEIGHT)
        
        local got = clientScript:GetAttribute(Z_WEIGHT_ATTRIBUTE)
        if type(got) == "number" then
            Z_WEIGHT = got
        else
            warn("Example1: Invalid zweight attribute, expected number but got", type(got))
        end
    end

    -- the index the registered connection is stored at
    local _r1 = temp:Register(clientScript:GetAttributeChangedSignal(X_WEIGHT_ATTRIBUTE):Connect(function()
        local this = clientScript:GetAttribute(X_WEIGHT_ATTRIBUTE)
        local other = clientScript:GetAttribute(Z_WEIGHT_ATTRIBUTE)
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
    end))

    -- the index the registered connection is stored at
    local _r2 = temp:Register(clientScript:GetAttributeChangedSignal(Z_WEIGHT_ATTRIBUTE):Connect(function()
        local this = clientScript:GetAttribute(Z_WEIGHT_ATTRIBUTE)
        local other = clientScript:GetAttribute(X_WEIGHT_ATTRIBUTE)
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
    end))

    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if animator then
        animator:Destroy()
    end

    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

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
    local animFolder = ReplicatedStorage:FindFirstChild("Example1Animations_R6")
    if animFolder then
        for _: number, anim: Instance in ipairs(animFolder:GetChildren()) do
            if anim:IsA("KeyframeSequence") then
                print("Loading animation:", anim.Name)
                animAssets[anim.Name] = AnimationAsset.new(anim, anim.Name)
            end
        end
    end

    -- Create animation tracks for each direction
    local animTracks = {
        Idle = AnimationTrack.new(animAssets.Idle or {}, { Speed = 1, Loop = true }),
        Forward = AnimationTrack.new(animAssets.WalkForward or {}, { Speed = 1, Loop = true }),
        Right = AnimationTrack.new(animAssets.WalkRight or {}, { Speed = 1, Loop = true }),
        Backward = AnimationTrack.new(animAssets.WalkBackward or {}, { Speed = 1, Loop = true }),
        Left = AnimationTrack.new(animAssets.WalkLeft or {}, { Speed = 1, Loop = true }),
    }

    local jointMap, retarget = UniversalJointWriter.BuildJointMap(character)

    -- Start with Idle
    if animTracks.Idle then
        animTracks.Idle:Play()
    end

    -- Update loop
    local blendedPose = Pose.new({})

    -- the index the registered connection is stored at
    local _r3 = temp:Register(RunService.RenderStepped:Connect(function(deltaTime)
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
            ["Backward"] = backWeight;
            ["Left"] = leftWeight;
        }

        -- Determine direction based on input
        local directionNames = { "Idle", "Forward", "Right", "Backward", "Left" }
        for _i: number, directionName: string in ipairs(directionNames) do
            if blendWeights[directionName] == 0 then
                if animTracks[directionName] and animTracks[directionName].Playing then
                    animTracks[directionName]:Stop()
                end
            elseif animTracks[directionName] and not animTracks[directionName].Playing then
                animTracks[directionName]:Play()
            end
        end

        local blended: { [string]: CFrame } = {}
        local hasBase: { [string]: boolean } = {}

        for directionName, weight in pairs(blendWeights) do
            if weight > 0 then
                local aplr = animTracks[directionName]
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
    end))

    print("Example1 loaded!")
    print("Loaded", countDictionary(animAssets), "animations")
end

function module:Destroy()
    temp:DisconnectAll()
end

return module