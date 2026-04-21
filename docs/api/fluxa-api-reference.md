# Fluxa API Reference

### Notes

Fluxa is actively developed, so the public API may change. The docs here are intended to capture the current runtime system and provide a starting point for developers.

All modules are accessible through the top-level package:

```lua
local Fluxa = require(ReplicatedStorage.Packages.fluxa)
```

### Module Overview

| Module | Path | Purpose |
|--------|------|---------|
| `AnimationAsset` | `Fluxa.AnimationAsset` | Parse a `KeyframeSequence` into samplable clip data |
| `AnimationTrack` | `Fluxa.AnimationTrack` | Playback state, fade weight, speed, loop, and signals |
| `BlendTree` | `Fluxa.BlendTree` | Blend tree node helpers |
| `Pose` | `Fluxa.Pose` | Pose blending utilities |
| `Retargeting` | `Fluxa.Retargeting` | Joint name remapping between rigs |
| `UniversalJointWriter` | `Fluxa.UniversalJointWriter` | Write a pose to a character's joints |
| `FluxaController` | `Fluxa.FluxaController` | Full animation graph: tracks, layers, blend trees, replication |
| `FluxaReplicationService` | `Fluxa.FluxaReplicationService` | Cross-client animation state replication |

### Layer stack

```
AnimationAsset   ← raw keyframe data, parsed once
     │
AnimationTrack   ← playback state, fade weight, phase, events
     │
FluxaController  ← owns all tracks, blend trees, layers
     │            blends them into a PoseData each frame
UniversalJointWriter ← writes PoseData to rig Motor6Ds / Bones / AnimationConstraints
```

`FluxaReplicationService` sits alongside this stack, serializing the controller's layer state and routing it to remote controllers on other clients.

### Which modules each example uses

| Module | Example 1 | Example 2 | Example 3 |
|--------|-----------|-----------|-----------|
| `AnimationAsset` | ✓ | ✓ | ✓ |
| `AnimationTrack` | ✓ | ✓ | via controller |
| `Pose` | ✓ | ✓ | via controller |
| `UniversalJointWriter` | ✓ | ✓ | via controller |
| `FluxaController` | — | — | ✓ |
| `FluxaReplicationService` | — | — | ✓ |

### Quick start: local-only controller (Example 3 pattern)

```lua
local Fluxa = require(ReplicatedStorage.Packages.fluxa)
local AnimationAsset = Fluxa.AnimationAsset
local FluxaController = Fluxa.FluxaController

-- 1. Build assets from a folder of KeyframeSequences
local assets = {}
for _, seq in ipairs(animFolder:GetChildren()) do
    if seq:IsA("KeyframeSequence") then
        assets[seq.Name] = AnimationAsset.new(seq, seq.Name)
    end
end

-- 2. Destroy Roblox's default Animator
local animator = humanoid:FindFirstChildOfClass("Animator")
if animator then animator:Destroy() end

-- 3. Create controller
local controller = FluxaController.new({
    Character = character,
    AutoApplyPose = true,
    Layers = {
        Base    = { Weight = 1, Order = 0 },
        Landing = { Weight = 0, Order = 1 },
    },
    Tracks = {
        Idle  = { Asset = assets.Idle,  Layer = "Base",    AutoManage = true,  Looped = true },
        Walk  = { Asset = assets.Walk,  Layer = "Base",    AutoManage = true,  Looped = true },
        Run   = { Asset = assets.Run,   Layer = "Base",    AutoManage = true,  Looped = true },
        Land  = { Asset = assets.Land,  Layer = "Landing", AutoManage = false, Looped = false, ReplicationSeekMode = "Never" },
    },
    BlendTrees = {
        Locomotion = function(ctrl, dt)
            local speed = ctrl.Layers.Base.Drivers.Speed or 0
            local move  = ctrl.Layers.Base.Drivers.MoveDir or 0
            return {
                Idle = 1 - move,
                Walk = move * math.clamp(1 - speed / 10, 0, 1),
                Run  = move * math.clamp((speed - 5) / 15, 0, 1),
            }
        end,
    },
    OnPreStep = function(ctrl, dt)
        local speed = humanoid.RootPart and humanoid.RootPart.AssemblyLinearVelocity.Magnitude or 0
        ctrl:SetLayerDriver("Base", "Speed", speed)
        ctrl:SetLayerDriver("Base", "MoveDir", humanoid.MoveDirection.Magnitude > 0.1 and 1 or 0)
    end,
})

controller:Start()

-- 4. Trigger Land on state change
humanoid.StateChanged:Connect(function(_old, new)
    if new == Enum.HumanoidStateType.Landed then
        controller:Play("Land")
        controller:MarkLayerAnimationStart("Landing", "Land")
    end
end)
```

### Quick start: raw API (Example 1/2 pattern)

```lua
local AnimationAsset = Fluxa.AnimationAsset
local AnimationTrack = Fluxa.AnimationTrack
local Pose = Fluxa.Pose
local UniversalJointWriter = Fluxa.UniversalJointWriter

local asset = AnimationAsset.new(keyframeSequence, "Walk")
local track  = AnimationTrack.new(asset, { Speed = 1, Loop = true })
local jointMap, retarget = UniversalJointWriter.BuildJointMap(character)

track:Play()

-- Listen for events
track.Stopped:Connect(function()
    print("Walk stopped")
end)

RunService.RenderStepped:Connect(function(dt)
    local sample = track:Update(dt)
    UniversalJointWriter.ApplyPose(jointMap, retarget, sample.Transforms)
end)
```

### Adding replication (Example 3 pattern)

```lua
local FluxaReplicationService = Fluxa.FluxaReplicationService

-- After creating local controller:
FluxaReplicationService.SetLocalReplicationEnabled(true)
FluxaReplicationService.StartLocalReplication(localController)

-- For each remote player (and on PlayerAdded):
local remoteController = createControllerForCharacter(player.Character, assets, false)
FluxaReplicationService.StartRemoteReplication(remoteController, player)

-- Cleanup on PlayerRemoving:
Players.PlayerRemoving:Connect(function(player)
    local rc = remoteControllers[player]
    if rc then
        rc:Destroy()
        remoteControllers[player] = nil
    end
end)
```
