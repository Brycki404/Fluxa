# Retargeting

Module path: `Fluxa.Retargeting`

Utilities for remapping pose joint names and scaling positional data when retargeting between rigs.

## Methods

#### `Retargeting.MapPose(pose, map, options?)`

Remaps a pose from source joint names to target joint names.

| Parameter | Type | Description |
|-----------|------|-------------|
| `pose` | `{[string]: CFrame}` | Source pose keyed by source-joint names |
| `map` | `{[string]: string}` | Source joint name -> target joint name |
| `options` | `{ Scale: number }?` | Optional retarget options |

Returns: `{[string]: CFrame}`

Behavior:

* Only mapped joints are included in the returned pose.
* Position is multiplied by `options.Scale` (default `1`).
* Rotation is preserved from the source transform.

```lua
local mapped = Fluxa.Retargeting.MapPose(sourcePose, {
	Torso = "UpperTorso",
	LeftArm = "LeftUpperArm",
}, { Scale = 1.1 })
```