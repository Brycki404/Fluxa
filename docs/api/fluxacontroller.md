# FluxaController

Module path: `Fluxa.FluxaController`

`FluxaController` is the central animation graph. It owns all tracks, layers, blend trees, and drivers for a single character. Each frame you call `controller:Step(dt)` and it handles weight calculation, pose blending, and writing results to the character's joints.

Use `FluxaController` when you need layers, blend trees, or replication. For raw API usage without these features see [Examples 1 and 2](../examples/README.md).

### When to use it

* You need upper-body / lower-body masking via layers.
* You want blend trees to own weight math instead of computing it yourself.
* You want replication via `FluxaReplicationService`.
* You want to cleanly separate animation logic from game logic via drivers.

### Types

#### `TrackConfig`

Passed as values in the `Tracks` table when constructing a controller.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Asset` | `AnimationAssetInstance` | required | Animation asset |
| `Layer` | `string` | `"Base"` | Layer this track belongs to |
| `Looped` | `boolean` | `true` | If false, plays once and stops |
| `AutoManage` | `boolean` | `true` | Controller auto-plays/stops based on weight |
| `FadeInTime` | `number` | `0` | Default fade-in duration |
| `FadeOutTime` | `number` | `0` | Default fade-out duration |
| `Speed` | `number` | `1` | Playback speed |
| `Loop` | `boolean` | `true` | Whether the clip loops |
| `ReplicationSeekMode` | `string?` | `nil` | `"Always"`, `"LoopingOnly"`, or `"Never"` |

#### `LayerConfig`

Passed as values in the `Layers` table when constructing a controller.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Weight` | `number` | `1` | Initial layer weight |
| `Order` | `number` | `0` | Blend order (lower = base, higher = overlay) |
| `BlendMode` | `string?` | `nil` | `"Override"` (default) or `"Additive"` |
| `Mask` | `{[string]: boolean}?` | `nil` | Joint mask for this layer |

#### `ControllerConfig`

Passed to `FluxaController.new`.

| Field | Type | Description |
|-------|------|-------------|
| `Character` | `Model` | Roblox character model |
| `Layers` | `{[string]: LayerConfig}` | Named layer definitions |
| `Tracks` | `{[string]: TrackConfig}` | Named track definitions |
| `BlendTrees` | `{[string]: BlendTreeFn}?` | Named blend tree functions |
| `OnPreStep` | `function?` | Called before blend resolution each frame |
| `OnPostBlend` | `function?` | Called after blend, before joint write |
| `AutoApplyPose` | `boolean?` | Auto-write pose each step (default `true`) |

### Constructor

#### `FluxaController.new(config)`

Creates a new controller with the given configuration.

Returns: `ControllerInstance`

Immediately builds the internal track and layer state. Does not start the step loop. Call `:Start()` to begin auto-stepping or call `:Step(dt)` manually.

```lua
local controller = FluxaController.new({
    Character = character,
    Layers = {
        Base    = { Weight = 1, Order = 0 },
        Landing = { Weight = 0, Order = 1 },
    },
    Tracks = {
        Idle = { Asset = assets.Idle, Layer = "Base", Loop = true },
        Land = { Asset = assets.Land, Layer = "Landing", Looped = false, ReplicationSeekMode = "Never" },
    },
})
controller:Start()
```

### Layer methods

#### `controller:AddLayer(name, config)`

Adds a new layer at runtime.

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `string` | Unique layer name |
| `config` | `LayerConfig` | Layer configuration |

#### `controller:RemoveLayer(name)`

Removes a layer and all tracks assigned to it.

#### `controller:SetLayerWeight(name, weight)`

Sets the target blend weight for a layer.

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `string` | Layer name |
| `weight` | `number` | Weight in `[0, 1]` |

#### `controller:SetLayerBlendMode(name, mode)`

Sets a layer's blend mode.

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `string` | Layer name |
| `mode` | `string` | `"Override"` or `"Additive"` |

#### `controller:SetLayerMask(name, mask)`

Assigns a joint mask to a layer.

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `string` | Layer name |
| `mask` | `{[string]: boolean}` | Map of joint names to include (`true`) or exclude (`false`) |

#### `controller:SetLayerDriver(name, key, value)` / `controller:GetLayerDriver(name, key)`

Sets or reads a named driver value on a layer. Blend tree functions read driver values to compute track weights.

```lua
controller:SetLayerDriver("Base", "Speed", humanoidRootPart.AssemblyLinearVelocity.Magnitude)
```

#### `controller:MarkLayerAnimationStart(layerName, trackName)`

Marks the start of a non-looped animation in a layer. Used to synchronize Landing-style overlay layers with the underlying timing.

### Track methods

