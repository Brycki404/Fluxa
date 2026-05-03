
# FluxaService

Module path: `Fluxa.FluxaService`

Global registry and command-routing service for `FluxaController` instances.

`FluxaService` is shared by server and client. It handles:

* Controller registration and lookups
* Server-authoritative NPC replication
* Server -> client animation command envelopes (play/stop)
* Optional global client step loop

## Signals and callbacks

* `FluxaService.Registered` (`Signal`) fires `(id, controller)` on registration.
* `FluxaService.Unregistered` (`Signal`) fires `(id, controller)` on unregister.
* `FluxaService.OnNPCRegistered` (`function?`) client callback `(npcId, character)`.
* `FluxaService.OnNPCUnregistered` (`function?`) client callback `(npcId)`.

## Controller registry API

#### `FluxaService.RegisterController(id, controller)`

Registers a controller under `id`. Replaces conflicting registrations and auto-cleans when character is removed.

#### `FluxaService.UnregisterController(id)`

Unregisters by id.

#### `FluxaService.GetController(id)` / `FluxaService.Get(id)`

Returns registered controller for `id`, or `nil`.

#### `FluxaService.GetAllControllers()` / `FluxaService.GetAll()`

Returns a map of all active registrations.

#### `FluxaService.GetControllerByCharacter(character)`

Returns the controller associated with a character model, if present.

#### `FluxaService.GetDebugSnapshot()` / `FluxaService.DebugDump()`

Inspection helpers for registry and NPC state.

#### `FluxaService.GetKnownNPCs()`

Client-side known NPC map (`npcId -> character?`) from notify envelopes.

## Server animation command API

Targets can be:

* `Player`
* `Model` character
* NPC `id` string

#### Play commands

* `PlayOnAll(target, trackName, options?)`
* `PlayFor(player, target, trackName, options?)`
* `PlayInRange(position, radius, target, trackName, options?)`

Return: `boolean` (`false` when rate-limited).

#### Stop commands

* `StopOnAll(target, trackName?, options?)`
* `StopFor(player, target, trackName?, options?)`
* `StopInRange(position, radius, target, trackName?, options?)`

#### Convenience wrappers

* `PlayOnPlayer(player, trackName, fadeInTime?, weight?, speed?)`
* `StopOnPlayer(player, trackName?, fadeOutTime?)`
* `PlayOnNPC(id, trackName, fadeInTime?, weight?, speed?)`
* `StopOnNPC(id, trackName?, fadeOutTime?)`

## Server NPC replication API

#### `FluxaService.StartNPCReplication(id, controller, characterOrOptions?, options?)`

Starts server-authoritative packet replication for an NPC controller.

Options support:

* `Character` (model)
* `RelevanceRadius` (distance filter)
* `ShouldReplicateToPlayer` (custom predicate)

#### `FluxaService.StopNPCReplication(id)`

Stops replication and unregisters the NPC id.

## Client global stepping

Client-only methods:

* `FluxaService.Start()`
* `FluxaService.StopLoop()`

When started, controllers are stepped from `RunService.Stepped` in priority order:

1. Local player controllers
2. Other player controllers
3. NPC controllers
4. Local-only controllers

Stepping is not automatically started by `FluxaService` itself; call `Start()` explicitly when you want global stepping.

```lua
local Fluxa = require(ReplicatedStorage.Packages.fluxa)
local FluxaService = Fluxa.FluxaService

-- Client
FluxaService.Start()

-- Later, if needed
FluxaService.StopLoop()
```