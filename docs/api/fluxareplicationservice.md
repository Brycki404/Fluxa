# FluxaReplicationService

Module path: `Fluxa.FluxaReplicationService`

`FluxaReplicationService` handles cross-client animation state synchronization. It serializes a `FluxaController` replication packet each frame (track bindings, global drivers, layer drivers, and recent animation start markers) and broadcasts it to remote clients, where a second "remote" controller applies the received packet.

### Overview

Fluxa replication uses a two-controller model:

* **Local controller**: the controller on the machine that owns the character. Has full drivers, blend trees, and game logic wired in. Produces the authoritative animation state each frame.
* **Remote controller**: a controller on every other client for the same character. Has no drivers. Receives replication packets and applies them to stay in sync.

### Setup

On the local client, after creating the character's controller:

```lua
FluxaReplicationService.SetLocalReplicationEnabled(true)
FluxaReplicationService.StartLocalReplication(localController)
```

On all clients, when a remote player's character spawns:

```lua
local remoteController = createControllerForCharacter(player.Character, assets, false)
FluxaReplicationService.StartRemoteReplication(remoteController, player)
```

Clean up on `PlayerRemoving`:

```lua
Players.PlayerRemoving:Connect(function(player)
    local rc = remoteControllers[player]
    if rc then
        rc:Destroy()
        remoteControllers[player] = nil
    end
end)
```

### ReplicationSeekMode per track

Each `TrackConfig` accepts a `ReplicationSeekMode` string:

| Value | Behavior |
|-------|----------|
| `"Always"` | Remote controller always seeks this track's time position. Useful when non-looped and looping clips both need strict phase sync. |
| `"LoopingOnly"` | Remote controller can seek this track's time position. Good for looping clips that should stay in sync. |
| `"Never"` | Remote controller never seeks this track's time. Good for non-looped clips that should play from the beginning when triggered. |

### What is replicated

* Global drivers filtered by per-driver replication flags
* Layer drivers filtered by per-driver replication flags
* Animation start markers (`MarkLayerAnimationStart` or auto start markers from `AutoReplicate` tracks)
* Track bindings (`trackName -> bindingId`) so remote controllers can hot-swap tracks without changing blend trees

### What is not replicated

* Drivers explicitly disabled via `SetGlobalDriverReplication(..., false)` or `SetLayerDriverReplication(..., false)`
* Blend tree function logic
* Procedural overrides applied in `OnPostBlend`

### Driver-by-driver replication control

Use the controller API to choose replication per driver:

* Global: `SetGlobalDriverReplication(key, enabled)`
* Layer: `SetLayerDriverReplication(layerName, key, enabled)`

You can also provide defaults up front with `GlobalDriverReplication` and `LayerDriverReplication` in `FluxaController.new(...)`.

For full documentation of the `FluxaReplicationService` API, see the [Fluxa GitBook](https://brycki404.gitbook.io/fluxa/api-reference/fluxareplicationservice).