#### `controller:AddTrack(name, config)`

Adds a new track at runtime.

#### `controller:RemoveTrack(name)`

Removes a track by name and destroys the underlying `AnimationTrack`.

#### `controller:SetTrackLayer(trackName, layerName)`

Reassigns a track to a different layer.

#### `controller:SetTrackWeight(trackName, weight)` / `controller:GetTrackWeight(trackName)`

Manually sets or reads the current weight of a track. Manual weight assignment bypasses the layer's blend tree for that track.

#### `controller:GetTrack(name)`

Returns the underlying `AnimationTrackInstance` for a named track, or `nil` if the track is not registered.

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `string` | Track name as registered in `Tracks` config |

Returns: `AnimationTrackInstance?`

Use this to connect to track signals or inspect playback state:

```lua
local jumpTrack = controller:GetTrack("Jump")
if jumpTrack then
    jumpTrack.Ended:Connect(function()
        print("Jump animation finished")
    end)
end
```

#### `controller:GetPlayingTracks()`

Returns all tracks whose `Weight` is greater than zero. This includes tracks that are fading in, at full weight, or fading out.

Returns: `{ AnimationTrackInstance }`

Tracks are returned in registration order (the order they were added to the controller).

```lua
local playing = controller:GetPlayingTracks()
for _, track in ipairs(playing) do
    print(track.Asset.Name, track.Weight)
end
```

### Playback methods

#### `controller:Play(trackName, fadeInTime?)`

Plays a named track with an optional fade-in time. Resets the track's time position to `0`.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `trackName` | `string` | required | Track name |
| `fadeInTime` | `number?` | track default | Fade-in duration in seconds |

#### `controller:StopTrack(trackName, fadeOutTime?)`

Stops a named track with an optional fade-out time.

#### `controller:Stop(trackName?)`

Stops a specific track by name, or stops all tracks if no name is provided.

### Blend tree methods

#### `controller:CreateBlendTree(name, fn)`

Registers a blend tree function under a name.

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `string` | Blend tree name |
| `fn` | `(ctrl, dt) -> {[string]: number}` | Function returning per-track weight targets |

#### `controller:RemoveBlendTree(name)`

Removes a registered blend tree.

### Driver methods

#### `controller:SetGlobalDriver(key, value)` / `controller:GetGlobalDriver(key)`

Sets or reads a global driver value accessible from all blend tree functions.

```lua
controller:SetGlobalDriver("AimPitch", camera.CFrame.LookVector.Y)
```

### Lifecycle methods

#### `controller:Step(dt)`

Advances the controller by `dt` seconds. Runs `OnPreStep`, resolves blend tree weights, updates all active tracks, blends the final pose, and writes it to the character (if `AutoApplyPose` is `true`).

Call this manually in `RunService.RenderStepped` when not using `:Start()`.

#### `controller:Start()`

Starts the internal `RenderStepped` loop, calling `:Step(dt)` automatically each frame.

#### `controller:StopLoop()`

Stops the internal `RenderStepped` loop. Does not affect playing tracks.

#### `controller:Destroy()`

Stops all tracks, disconnects all signals and connections, and cleans up the controller.

### Replication methods

#### `controller:GetReplicationPacket()`

Returns a serializable table representing the current layer and track state. Used by `FluxaReplicationService` to send state to remote clients.

Returns: `table`

#### `controller:ApplyReplicationPacket(packet)`

Applies a replication packet received from another client. Used by `FluxaReplicationService` on remote controllers.

| Parameter | Type | Description |
|-----------|------|-------------|
| `packet` | `table` | Packet from `GetReplicationPacket()` |

### OnPostBlend callback

If you provide an `OnPostBlend` function in the constructor config, it is called each frame after the pose is fully blended but before it is written to the character. Use it to apply procedural overrides:

```lua
OnPostBlend = function(ctrl, pose, dt)
    -- Apply IK foot placement to the blended pose before writing
    FootPlanting.Apply(pose, character)
end
```

### Notes

* Tracks assigned to non-existent layers are silently dropped. Always define layers before registering tracks that reference them.
* Blend tree functions are resolved in layer order (by `Order` value, ascending). Lower-order layers blend first.
* Non-looped tracks (`Looped = false`) stop automatically after playing once. Their weight fades out at the track's `FadeOutTime`.
* `AutoManage = true` tracks are played and stopped automatically when their blend-tree-computed weight becomes nonzero or returns to zero. `AutoManage = false` tracks are only played or stopped via explicit `:Play` and `:StopTrack` calls.
* `FluxaController` creates one `UniversalJointWriter.BuildJointMap` per controller. If the character's joint hierarchy changes after construction (unlikely at runtime), you may need to recreate the controller.
