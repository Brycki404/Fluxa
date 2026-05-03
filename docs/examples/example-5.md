# Example 5

Example 5 combines the binding-manager architecture from Example 4 with the multiplayer registry and routing flow of `FluxaService`.

It demonstrates a full playable setup with:

* local player controller
* replicated remote player controllers
* server-owned NPC visual controllers on clients
* shared binding catalog + binding set manager

## What it demonstrates

1. Shared controller lifecycle through `FluxaService.RegisterController`.
2. Binding-driven track loading via `FluxaBindingSetManager`.
3. Local/remote player replication through `FluxaReplicationService`.
4. Client-side visual NPC controllers keyed by NPC id.
5. Layered procedural post-blend logic (`OnPostBlend`) for turn lean and aim/look composition.
6. Track swap policy using `PreservePhaseOnSwap` for locomotion continuity.

## Core architecture

Example 5 keeps the same animation graph shape as Example 3:

* `Base` layer for locomotion and airborne state
* `Landing` layer for land one-shots
* `UpperBody` layer for attack and aim overlays

The difference is ownership and routing:

* controllers are registered by player or NPC id in `FluxaService`
* remote player controllers are started with `FluxaReplicationService.StartRemoteReplication`
* local controller packets are pushed by `FluxaReplicationService.StartLocalReplication`
* tagged NPCs (`FluxaNPC`) are mirrored into client visual models and animated locally

## Required setup

Example 5 expects at least one of these animation folders in `ReplicatedStorage`:

* `Example3Animations_R15`
* `Example2Animations_R15`

It also expects a `ServerNPC` model in `Workspace` for the NPC demo path.

The provided server script at `dev/ServerScriptService/Server/Example5NPC.server.luau` assigns it an id attribute and tag:

* `FluxaNPCId` (attribute)
* `FluxaNPC` (CollectionService tag)

## Binding catalog behavior

`Example5BindingCatalog` currently ships a default set that maps track names directly to same-name sources:

* `Idle`, `Walk`, `Run`, `SlowWalk`
* `Jump`, `Fall`, `Land`, `Climb`
* `Attack`

This keeps Example 5 content-light while preserving the full binding pipeline from Example 4.

## Swap policy

Locomotion tracks (`Walk`, `Run`, `SlowWalk`, `Climb`) are configured with `PreservePhaseOnSwap = true`.

One-shots like `Attack` and `Land` use non-looping behavior with `ReplicationSeekMode = "Never"` so start timing is explicit and deterministic.

## Procedural layering

Example 5 uses `OnPostBlend` to apply procedural corrections after track/layer blending:

* turn lean on torso joints
* weighted aim pitch during attack
* complementary look-at style head/torso offsets when attack influence is low

This shows how authored animation and procedural motion can coexist in one controller.

## Running Example 5

Set `StarterPlayerScripts/Client.ex` to `5`.

The client bootstrap will:

1. Start `FluxaService` stepping.
2. Build/reuse a shared `FluxaBindingSetManager`.
3. Spawn local controller + drivers.
4. Spawn remote player replication controllers.
5. Spawn client visual NPC controllers for tagged NPC models.

## Practical takeaway

Use Example 5 as the reference when you want Example 4-style binding modularity plus production-like multi-actor ownership and replication orchestration.
