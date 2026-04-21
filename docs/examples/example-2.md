# Example 2

[Video clip](https://medal.tv/games/roblox-studio/clips/mvyAkmOl05pxo3kbS?invite=cr-MSxiRXUsMjMzNjE0MTQ\&v=26)

## Architecture: Manual State Machine and Locomotion Polish

### Why this example exists

Example 2 is the middle step between raw API usage and the full `FluxaController` graph. It still uses `AnimationTrack`, `Pose`, and `UniversalJointWriter` directly with no `FluxaController` or layers. But on top of that foundation it builds a complete locomotion state machine, a momentum model, phase-synced gait, and additive turn-lean.

The purpose is to show how far you can go with the raw API before you need the structure that `FluxaController` provides. Example 2 is a credible complete animation controller. It lacks replication and upper-body layering, but locomotion, air states, landing, and sprint feel polished.

### What this example does not have

Like Example 1, there is no `FluxaController`, no layer system, and no blend trees. There is also no replication of any kind.

Everything runs in a single `RenderStepped` connection on the local client.

### What the example does

Example 2 controls a full R15 character with eight animation clips: Idle, SlowWalk, Walk, Run, Jump, Fall, Land, and Climb.

It tracks an explicit air state string (`Ground`, `Jump`, `Fall`, `Land`, `Climb`) driven by `HumanoidStateChanged`. Each state has its own blend weight logic. Looping tracks play and stop automatically based on whether their smoothed weight is nonzero. One-shots (Jump and Land) are triggered only from state events, never from the weight math.

On top of the state machine, it runs a momentum model, phase-synced gait, and turn-lean, all computed in the render loop.

### Systems in detail

#### State machine

Five air states: `Ground`, `Jump`, `Fall`, `Land`, `Climb`.

Transitions are driven by `Humanoid.StateChanged` events. When the humanoid reports `Jumping`, the Jump one-shot plays and the state becomes `Jump`. `Freefall` transitions to `Fall`. `Landed` or `Running` transitions to `Land` (with a cooldown to prevent re-triggering) then automatically to `Ground` after a short blend duration. `Climbing` activates `Climb`.

#### Momentum

Momentum is a `0` to `1` value that builds while the character is moving without shift held and decays when stopped or shift is held. It drives `WalkSpeed` between `BASE_WALK_SPEED` and `MAX_RUN_SPEED`, and it gates which blend clips receive weight: at momentum `0` the character blends between Idle and Walk; at momentum `1` it blends between Walk and Run.

#### Shift (slow walk)

Holding shift (default `C`) zeroes momentum, lowers `WalkSpeed` to `SLOW_WALK_SPEED`, and switches the ground blend to use only Idle and SlowWalk, bypassing the Walk and Run clips entirely.

#### Phase-locked gait

SlowWalk, Walk, and Run tracks are phase-locked: rather than playing at their natural playback speed, their `Speed` is set to `0` every frame and their `Time` position is driven directly from a shared `locomotionPhase` accumulator.

The accumulator advances at a rate proportional to the character's current planar speed relative to `BASE_WALK_SPEED`, clamped between `LOCOMOTION_MIN_CYCLE_RATE` and `LOCOMOTION_MAX_CYCLE_RATE`. All three clips advance together regardless of which one has weight, so transitions between slow walk, walk, and run never produce foot-slide from mis-aligned gait cycles.

#### Turn lean

Each frame the root's yaw is compared to the previous frame's yaw to get a yaw rate in radians per second. That rate is scaled by a sensitivity constant and a speed-proportional lean scale, then clamped to a max lean angle in degrees.

The result is smoothed over time and applied additively to `UpperTorso` (and `Torso` for R6) and `LowerTorso` with a reduced scale. This produces a visual banking effect when turning at speed without requiring any dedicated turn animation clips.

#### Blend weight smoothing

All blend weights pass through a per-name smoothing accumulator before being applied. Each frame, the current smoothed value lerps toward the raw target weight at `WEIGHT_SMOOTH_SPEED`. This removes the visual popping that would occur if weights changed instantly when the state machine transitions.

### Frame by frame

1. Sample planar speed and smooth it.
2. Apply a face-direction lerp to the root `CFrame` if moving.
3. Compute this frame's yaw delta and update turn lean.
4. Update momentum: build if moving and not in slow walk, decay if stopped or shifting.
5. Set humanoid `WalkSpeed` from momentum curve.
6. Advance `locomotionPhase` accumulator, then seek SlowWalk/Walk/Run to match.
7. Advance Land blend timer if in Land state; hand off to Ground when done.
8. Compute raw blend weights for current air state.
9. Smooth all weights toward targets.
10. Auto play or stop looping clips based on smoothed weight.
11. Sample all playing tracks with `Update(dt)`.
12. Lerp all sampled poses together weighted by smoothed weights.
13. Apply turn lean additively to torso joints in the blended pose.
14. Write final pose to character via `UniversalJointWriter.ApplyPose`.

### Limitations compared to Example 3

* No layers: Land, Idle, Run, Jump, and all other clips compete in the same linear lerp.
* No upper-body masking: there is no way to isolate combat or aim to the upper body while legs continue locomotion.
* No replication: the output only exists on the local client.
* Manual weight math: adding a new state requires editing the weight block in the render loop.

### Summarizing statement

> Example 2 is a complete local animation controller built without `FluxaController`. It shows how to implement momentum, air states, phase-synced locomotion, and turn lean using only the raw Fluxa API. It is the right reference for single-player experiences or projects where replication and layer composition are not a requirement.