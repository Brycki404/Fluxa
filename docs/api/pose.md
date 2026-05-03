# Pose

Module path: `Fluxa.Pose`

Represents a joint transform dictionary and provides pose math utilities.

## Constructor

#### `Pose.new(data?)`

Creates a new pose wrapper around a transform dictionary.

| Parameter | Type | Description |
|-----------|------|-------------|
| `data` | `{[string]: CFrame}?` | Optional initial pose data |

Returns: `PoseInstance`

```lua
local pose = Fluxa.Pose.new({
	Head = CFrame.new(0, 1, 0),
})
```

## Methods

#### `pose:Clone()`

Clones the pose data and returns a new `PoseInstance`.

Returns: `PoseInstance`

#### `pose:Lerp(other, alpha)`

Interpolates this pose toward `other` by `alpha`.

| Parameter | Type | Description |
|-----------|------|-------------|
| `other` | `PoseInstance` | Target pose |
| `alpha` | `number` | Blend factor in `[0, 1]` |

Returns: `PoseInstance`

Notes:

* The implementation first lerps matching joints.
* It then copies all joints from `other` into the result.
* In practice, any joint present in `other` ends with `other`'s transform.

#### `pose:Additive(addPose, weight)`

Applies additive positional displacement from `addPose` scaled by `weight`.

| Parameter | Type | Description |
|-----------|------|-------------|
| `addPose` | `PoseInstance` | Pose providing additive displacement |
| `weight` | `number` | Additive blend strength |

Returns: `PoseInstance`

#### `pose:ApplyMask(mask)`

Filters this pose to only joints whose key is `true` in `mask`.

| Parameter | Type | Description |
|-----------|------|-------------|
| `mask` | `{[string]: boolean}` | Joint include map |

Returns: `PoseInstance`