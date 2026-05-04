# FluxaSettings

Module path: `Fluxa.FluxaSettings`

Shared constants and runtime configuration for Fluxa modules on both server and client.

## API

#### `FluxaSettings.Get(index, defaultValue)`

Gets a setting by key, returning `defaultValue` when missing.

| Parameter | Type | Description |
|-----------|------|-------------|
| `index` | `string` | Setting key |
| `defaultValue` | `any` | Value returned if key is not set |

Returns: `any`

#### `FluxaSettings.Set(index, value)`

Sets or overrides a setting key at runtime.

| Parameter | Type | Description |
|-----------|------|-------------|
| `index` | `string` | Setting key |
| `value` | `any` | New value |

## Built-in Settings

#### Controller

* `ANIMATION_START_REPLICATION_WINDOW = 0.6`

#### FluxaService remotes

* `NPC_REPLICATION_REMOTE = "FluxaService_NPCReplication"`
* `NPC_NOTIFY_REMOTE = "FluxaService_NPCNotify"`
* `ANIM_CMD_REMOTE = "FluxaService_AnimCmd"`

#### FluxaService behavior

* `NPC_SEND_RATE_HZ = 20`
* `NPC_START_TIMES_INTERVAL = 0.25`
* `DEFAULT_PLAY_RATE_LIMIT_WINDOW = 0.05`
* `LOD_TIERS = { {dist, rate}, ... }` distance-based replication rates

#### FluxaReplicationService

* `REMOTE_EVENT_NAME = "FluxaReplication"`
* `ANIMATION_START_TIMES_INTERVAL = 0.25`
* `TRACK_BINDINGS_SYNC_INTERVAL = 1.0`
* `SATSET_RELIABLE = true`
* `SATSET_CLIENT_PACKET_NAME = "FluxaReplication_ClientToServer"`
* `SATSET_SERVER_PACKET_NAME = "FluxaReplication_ServerToClient"`
* `SATSET_GUARD_MAX_TOKENS = 60`
* `SATSET_GUARD_REFILL_RATE = 30`
* `SATSET_GUARD_STUDIO_BYPASS = true`

```lua
local FluxaSettings = Fluxa.FluxaSettings

-- Example: change default play command rate-limit window
FluxaSettings.Set("DEFAULT_PLAY_RATE_LIMIT_WINDOW", 0.1)
```