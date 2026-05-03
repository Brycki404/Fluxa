# UniversalJointWriter

Module path: `Fluxa.UniversalJointWriter`

Builds canonical joint mappings for a rig and applies pose data to `Motor6D`, `Bone`, and `AnimationConstraint` joints.

## Methods

#### `UniversalJointWriter.BuildJointMap(root)`

Scans a model and builds both a canonical joint map and a retarget alias map.

| Parameter | Type | Description |
|-----------|------|-------------|
| `root` | `Model` | Rig model to scan |

Returns: `(jointMap, retargetMap)`

* `jointMap`: `{[string]: JointInfo}`
* `retargetMap`: `{[string]: string}`

The retarget map includes normalized aliases (case and punctuation-insensitive), letting pose channels authored with alternate names resolve to canonical rig joints.

#### `UniversalJointWriter.ApplyPose(jointMap, retarget, pose)`

Writes pose transforms into rig joints using alias-aware retargeting.

| Parameter | Type | Description |
|-----------|------|-------------|
| `jointMap` | `{[string]: JointInfo}` | Built from `BuildJointMap` |
| `retarget` | `{[string]: string}` | Alias -> canonical map |
| `pose` | `{[string]: CFrame}` | Pose transforms keyed by animation channel name |

For each pose key, Fluxa tries:

1. Exact alias lookup
2. Normalized alias lookup
3. Raw name fallback

When a canonical joint is resolved, transform is applied to:

* `Motor6D.Transform`
* `AnimationConstraint.Transform`
* `Bone.Transform`

```lua
local jointMap, retarget = Fluxa.UniversalJointWriter.BuildJointMap(character)
local sample = track:Update(dt)
Fluxa.UniversalJointWriter.ApplyPose(jointMap, retarget, sample.Transforms)
```