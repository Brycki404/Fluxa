# FluxaSettings

Shared constants and configuration for Fluxa modules (server and client).

## Key Settings
- `ANIMATION_START_REPLICATION_WINDOW`
- `NPC_REPLICATION_REMOTE`, `NPC_NOTIFY_REMOTE`, `ANIM_CMD_REMOTE`
- `NPC_SEND_RATE_HZ`, `NPC_START_TIMES_INTERVAL`, `DEFAULT_PLAY_RATE_LIMIT_WINDOW`
- `REMOTE_EVENT_NAME`, `SEND_RATE_HZ`, `ANIMATION_START_TIMES_INTERVAL`, `TRACK_BINDINGS_SYNC_INTERVAL`

## API
- `FluxaSettings.Get(index, defaultValue)`
- `FluxaSettings.Set(index, value)`

See source for all available settings.