--!nonstrict
local module = {}

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Shared = ReplicatedFirst:WaitForChild("Shared")
local ConnectionRegistry = require(Shared.ConnectionRegistry)
local temp = ConnectionRegistry.new()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationAsset = require(ReplicatedStorage.Packages.fluxa.AnimationAsset)
local AnimationPlayer = require(ReplicatedStorage.Packages.fluxa.AnimationPlayer)
local Pose = require(ReplicatedStorage.Packages.fluxa.Pose)
local UniversalJointWriter = require(ReplicatedStorage.Packages.fluxa.UniversalJointWriter)

-- Tunable speeds (studs/s)
local SLOW_WALK_SPEED   = 6   -- holding shift
local BASE_WALK_SPEED   = 10  -- speed when momentum = 0
local MAX_RUN_SPEED     = 22  -- speed when momentum = 1

-- How fast momentum builds / decays (0-1 per second)
local MOMENTUM_BUILD_RATE  = 0.8   -- ~5 s to reach full run
local MOMENTUM_DECAY_RATE  = 0.4   -- ~2.5 s to bleed back to walk

local SHIFT_KEY = Enum.KeyCode.C

-- Turn-lean tuning
local MAX_TURN_LEAN_DEG = 14
local TURN_LEAN_SENSITIVITY = 0.2 -- lean radians per yaw-rate (rad/s)
local TURN_LEAN_SMOOTH_SPEED = 10
local MIN_LEAN_SCALE = 0.2 -- keep a little lean at low speed so turns still read
local SPEED_SMOOTH_SPEED = 10
local WEIGHT_SMOOTH_SPEED = 12
local LAND_RETRIGGER_COOLDOWN = 0.12
local LAND_BLEND_DURATION = 0.16
local LAND_GROUND_START_ALPHA = 0.45
local LOCOMOTION_MIN_CYCLE_RATE = 0.8
local LOCOMOTION_MAX_CYCLE_RATE = 2.0

local function getYaw(cf: CFrame): number
    local look = cf.LookVector
    return math.atan2(-look.X, -look.Z)
end

local function deltaAngle(a: number, b: number): number
    local d = (a - b + math.pi) % (2 * math.pi) - math.pi
    return d
end

local function getSortedKeys(map: {[any]: any}): {string}
    local keys = {}
    for key in pairs(map) do
        table.insert(keys, tostring(key))
    end
    table.sort(keys)
    return keys
end

local function countDictionary(d: {[any]: any}): number
    local count: number = 0
    for _i: any, _v: any in pairs(d) do
        count += 1
    end
    return count
end

local function debugPrintJointMap(jointMap, retarget)
    print("Example2 Debug: jointMap entries =", countDictionary(jointMap))
    for _, canonicalName in ipairs(getSortedKeys(jointMap)) do
        local info = jointMap[canonicalName]
        local aliasList = info and info.Aliases or {}
        print(string.format(
            "Example2 Debug: joint %s [%s] aliases={%s}",
            canonicalName,
            info.Type,
            table.concat(aliasList, ", ")
        ))
    end

    print("Example2 Debug: retarget entries =", countDictionary(retarget))
    for _, alias in ipairs(getSortedKeys(retarget)) do
        local canonicalName = retarget[alias]
        print(string.format("Example2 Debug: retarget %s -> %s", alias, tostring(canonicalName)))
    end
end

