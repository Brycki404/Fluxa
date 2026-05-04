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
Settings.SATSET_RELIABLE = true
Settings.SATSET_CLIENT_PACKET_NAME = "FluxaReplication_ClientToServer"
Settings.SATSET_SERVER_PACKET_NAME = "FluxaReplication_ServerToClient"
Settings.SATSET_GUARD_MAX_TOKENS = 60
Settings.SATSET_GUARD_REFILL_RATE = 30
Settings.SATSET_GUARD_STUDIO_BYPASS = true
-- LOD send rates (Hz) by distance (studs)
Settings.LOD_TIERS = {
	{ dist = 20, rate = 20 },   -- 0-20 studs: 20 Hz
	{ dist = 50, rate = 10 },   -- 20-50 studs: 10 Hz
	{ dist = 100, rate = 3 },   -- 50-100 studs: 3 Hz
	{ dist = math.huge, rate = 1 }, -- >100 studs: 1 Hz
}
Settings.ANIMATION_START_TIMES_INTERVAL = 0.25
-- TrackBindings change rarely (weapon/stance swap) but add bandwidth if sent
-- every packet.  We delta-replicate: include whenever the controller reports
-- its bindings as dirty, and also on a slow heartbeat so late-joining peers
-- recover within ~1s even if they miss the dirty packet.
Settings.TRACK_BINDINGS_SYNC_INTERVAL = 1.0
-- Number of decimal places to round numeric driver values to before comparing.
-- Reduces spurious sends from floating-point drift (e.g. aim pitch).
-- 3 = 0.001 precision (~0.057 degrees for radian angles).
Settings.DRIVER_QUANTIZE_PRECISION = 3
-- Add more shared settings here as needed


local FluxaSettings = {}
FluxaSettings.Settings = Settings

function FluxaSettings.Get(index: string, defaultValue: any): any
	local value = FluxaSettings.Settings[index]
	if value ~= nil then
		return value
	end
	return defaultValue
end

function FluxaSettings.Set(index: string, value: any): ()
    FluxaSettings.Settings[index] = value
end

return FluxaSettings
