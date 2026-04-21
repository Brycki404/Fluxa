# Example 3

[Video clip](https://medal.tv/games/roblox-studio/clips/mw3yBiXbaAsvtFC4k?invite=cr-MSxadWgsMjMzNjE0MTQ\&v=82)

## Architecture: Tracks, Layers, Drivers, and Weights

### Why this example exists

Example 3 is not trying to be the shortest path to animation. It is trying to be the most controllable path.

Default Roblox animation systems are great for rapid setup, but they are mostly state-machine driven and controller-managed. Example 3 shows a different model:

* You own the animation graph.
* You decide how every state transitions.
* You decide how every weight is calculated.
* You decide what replicates and what stays local.

### Mental model

Think of Example 3 as four systems working together each frame.

1. **Drivers produce intent and motion context.** Input driver sets input flags. Movement driver computes speed, momentum, yaw, lean, and locomotion context. Humanoid state driver converts Roblox humanoid events into explicit animation states. Combat and camera drivers feed upper-body aiming and attack intent.

2. **Drivers are written into layers.** Base layer stores locomotion and movement context. Landing layer handles landing one-shot behavior independently. UpperBody layer handles attack and aim overlays.

3. **Tracks are sampled and mixed by layer.** Tracks are the raw animation clips and one-shots. Blend trees calculate per-track target weights for a layer. Layers determine ordering and masking.

4. **Final weights decide what you see.** Track weight decides per-clip influence. Layer weight decides per-layer influence. Weight smoothing reduces pops and makes transitions readable.

### The four pillars

#### 1) Tracks

Tracks are the concrete clips: Idle, SlowWalk, Walk, Run, Jump, Fall, Land, Climb, Attack.

Each track has independent behavior:
* Looping or one-shot
* Fade in and fade out timing
* Replication seek mode
* Auto-managed or manually triggered

#### 2) Layers

Example 3 uses:
* **Base** layer for locomotion and core movement state
* **Landing** layer for land overlay control
* **UpperBody** layer for attack and aim

This means Landing no longer fights locomotion timing in Base. Upper body can aim and attack while legs continue locomotion. You can control layer priority and mask boundaries explicitly.

#### 3) Drivers

Drivers translate raw humanoid state changes into explicit animation intent, compute smoothed movement metrics for stable blending, convert camera look direction into upper-body aim parameters, and trigger one-shots at the right semantic moment.

#### 4) Weights

There are two kinds:
* **Track weights**: how much a specific clip contributes.
* **Layer weights**: how much an entire layer contributes.

Example 3 relies on weighted blending heavily: the locomotion blend tree computes Idle/SlowWalk/Walk/Run by move magnitude and momentum. Landing layer weight is speed-driven and smoothed. UpperBody layer weight is attack-influence-driven.

### Putting it together frame by frame

1. Read inputs and movement signals.
2. Update driver outputs: speed, momentum, turn lean, state flags.
3. Resolve layer states and blend params.
4. Update one-shots and trigger events when needed.
5. Compute blend-tree targets.
6. Apply track and layer weights.
7. Blend final pose and write to character joints.

### How replication works in Example 3

#### The problem with local-only controllers

In Examples 1 and 2, animation state only exists on the machine running the controller. Other clients see the default Roblox network character with default animations. `FluxaController` is designed to be replicated — its internal graph state is serializable and can be sent across the network.

#### Two replication roles

**Local replication** is for your own character. After creating a `FluxaController` for the local player's character and wiring up all the drivers, Example 3 calls:

```lua
FluxaReplicationService.StartLocalReplication(_controller)
```

**Remote replication** is for every other player's character. When a player joins, Example 3 creates a second `FluxaController` for that player's character with no drivers attached:

```lua
local remoteController = createFluxaController(character, assets, false)
FluxaReplicationService.StartRemoteReplication(remoteController, player)
```

The `false` argument skips driver setup. The remote controller has the same tracks and layers as a local controller, but receives no input. It is purely a playback target. Fluxa fills its state from the incoming replication stream and the controller applies the result to that character's joints.

#### ReplicationSeekMode

Each track has a `ReplicationSeekMode` that controls how the remote playback handles the time position received from replication.

* `LoopingOnly` — used for Idle, Walk, Run, SlowWalk, Fall, and Climb. Replication can seek their `Time` to stay synchronized.
* `Never` — used for one-shot tracks Jump, Land, and Attack. One-shots should play from the start when triggered and run to completion. Setting `Never` means the remote controller respects the trigger event but never jumps the clip's time position based on network data.

#### What is not replicated

Drivers are not replicated. The local client's input state, camera direction, and movement context never leave the local machine. The replication payload is the controller's resulting track weights and playback positions, not the game logic that produced them.

### Suggested positioning statement

> Example 3 is a programmable animation graph approach. It is intentionally more complex than default Roblox animation controllers, but in exchange it gives us deterministic behavior, layered composition, and precise control over transitions, replication, and gameplay-coupled animation logic.
