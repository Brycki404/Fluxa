# FluxaReplicationService

Module path: `Fluxa.FluxaReplicationService`

`FluxaReplicationService` handles cross-client animation state synchronization. It serializes a `FluxaController`'s layer and track state each frame and broadcasts it to remote clients, where a second "remote" controller applies the received packet.

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
| `"LoopingOnly"` | Remote controller can seek this track's time position. Good for looping clips that should stay in sync. |
| `"Never"` | Remote controller never seeks this track's time. Good for one-shots that should play from the beginning when triggered. |

### What is replicated

* Track weights (which tracks are active and at what weight)
* Track time positions (for tracks with `ReplicationSeekMode = "LoopingOnly"`)
* Layer weights

### What is not replicated

* Driver values (input state, camera direction, movement context)
* Blend tree function logic
* Procedural overrides applied in `OnPostBlend`

For full documentation of the `FluxaReplicationService` API, see the [Fluxa GitBook](https://brycki404.gitbook.io/fluxa/api-reference/fluxareplicationservice).
