# AnimationTrack

Module path: `Fluxa.AnimationTrack`

`AnimationTrack` wraps an `AnimationAsset` with playback state: current time position, fade in/out weight envelopes, playback speed, loop behavior, and lifecycle signals. It is the runtime unit of animation in Fluxa.

When using `FluxaController`, tracks are created and managed internally. When using the raw API (Examples 1 and 2), you create and drive them manually.

### When to use it directly

Use `AnimationTrack` directly when you do not need layers, blend trees, or replication. Examples 1 and 2 both drive tracks manually in a `RenderStepped` loop.

When using `FluxaController`, the controller creates `AnimationTrack` instances for you. You can retrieve a track for direct inspection or signal connections with `controller:GetTrack(name)`.

### Types

#### `AnimationTrackInstance`

The object returned by `AnimationTrack.new`.

**Playback state**

| Field | Type | Description |
|-------|------|-------------|
| `Asset` | `AnimationAssetInstance` | The underlying animation data |
| `Animation` | `AnimationAssetInstance` | Alias for `Asset` (Roblox compatibility) |
| `Length` | `number` | Asset duration in seconds |
| `Time` | `number` | Current playback time |
| `TimePosition` | `number` | Alias for `Time` (Roblox compatibility) |
| `Speed` | `number` | Playback speed multiplier |
| `Looped` | `boolean` | Whether the track loops |
| `IsPlaying` | `boolean` | True while the track is active |
| `Weight` | `number` | Current blend weight (smoothed by fade envelopes) |
| `FadeInTime` | `number` | Fade-in duration in seconds |
| `FadeOutTime` | `number` | Fade-out duration in seconds |

**Signals**

| Field | Type | Description |
|-------|------|-------------|
| `Stopped` | `Signal` | Fires when `Stop()` is called or natural fade-out begins |
| `Ended` | `Signal` | Fires when the track's weight reaches zero after fade |
| `DidLoop` | `Signal` | Fires once each time the track completes a full loop cycle |
| `KeyframeReached` | `Signal` | Fires with `(markerName)` each time a `KeyframeMarker` time is crossed |

### Constructor

#### `AnimationTrack.new(asset, config?)`

Creates a new `AnimationTrackInstance`.

| Parameter | Type | Description |
|-----------|------|-------------|
| `asset` | `AnimationAssetInstance` | The asset to play |
| `config` | `table?` | Optional initial settings |

`config` may include:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `Speed` | `number` | `1` | Playback speed multiplier |
| `Looped` | `boolean` | `true` | Whether the track loops |
| `FadeInTime` | `number` | `0.2` | Default fade-in duration |
| `FadeOutTime` | `number` | `0.2` | Default fade-out duration |
| `Weight` | `number` | `1` | Initial target weight |

Returns: `AnimationTrackInstance`

### Methods

#### `track:Play(fadeInTime?, weight?, speed?)`

Starts playback. Resets `Time` to `0` and sets `IsPlaying` to `true`.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `fadeInTime` | `number?` | `self.FadeInTime` | Fade-in duration in seconds |
| `weight` | `number?` | `1` | Target weight, clamped to `[0, 1]` |
| `speed` | `number?` | `self.Speed` | Playback speed override |

Calling `Play` while the track is already playing restarts it from the beginning. The `Stopped` and `Ended` guard flags are reset so signals fire again on the next natural completion.

#### `track:Stop(fadeOutTime?)`

Stops playback and begins the fade-out envelope.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `fadeOutTime` | `number?` | `0` | Fade-out duration in seconds |

If the track is not playing and its weight is already at or below zero, `Stop` returns immediately without firing signals.

`Stopped` fires synchronously in `Stop()`. `Ended` fires once weight reaches zero — either immediately (if `fadeOutTime` is `0`) or at the end of the next `Update` call that drives weight to zero.

#### `track:Update(dt)`

Advances the track by `dt` seconds and returns the sampled `AnimationSample`.

| Parameter | Type | Description |
|-----------|------|-------------|
| `dt` | `number` | Delta time in seconds |

Returns: `AnimationSample` — joint transforms at the current time position.

Also fires:
* `DidLoop` each time the time position wraps on a looping track
* `KeyframeReached` and per-marker signals for any `AnimationEvent` whose time falls in the `(previousTime, currentTime]` window
* `Stopped` and `Ended` on natural non-looping completion

When using `FluxaController`, `Update` is called internally by `controller:Step`. When using the raw API, you call `Update` yourself in `RunService.RenderStepped`.

