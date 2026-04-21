# Example 1

[Video clip](https://medal.tv/games/roblox-studio/clips/mvbhSOEusSwSaiAyt?invite=cr-MSxsVDYsMjMzNjE0MTQ\&v=40)

## Architecture: Raw Fluxa APIs and 2D Directional Blending

### Why this example exists

Example 1 is the most minimal complete usage of Fluxa. It does not use `FluxaController`, layers, blend trees, or any higher-level framework features. It uses only the foundational building blocks directly.

The goal is to show you exactly what Fluxa's low-level API looks like before any abstraction is applied. If you understand Example 1, you understand what the higher examples are doing underneath.

### What this example does not have

* No `FluxaController`
* No layers
* No blend trees
* No one-shots
* No state machine
* No momentum or speed model
* No replication of any kind

Everything runs as a single `RenderStepped` connection on the local client. No server communication happens, no `RemoteEvent`s fire, and no other clients are involved.

### Why there is no replication

Example 1 is a local-only demonstration. It exists to teach the blending math, not networking. Because there is no `FluxaController` and no `FluxaReplicationService` involved, the animation output only exists on the machine running it.

This is intentional and appropriate for its purpose. If you want replication, see [Example 3](example-3.md).

### What the example does

Each frame it reads the humanoid's `MoveDirection`, projects it onto the root's local XZ axes, and produces four directional weights: Forward, Backward, Left, Right. An Idle weight fills the remainder based on how much the player is actually moving.

Those weights are normalized and used to lerp several `AnimationTrack`s together into a blended pose, which is then written to the character's joints via `UniversalJointWriter`.

### The low-level API flow

There are four modules in use:

**AnimationAsset** — wraps a `KeyframeSequence` into a samplable clip. Created once per animation from a folder in `ReplicatedStorage`.

**AnimationTrack** — wraps an `AnimationAsset` with playback state. Tracks can be played and stopped, and they expose an `Update(dt)` method that advances internal time and returns a pose sample.

**Pose** — a snapshot of joint `CFrame` transforms. Blending is done by lerping one pose against another joint by joint.

**UniversalJointWriter** — resolves canonical joint names to the actual rig joints (R6 or R15) and writes a pose to the character. This handles the retargeting step.

### Frame by frame

1. Read `humanoid.MoveDirection` and project onto root local axes to get `moveX` and `moveZ`.
2. Compute a 2D blend vector and normalize it to a direction.
3. Split the direction into four axis components, normalize by direction sum.
4. Scale each directional weight by how much the player is moving, leaving remainder as Idle weight.
5. Play any track that gained weight, stop any track that lost all weight.
6. For each active track, call `Update(dt)` to advance time and get a pose.
7. Lerp all poses together using their weights.
8. Write the blended pose to the character via `UniversalJointWriter.ApplyPose`.

### Configurable blend axis weights

The X and Z blend axis weights are exposed as `Instance` Attributes on the client script. The defaults are `X=0.35` and `Z=0.65`, meaning forward/backward movement has more influence than strafe. Both attributes are live-editable in Studio during playtest.

### Limitations compared to later examples

* No blend smoothing: weights snap to their target each frame.
* No locomotion phase sync: if two clips are both active, they run independently and can slide against each other.
* No state machine: there is no jump, fall, land, or climb handling.
* R6 only: the animation folder and retargeting are calibrated for a six-bone rig.
* No layer composition: everything is blended in a single pass without priority or masking.

### Suggested positioning statement

> Example 1 shows the raw Fluxa building blocks with no framework overhead. It is a 2D directional walk blend implementation in about 200 lines: read input, compute weights, lerp poses, write joints. Everything is visible and explicit with nothing hidden. It is the right starting point for understanding what Fluxa actually does at the base level.
