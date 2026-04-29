--!strict
-- FluxaSettings: Shared constants for Fluxa modules (server and client)

local Settings = {}

-- Fluxa Controller settings
Settings.ANIMATION_START_REPLICATION_WINDOW = 0.6

-- Fluxa Service settings
Settings.NPC_REPLICATION_REMOTE = "FluxaService_NPCReplication"
Settings.NPC_NOTIFY_REMOTE = "FluxaService_NPCNotify"
Settings.ANIM_CMD_REMOTE = "FluxaService_AnimCmd"

Settings.NPC_SEND_RATE_HZ = 20
Settings.NPC_START_TIMES_INTERVAL = 0.25
Settings.DEFAULT_PLAY_RATE_LIMIT_WINDOW = 0.05

-- Fluxa Replication Service settings
Settings.REMOTE_EVENT_NAME = "FluxaReplication"
Settings.SEND_RATE_HZ = 30
Settings.ANIMATION_START_TIMES_INTERVAL = 0.25
-- TrackBindings change rarely (weapon/stance swap) but add bandwidth if sent
-- every packet.  We delta-replicate: include whenever the controller reports
-- its bindings as dirty, and also on a slow heartbeat so late-joining peers
-- recover within ~1s even if they miss the dirty packet.
Settings.TRACK_BINDINGS_SYNC_INTERVAL = 1.0

-- Add more shared settings here as needed


local FluxaSettings = {}
FluxaSettings.Settings = Settings

function FluxaSettings.Get(index: string, defaultValue: any): any
    return FluxaSettings.Settings[index] or defaultValue
end

function FluxaSettings.Set(index: string, value: any): ()
    FluxaSettings.Settings[index] = value
end

return FluxaSettings