#### `track:AdjustSpeed(speed)`

Sets `self.Speed` without restarting playback.

| Parameter | Type | Description |
|-----------|------|-------------|
| `speed` | `number` | New speed multiplier |

Useful for phase-syncing locomotion clips to character movement speed without calling `Stop` and `Play`.

#### `track:GetMarkerReachedSignal(markerName)`

Returns a per-marker signal that fires whenever the track crosses the named `KeyframeMarker`.

| Parameter | Type | Description |
|-----------|------|-------------|
| `markerName` | `string` | Name of the `KeyframeMarker` in the source `KeyframeSequence` |

Returns: `Signal`

The signal fires in the same update pass as `KeyframeReached`. If no marker with this name exists in the asset, the signal is still created and returned — it will simply never fire.

```lua
track:GetMarkerReachedSignal("LeftFootDown"):Connect(function()
    playFootstepSound("Left")
end)
```

#### `track:GetTimeOfKeyframe(keyframeName)`

Returns the time position of the first `AnimationEvent` whose `Name` matches `keyframeName`.

| Parameter | Type | Description |
|-----------|------|-------------|
| `keyframeName` | `string` | Name to search for |

Returns: `number` — the time in seconds, or `0` if no match is found.

Throws an error if the asset has no keyframes/events, or if no keyframe matches `keyframeName`.

#### `track:Destroy()`

Stops the track and disconnects all signals.

Call this when you are done with a track and want to release signal connections. `FluxaController` calls this automatically when you remove a track.

### Signals in detail

#### Signal lifecycle

```
Play() called          Stop() called or animation naturally reaches end
     │                          │
     ▼                          ▼
  IsPlaying = true          Stopped fires
  Weight ramps up           Weight ramps down (FadeOutTime)
                                 │
                           weight reaches 0
                                 │
                                 ▼
                             Ended fires
```

* `Stopped` fires at the moment fade-out begins — the track is still potentially contributing weight until `Ended` fires.
* `Ended` fires when the track weight has reached zero and the clip is fully blended out.
* Both guard flags reset on the next `Play()` call, so they fire again on subsequent play/stop cycles.

#### DidLoop

`DidLoop` fires once per full cycle. If a looping track has `Length = 1.2` and runs for 3 seconds, `DidLoop` fires twice (at 1.2 s and 2.4 s). It does not fire on the initial play or on stop.

```lua
track.DidLoop:Connect(function()
    syncPhaseToOtherTracks()
end)
```

#### KeyframeReached and per-marker signals

`KeyframeReached` fires with the marker name as its argument. Use it for generic listening without knowing marker names in advance:

```lua
track.KeyframeReached:Connect(function(markerName)
    print("Crossed marker:", markerName)
end)
```

Use `GetMarkerReachedSignal` when you know the exact marker name:

```lua
track:GetMarkerReachedSignal("Impact"):Connect(function()
    dealMeleeDamage()
end)
```

### Phase-driven locomotion

A common pattern in Examples 2 and 3 is to decouple `Speed` from time advancement and instead set `Time` directly from a shared locomotion phase accumulator. This keeps slow-walk, walk, and run clips synchronized regardless of their natural playback speeds:

```lua
-- Advance phase accumulator
local speed = humanoidRootPart.AssemblyLinearVelocity.Magnitude
local normalizedRate = math.clamp(speed / BASE_WALK_SPEED, MIN_CYCLE_RATE, MAX_CYCLE_RATE)
locomotionPhase = (locomotionPhase + normalizedRate * dt) % 1

-- Drive track time positions directly
for _, track in { slowWalkTrack, walkTrack, runTrack } do
    track.Speed = 0
    local len = track.Asset:GetLength()
    if len and len > 0 then
        track.Time = locomotionPhase * len
    end
end
```

### Weight behavior

`Weight` starts at `0` when a track is constructed. Calling `Play(fadeInTime)` ramps it toward the target weight (`_PlayTargetWeight`) over `fadeInTime` seconds. Calling `Stop(fadeOutTime)` ramps it back to `0` over `fadeOutTime` seconds.

While weight is ramping, `IsPlaying` remains `true`. `IsPlaying` only becomes `false` after the weight has fully reached zero and `Ended` has fired.

> In the raw API pattern (Examples 1 and 2), `Weight` must be read back each frame to build a weighted blend. In `FluxaController`, blend weights are computed by the layer's blend tree and applied automatically.