function module:Start(clientScript: LocalScript)
    if not clientScript then
        warn("Example2: No client script provided!")
        return
    end

    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

    local root = character:WaitForChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if animator then
        animator:Destroy()
    end

    -- Load animations from folder (swap in your own KeyframeSequences)
    local animAssets = {}
    local animFolder = ReplicatedStorage:FindFirstChild("Example2Animations_R15")
    if animFolder then
        for _: number, anim: Instance in ipairs(animFolder:GetChildren()) do
            if anim:IsA("KeyframeSequence") then
                print("Loading animation:", anim.Name)
                animAssets[anim.Name] = AnimationAsset.new(anim, anim.Name)
            end
        end
    end

    local animPlayers = {
        Idle     = AnimationPlayer.new(animAssets.Idle     or {}, { Speed = 1, Loop = true,  FadeInTime = 0.18, FadeOutTime = 0.22 });
        SlowWalk = AnimationPlayer.new(animAssets.SlowWalk or {}, { Speed = 1, Loop = true,  FadeInTime = 0.20, FadeOutTime = 0.24 });
        Walk     = AnimationPlayer.new(animAssets.Walk     or {}, { Speed = 1, Loop = true,  FadeInTime = 0.20, FadeOutTime = 0.24 });
        Run      = AnimationPlayer.new(animAssets.Run      or {}, { Speed = 1, Loop = true,  FadeInTime = 0.18, FadeOutTime = 0.22 });
        Jump     = AnimationPlayer.new(animAssets.Jump     or {}, { Speed = 1, Loop = false, FadeInTime = 0.08, FadeOutTime = 0.16 });
        Fall     = AnimationPlayer.new(animAssets.Fall     or {}, { Speed = 1, Loop = true,  FadeInTime = 0.14, FadeOutTime = 0.18 });
        Land     = AnimationPlayer.new(animAssets.Land     or {}, { Speed = 1, Loop = false, FadeInTime = 0.08, FadeOutTime = 0.16 });
        Climb    = AnimationPlayer.new(animAssets.Climb    or {}, { Speed = 1, Loop = true,  FadeInTime = 0.18, FadeOutTime = 0.22 });
    }

    local jointMap, retarget = UniversalJointWriter.BuildJointMap(character)
    local didPrintRigDebug = false
    local didPrintSampleDebug = false

    animPlayers.Idle:Play()

    -- ── State ──────────────────────────────────────────────────────────────
    -- momentum: 0 = walking, 1 = full sprint
    local momentum: number = 0
    local isShiftHeld: boolean = false
    -- "Ground" | "Jump" | "Fall" | "Land" | "Climb"
    local airState: string = "Ground"
    local wasAirborne: boolean = false
    local lastLandTriggerTime: number = -math.huge
    local landBlendTime: number = 0
    local lastYaw: number = getYaw(root.CFrame)
    local turnLean: number = 0
    local smoothedPlanarSpeed: number = 0
    local smoothedWeights = {
        Idle = 0; SlowWalk = 0; Walk = 0; Run = 0;
        Jump = 0; Fall = 0; Land = 0; Climb = 0;
    }
    local locomotionPhase: number = 0

    local function syncLocomotionPhase(phase: number)
        local locomotionNames = { "SlowWalk", "Walk", "Run" }
        for _, name in ipairs(locomotionNames) do
            local aplr = animPlayers[name]
            local asset = aplr and aplr.Asset
            if aplr and asset and asset.GetLength then
                local duration = asset:GetLength()
                if duration and duration > 0 then
                    aplr.Time = phase * duration
                end
            end
        end
    end

    -- ── Input ──────────────────────────────────────────────────────────────
    temp:Register(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if gameProcessed then return end
        if input.KeyCode == SHIFT_KEY then
            isShiftHeld = true
        end
    end))

    temp:Register(UserInputService.InputEnded:Connect(function(input: InputObject, _: boolean)
        if input.KeyCode == SHIFT_KEY then
            isShiftHeld = false
        end
    end))

    -- ── Humanoid state → air state ─────────────────────────────────────────
    temp:Register(humanoid.StateChanged:Connect(function(_old: EnumItem, new: EnumItem)
        local now = os.clock()

        if new == Enum.HumanoidStateType.Jumping then
            wasAirborne = true
            airState = "Jump"
            print("JUMP")
            animPlayers.Jump:Play()

        elseif new == Enum.HumanoidStateType.Freefall then
            wasAirborne = true
            airState = "Fall"
            if not animPlayers.Fall.Playing then
                print("FALL")
                animPlayers.Fall:Play()
            end

        elseif new == Enum.HumanoidStateType.Climbing then
            airState = "Climb"
            wasAirborne = false
            if not animPlayers.Climb.Playing then
                animPlayers.Climb:Play()
            end
        elseif new == Enum.HumanoidStateType.Landed
            or new == Enum.HumanoidStateType.Running
            or new == Enum.HumanoidStateType.RunningNoPhysics then

            local canTriggerLand = wasAirborne
                and not animPlayers.Land.Playing
                and (now - lastLandTriggerTime) >= LAND_RETRIGGER_COOLDOWN

            if canTriggerLand then
                -- trigger a one-shot land animation before returning to ground blend
                airState = "Land"
                wasAirborne = false
                lastLandTriggerTime = now
                landBlendTime = 0
                print("LAND")
                animPlayers.Land:Play()
            elseif airState ~= "Land" then
                airState = "Ground"
                wasAirborne = false
            end
        end
    end))

    -- ── Render loop ────────────────────────────────────────────────────────
    local blendedPose = Pose.new({})

    if not didPrintRigDebug then
        didPrintRigDebug = true
        debugPrintJointMap(jointMap, retarget)
    end

    local _conn = temp:Register(RunService.RenderStepped:Connect(function(deltaTime: number)
        local isMoving: boolean = humanoid.MoveDirection.Magnitude > 0.1
        local vel = root.AssemblyLinearVelocity
        local planarSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
        smoothedPlanarSpeed += (planarSpeed - smoothedPlanarSpeed) * math.clamp(deltaTime * SPEED_SMOOTH_SPEED, 0, 1)
        
        if isMoving then
            local targetCFrame = CFrame.lookAt(root.Position, root.Position + humanoid.MoveDirection)
            root.CFrame = root.CFrame:Lerp(targetCFrame, math.clamp(deltaTime * 10, 0, 1))
        end

        -- ── Turn-rate lean (additive torso bank) ─────────────────────────
        local currentYaw: number = getYaw(root.CFrame)
        local yawDelta: number = deltaAngle(currentYaw, lastYaw)
        local turnRate: number = if deltaTime > 0 then yawDelta / deltaTime else 0
        lastYaw = currentYaw

        local maxLean = math.rad(MAX_TURN_LEAN_DEG)
        local targetLean = 0
        if isMoving then
            local speedAlpha = math.clamp(smoothedPlanarSpeed / MAX_RUN_SPEED, 0, 1)
            local momentumAlpha = if isShiftHeld then 0 else momentum
            local leanScale = math.clamp((MIN_LEAN_SCALE + momentumAlpha) * speedAlpha, 0, 1)
            targetLean = math.clamp(-turnRate * TURN_LEAN_SENSITIVITY * leanScale, -maxLean, maxLean)
        end
        turnLean = turnLean + (targetLean - turnLean) * math.clamp(deltaTime * TURN_LEAN_SMOOTH_SPEED, 0, 1)

        -- ── Momentum ───────────────────────────────────────────────────────
        if not isMoving then
            momentum = 0
        elseif not isShiftHeld and airState == "Ground" then
            momentum = math.min(1, momentum + MOMENTUM_BUILD_RATE * deltaTime)
        else
            momentum = math.max(0, momentum - MOMENTUM_DECAY_RATE * deltaTime)
        end

        -- ── WalkSpeed ──────────────────────────────────────────────────────
        if isShiftHeld then
            humanoid.WalkSpeed = SLOW_WALK_SPEED
        else
            humanoid.WalkSpeed = BASE_WALK_SPEED + (MAX_RUN_SPEED - BASE_WALK_SPEED) * momentum
        end

        -- Keep movement clips phase-locked so blends do not foot-slide/pop.
        local locomotionCycleRate: number = 0
        if isMoving then
            locomotionCycleRate = math.clamp(
                smoothedPlanarSpeed / BASE_WALK_SPEED,
                LOCOMOTION_MIN_CYCLE_RATE,
                LOCOMOTION_MAX_CYCLE_RATE
            )
        end
        locomotionPhase = (locomotionPhase + deltaTime * locomotionCycleRate) % 1
        syncLocomotionPhase(locomotionPhase)

        -- Speeds are externally phase-driven for synced locomotion players.
        animPlayers.SlowWalk.Speed = 0
        animPlayers.Walk.Speed = 0
        animPlayers.Run.Speed = 0
        animPlayers.Climb.Speed = math.clamp(smoothedPlanarSpeed / BASE_WALK_SPEED, 0.8, 1.8)

        if airState == "Land" then
            landBlendTime += deltaTime
        else
            landBlendTime = 0
        end

        -- Land is a short overlay; hand off quickly to locomotion.
        if airState == "Land" and (not animPlayers.Land.Playing or landBlendTime >= LAND_BLEND_DURATION) then
            airState = "Ground"
        end

        -- ── Blend weights ──────────────────────────────────────────────────
        local blendWeights = {
            Idle = 0; SlowWalk = 0; Walk = 0; Run = 0;
            Jump = 0; Fall = 0; Land = 0; Climb = 0;
        }

        if airState == "Jump" then
            if animPlayers.Jump.Playing then
                blendWeights.Jump = 1
            else
                -- jump anim ended before Freefall fired; fall back to Fall
                blendWeights.Fall = 1
                if not animPlayers.Fall.Playing then
                    animPlayers.Fall:Play()
                end
            end

        elseif airState == "Fall" then
            blendWeights.Fall = 1

        elseif airState == "Land" then
            local landProgress = math.clamp(landBlendTime / LAND_BLEND_DURATION, 0, 1)
            local groundAlpha = math.clamp(
                LAND_GROUND_START_ALPHA + (1 - LAND_GROUND_START_ALPHA) * landProgress,
                0,
                1
            )
            local landAlpha = 1 - groundAlpha
            local moveMag: number = math.min(1, humanoid.MoveDirection.Magnitude)

            blendWeights.Land = landAlpha
            if isShiftHeld then
                blendWeights.Idle     = (1 - moveMag) * groundAlpha
                blendWeights.SlowWalk = moveMag * groundAlpha
            else
                blendWeights.Idle = (1 - moveMag) * groundAlpha
                blendWeights.Walk = moveMag * (1 - momentum) * groundAlpha
                blendWeights.Run  = moveMag * momentum * groundAlpha
            end

        elseif airState == "Climb" then
            blendWeights.Climb = 1

        else -- Ground
            local moveMag: number = math.min(1, humanoid.MoveDirection.Magnitude)

            if isShiftHeld then
                -- Shift held: blend Idle ↔ SlowWalk only; momentum decays
                blendWeights.Idle     = 1 - moveMag
                blendWeights.SlowWalk = moveMag
            else
                -- Normal: blend Idle ↔ Walk ↔ Run based on movement + momentum
                --   moveMag 0 → fully Idle
                --   moveMag 1, momentum 0 → fully Walk
                --   moveMag 1, momentum 1 → fully Run
                blendWeights.Idle = 1 - moveMag
                blendWeights.Walk = moveMag * (1 - momentum)
                blendWeights.Run  = moveMag * momentum
            end
        end

        -- Smooth target blend tree weights to avoid abrupt visual pops.
        for name: string, targetW: number in pairs(blendWeights) do
            local currentW: number = smoothedWeights[name] or 0
            smoothedWeights[name] = currentW + (targetW - currentW) * math.clamp(deltaTime * WEIGHT_SMOOTH_SPEED, 0, 1)
        end

        -- ── Sync looping players (auto play/stop) ──────────────────────────
        -- One-shots (Jump, Land) are triggered only by StateChanged, never here
        local loopingNames = { "Idle", "SlowWalk", "Walk", "Run", "Fall", "Climb" }
        for _: number, name: string in ipairs(loopingNames) do
            local aplr = animPlayers[name]
            local w: number = smoothedWeights[name] or 0
            if w == 0 then
                if aplr and aplr.Playing then
                    aplr:Stop(aplr.FadeOutTime)
                end
            elseif aplr and not aplr.Playing then
                aplr:Play()
            end
        end

        -- ── Sample & blend ─────────────────────────────────────────────────
        local blended: { [string]: CFrame } = {}
        local hasBase: { [string]: boolean } = {}
        local sampledTransforms: {[string]: boolean} = {}

        for name: string, aplr in pairs(animPlayers) do
            if aplr.Playing then
                local logicalW: number = smoothedWeights[name] or 0
                local effectiveW: number = if logicalW > 0 then aplr.Weight * logicalW else aplr.Weight
                local sample = aplr:Update(deltaTime)
                if effectiveW > 0 then
                    for joint: string, cf: CFrame in pairs(sample.Transforms) do
                        sampledTransforms[joint] = true
                        if not hasBase[joint] then
                            blended[joint] = cf
                            hasBase[joint] = true
                        else
                            blended[joint] = blended[joint]:Lerp(cf, effectiveW)
                        end
                    end
                end
            end
        end

        if not didPrintSampleDebug and next(sampledTransforms) ~= nil then
            didPrintSampleDebug = true

            local sampledKeys = getSortedKeys(sampledTransforms)
            print("Example2 Debug: first sampled transform count =", #sampledKeys)
            for _, poseName in ipairs(sampledKeys) do
                local resolvedName = retarget[poseName] or retarget[string.lower((poseName:gsub("[%s%p_]", "")))] or poseName
                local resolvedInfo = jointMap[resolvedName]
                if resolvedInfo then
                    print(string.format(
                        "Example2 Debug: sample %s resolved to %s [%s]",
                        poseName,
                        resolvedName,
                        resolvedInfo.Type
                    ))
                else
                    warn(string.format(
                        "Example2 Debug: sample %s did not resolve to a rig joint (resolved lookup = %s)",
                        poseName,
                        tostring(resolvedName)
                    ))
                end
            end

            if next(blended) == nil then
                warn("Example2 Debug: sampled transforms existed, but blended pose is still empty")
            else
                print("Example2 Debug: blended joint count on first sample =", countDictionary(blended))
            end
        end

        if math.abs(turnLean) > 1e-4 then
            local upperLean = CFrame.Angles(0, 0, -turnLean)
            local lowerLean = CFrame.Angles(0, 0, -turnLean * 0.35)

            if blended.UpperTorso then
                blended.UpperTorso = blended.UpperTorso * upperLean
            end
            if blended.Torso then
                blended.Torso = blended.Torso * upperLean
            end
            if blended.LowerTorso then
                blended.LowerTorso = blended.LowerTorso * lowerLean
            end
        end

        blendedPose = Pose.new(blended)
        UniversalJointWriter.ApplyPose(jointMap, retarget, blendedPose.Data)
    end))

    print("Example2 loaded!")
    print("Loaded", countDictionary(animAssets), "animations")
end

function module:Destroy()
    temp:DisconnectAll()
end

return module