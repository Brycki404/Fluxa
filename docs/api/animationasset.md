# AnimationAsset

Module path: `Fluxa.AnimationAsset`

`AnimationAsset` parses a Roblox `KeyframeSequence` into an in-memory animation representation that can be sampled at arbitrary time positions. It is the lowest-level data object in Fluxa — every `AnimationTrack` needs one.

### When to use it

Construct one `AnimationAsset` per `KeyframeSequence` when your controller starts. After that you hand the asset to `AnimationTrack.new` and never touch it directly again, except possibly to call `GetLength` or `GetEventsAt` when you need metadata.

Examples 1, 2, and 3 all follow this pattern: they iterate over a folder of `KeyframeSequence` instances in `ReplicatedStorage` and build an asset dictionary before creating any tracks.

```lua
local animAssets = {}
local animFolder = ReplicatedStorage:FindFirstChild("Example3Animations_R15")
if animFolder then
    for _, anim in ipairs(animFolder:GetChildren()) do
        if anim:IsA("KeyframeSequence") then
            animAssets[anim.Name] = AnimationAsset.new(anim, anim.Name)
        end
    end
end
```

### Types

#### `AnimationKeyframe`

A single keyframe on one joint channel.

| Field | Type | Description |
|-------|------|-------------|
| `Name` | `string` | Joint name |
| `Time` | `number` | Time in seconds |
| `Value` | `CFrame` | Joint transform at this keyframe |

#### `AnimationChannel`

A named joint channel containing an ordered list of keyframes.

| Field | Type | Description |
|-------|------|-------------|
| `Name` | `string` | Joint name |
| `Keyframes` | `{AnimationKeyframe}` | Sorted list of keyframes |

#### `AnimationEvent`

A timeline marker baked from a `KeyframeMarker` in the source `KeyframeSequence`.

| Field | Type | Description |
|-------|------|-------------|
| `Time` | `number` | Time in seconds |
| `Name` | `string` | Marker name |
| `Value` | `string` | Marker value string |

#### `AnimationSample`

The output of a single `Sample` call — joint transforms at a given time position.

| Field | Type | Description |
|-------|------|-------------|
| `Transforms` | `{[string]: CFrame}` | Map of joint name to `CFrame` |

#### `AnimationAssetInstance`

The object returned by `AnimationAsset.new`.

| Field | Type | Description |
|-------|------|-------------|
| `Name` | `string` | Asset name |
| `Duration` | `number` | Total animation duration in seconds |
| `Channels` | `{[string]: {AnimationKeyframe}}` | Per-joint keyframe data |
| `Events` | `{AnimationEvent}` | Timeline markers sorted by time |

### Constructor

#### `AnimationAsset.new(sequence, nameOverride?)`

Parses the given `KeyframeSequence` and returns an `AnimationAssetInstance`.

| Parameter | Type | Description |
|-----------|------|-------------|
| `sequence` | `KeyframeSequence` | The source sequence to parse |
| `nameOverride` | `string?` | Optional name; defaults to `sequence.Name` |

Returns: `AnimationAssetInstance`

The constructor walks the full pose tree of every `Keyframe` in the sequence, collecting per-joint `CFrame` values into sorted channel lists. It also extracts any `KeyframeMarker` instances as `AnimationEvent` entries.

### Methods

#### `asset:Sample(time)`

Samples all channels at the given time and returns an `AnimationSample`.

| Parameter | Type | Description |
|-----------|------|-------------|
| `time` | `number` | Time in seconds to sample |

Returns: `AnimationSample`

Each channel is sampled by linear interpolation between the two nearest keyframes. Before the first keyframe the first value is held; after the last keyframe the last value is held. Sampling does not wrap.

`AnimationTrack.Update` calls this internally every frame. You generally do not call it directly.

#### `asset:GetLength()`

Returns: `number` — the total duration of the animation in seconds.

Used by `AnimationTrack` for phase-sync calculations:

```lua
local duration = asset:GetLength()
if duration and duration > 0 then
    track.Time = phase * duration
end
```

#### `asset:GetEventsAt(time, window?)`

Returns all `AnimationEvent` entries whose `Time` falls within `[time - window, time]`.

| Parameter | Type | Description |
|-----------|------|-------------|
| `time` | `number` | Current playback time |
| `window` | `number?` | Lookback window in seconds (default `0.033`) |

Returns: `{AnimationEvent}`

Use this to fire footstep sounds, particle effects, or gameplay callbacks at the right moment in an animation without hard-coding time values.

### Notes

* `AnimationAsset` is read-only after construction. Nothing in the examples or the controller mutates it.
* Both the modern `Keyframe:GetPoses()` API and the legacy child-scan fallback are handled automatically, so assets work on all Roblox engine versions.
* The parser normalizes and sorts keyframes at construction time, so sampling at runtime is a single linear scan with no allocation.
* There is no built-in caching. If you create two `AnimationAsset` instances from the same `KeyframeSequence`, the sequence is parsed twice.
