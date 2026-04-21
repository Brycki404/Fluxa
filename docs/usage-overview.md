# Usage Overview

## Key Concepts

* `AnimationAsset` converts `KeyframeSequence` data into fast sampled pose data.
* `Pose` is a dictionary of joint names to `CFrame` transforms.
* `AnimationTrack` drives an `AnimationAsset` in time with looping, speed, fade envelopes, and signal events.
* `BlendTree` defines code-driven animation blends.
* `UniversalJointWriter` writes the final pose into a character via `Motor6D.Transform`, `AnimationConstraint.Transform`, or `Bone.Transform`.

The following API found in this documentation is grouped by ModuleScript.

## Module Map

| Module | Path | Purpose |
|--------|------|---------|
| `AnimationAsset` | `Fluxa.AnimationAsset` | Parse a `KeyframeSequence` into samplable clip data |
| `AnimationTrack` | `Fluxa.AnimationTrack` | Playback state, fade weight, speed, loop, and signals |
| `BlendTree` | `Fluxa.BlendTree` | Blend tree node helpers |
| `Pose` | `Fluxa.Pose` | Pose blending utilities |
| `Retargeting` | `Fluxa.Retargeting` | Joint name remapping between rigs |
| `UniversalJointWriter` | `Fluxa.UniversalJointWriter` | Write a pose to a character's joints |
| `FluxaController` | `Fluxa.FluxaController` | Full animation graph with tracks, layers, blend trees, and replication |
| `FluxaReplicationService` | `Fluxa.FluxaReplicationService` | Cross-client animation state replication |
| `IK.CCD` | `Fluxa.IK.CCD` | Cyclic Coordinate Descent IK solver |
| `IK.FABRIK` | `Fluxa.IK.FABRIK` | FABRIK IK solver |
| `IK.FootPlanting` | `Fluxa.IK.FootPlanting` | Foot planting IK |
| `IK.LookAt` | `Fluxa.IK.LookAt` | Look-at IK solver |
| `IK.TwoBoneIK` | `Fluxa.IK.TwoBoneIK` | Two-bone IK solver |

## Layer Stack

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

## Notes

Fluxa is actively developed, so the public API may change. The docs here are intended to capture the current runtime system and provide a starting point for developers.

## Replication Controls

FluxaController exposes fine-grained replication controls:

* Per-track animation-start replication via `TrackConfig.AutoReplicate` or `SetTrackAutoReplicate(...)`.
* Per-global-driver replication via `SetGlobalDriverReplication(...)`.
* Per-layer-driver replication via `SetLayerDriverReplication(...)`.
* Constructor defaults via `GlobalDriverReplication` and `LayerDriverReplication` in `FluxaController.new(...)`.

Use these controls to keep important gameplay animation state synchronized while preserving local-only driver data when needed.
