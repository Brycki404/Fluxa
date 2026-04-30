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
| `BindingId` | `string?` | `asset.Name` or track name | Stable replicated binding identifier for this track |
| `TrackOptions` | `{[string]: any}?` | `nil` | Options passed directly to `AnimationTrack.new` |
| `Layer` | `string` | `"Base"` | Layer this track belongs to |
| `AutoManage` | `boolean` | `true` | Controller auto-plays/stops based on weight |
| `AutoReplicate` | `boolean` | `false` | If true, starting this track auto-emits replication start markers |
| `InitialWeight` | `number` | `0` | Initial target weight for this track |
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
| `TrackBindingResolver` | `function?` | Resolves replicated `BindingId` values into local assets |
| `AutoStart` | `boolean?` | Starts the internal step loop immediately |
| `WeightSmoothingSpeed` | `number?` | Smoothing speed for weight interpolation |
| `ReplicationSeekMode` | `"Always"\|"LoopingOnly"\|"Never"?` | Default seek mode for tracks that do not override it |
| `Drivers` / `Params` | `{[string]: any}?` | Initial global drivers (`Params` is legacy alias) |
| `GlobalDriverReplication` | `{[string]: boolean}?` | Up-front per-global-driver replication flags |
| `LayerDriverReplication` | `{[string]: {[string]: boolean}}?` | Up-front per-layer-driver replication flags |
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
        Idle = { Asset = assets.Idle, Layer = "Base", TrackOptions = { Looped = true } },
        Land = { Asset = assets.Land, Layer = "Landing", AutoReplicate = true, ReplicationSeekMode = "Never", TrackOptions = { Looped = true }},
    },
    GlobalDriverReplication = {
        Speed = true,
        DebugOnly = false,
    },
    LayerDriverReplication = {
        Base = {
            MoveDir = true,
            LocalLean = false,
        },
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

#### `controller:SetLayerDriverReplication(layerName, key, enabled)` / `controller:GetLayerDriverReplication(layerName, key)`

Enables or disables replication per layer driver.

Defaults to `true` (replicate) unless explicitly set to `false`.

#### `controller:MarkLayerAnimationStart(layerName, trackName)`

Manually marks the start of an animation in a layer for replication.

Use this for manual or one-off triggers. For per-track automatic behavior, prefer `TrackConfig.AutoReplicate = true` (or `SetTrackAutoReplicate`).

### Track methods

#### `controller:LoadTrack(name, asset, config?)`

Loads (or hot-swaps) a named track at runtime.

If a track already exists under this name, Fluxa unloads and destroys the old track first, then binds the new track under the same name. This keeps blend trees unchanged while animation assets swap underneath.

#### `controller:SetTrackAsset(name, asset, options?)`

Swaps the asset underneath an existing track name with an explicit phase policy.

Options:

* `PreservePhase` or `preservePhase` - when `true`, Fluxa preserves the old track's normalized phase on the new asset
* `BindingId` - override the binding id stored for replication
* `TrackOptions` - optional track options for the new track instance

Use this when swap behavior must be explicit instead of inferred:

* locomotion swaps usually use `PreservePhase = true`
* one-shot swaps usually use `PreservePhase = false`

#### `controller:UnloadTrack(name)`

Removes a track by name and stops it if currently playing.

Also destroys the underlying track instance for memory safety.

#### `controller:SetTrackBindingResolver(resolverFn)`

Sets a resolver used by replication to map `BindingId` values to local assets.

Signature:

```lua
resolverFn = function(controller, trackName, bindingId, previousBindingId)
    return resolvedAsset, optionalTrackConfig
end
```

Return `nil` as `resolvedAsset` to unload that track when the replicated binding changes.

#### `controller:GetTrackBinding(trackName)`

Returns the current replicated binding id for a track name, or `nil` if the track is not loaded.

#### `controller:GetTrackBindings()`

Returns a cloned map of all active track bindings (`trackName -> bindingId`).

#### `controller:SetTrackLayer(trackName, layerName)`

Reassigns a track to a different layer.

#### `controller:SetTrackAutoReplicate(trackName, enabled)` / `controller:GetTrackAutoReplicate(trackName)`

Enables or disables automatic animation-start replication for a track.

When enabled, any start through `Play(...)` or `AutoManage` start automatically records a replication start marker.

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

#### `controller:Play(trackName, fadeInTime?, weight?, speed?)`

Plays a named track with an optional fade-in time. Resets the track's time position to `0`.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `trackName` | `string` | required | Track name |
| `fadeInTime` | `number?` | track default | Fade-in duration in seconds |
| `weight` | `number?` | `1` | Target play weight, clamped to `[0, 1]` |
| `speed` | `number?` | current track speed | Playback speed override |

#### `controller:Stop(trackName, fadeOutTime?)`

Stops a named track with an optional fade-out time.

#### `controller:StopAll(fadeOutTime?)`

Stops all registered tracks.

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

#### `controller:SetGlobalDriverReplication(key, enabled)` / `controller:GetGlobalDriverReplication(key)`

Enables or disables replication per global driver.

Defaults to `true` (replicate) unless explicitly set to `false`.

### Lifecycle methods

#### `controller:Step(dt)`

Advances the controller by `dt` seconds. Runs `OnPreStep`, resolves blend tree weights, updates all active tracks, blends the final pose, and writes it to the character (if `AutoApplyPose` is `true`).

Call this manually in `RunService.RenderStepped` when not using `:Start()`.


#### `controller:Start()`

**No-op.** Stepping is now managed globally by `FluxaService` on the client. Register your controller with `FluxaService.RegisterController` and it will be stepped automatically.

#### `controller:StopLoop()`

**No-op.** Stepping is now managed globally by `FluxaService`.

#### `controller:Destroy()`

Stops all tracks, disconnects all signals and connections, and cleans up the controller.

### Replication methods

#### `controller:GetReplicationPacket()`

Returns a serializable table representing replication state.

Includes:

* Track bindings (`trackName -> bindingId`)
* Global drivers filtered by `GlobalDriverReplication`
* Layer drivers filtered by `LayerDriverReplication`
* Recent animation-start markers for each layer

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
* `AutoManage = true` tracks are played and stopped automatically when their blend-tree-computed weight becomes nonzero or returns to zero. `AutoManage = false` tracks are only played or stopped via explicit `:Play` and `:Stop` calls.
* Driver replication is opt-out per driver (default `true`) and can be configured up front with `GlobalDriverReplication` and `LayerDriverReplication`.
* Track start replication is opt-in per track (`AutoReplicate = true`) or manual through `MarkLayerAnimationStart`.
* `FluxaController` creates one `UniversalJointWriter.BuildJointMap` per controller. If the character's joint hierarchy changes after construction (unlikely at runtime), you may need to recreate the controller.
