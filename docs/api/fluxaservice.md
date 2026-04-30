
# FluxaService

Central registry and authoritative router for all FluxaController instances. Handles controller registration, NPC replication, animation commands, and global client-side stepping.

## Key Features

- Register/unregister controllers by ID, Player, or Model
- NPC replication and relevance radius
- Animation command routing (Play/Stop on all, for player, in range, on NPC)
- Debug snapshot and controller lookup utilities
- **Global client-side step loop**: All controllers are stepped via a single BindToRenderStep, with priority order (LocalPlayer, ReplicatedPlayers, NPCs, LocalOnly)
- `Start()` and `StopLoop()` methods to control the global step loop on the client

## API

- `RegisterController(id, controller)` — Register a controller with a unique ID
- `UnregisterController(id)` — Unregister a controller
- `GetController(id)` — Get a controller by ID
- `GetAllControllers()` — Get all registered controllers
- `GetControllerByCharacter(character)` — Get controller by character model
- `StartNPCReplication(id, controller, options)` — Begin server-authoritative NPC replication
- `StopNPCReplication(id)` — Stop NPC replication
- `PlayOnAll(target, trackName, options)` — Play animation on all matching targets
- `StopOnAll(target, trackName, options)` — Stop animation on all matching targets
- `PlayFor(player, target, trackName, options)` — Play animation for a specific player
- `StopFor(player, target, trackName, options)` — Stop animation for a specific player
- `PlayInRange(position, radius, target, trackName, options)` — Play animation for players in range
- `StopInRange(position, radius, target, trackName, options)` — Stop animation for players in range
- `PlayOnPlayer(player, trackName, ...)` — Play animation on a player
- `StopOnPlayer(player, trackName, ...)` — Stop animation on a player
- `PlayOnNPC(id, trackName, ...)` — Play animation on an NPC
- `StopOnNPC(id, trackName, ...)` — Stop animation on an NPC
- `Start()` — (Client) Start the global controller step loop (BindToRenderStep)
- `StopLoop()` — (Client) Stop the global controller step loop

### Global Stepping (Client)

On the client, all registered controllers are stepped in priority order each frame:

1. LocalPlayer controllers
2. Replicated player controllers
3. NPC controllers
4. LocalOnly (non-player, non-NPC) controllers

Call `FluxaService.Start()` to enable the step loop, and `FluxaService.StopLoop()` to disable it. By default, stepping auto-starts on require.

### Example: Manual Control

```lua
-- Start stepping all controllers (usually not needed unless you want to restart after StopLoop)
FluxaService.Start()

-- Stop stepping all controllers
FluxaService.StopLoop()
```

### Example: Registering a Controller

```lua
local controller = FluxaController.new({ ... })
FluxaService.RegisterController("myId", controller)
```

### Example: NPC Replication

```lua
FluxaService.StartNPCReplication("npc1", npcController, { Character = npcModel })
```

---

See the source for advanced usage and full API details.