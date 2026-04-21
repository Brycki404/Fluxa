--!nonstrict
-- FluxaReplicationService: deterministic layered packet replication over RemoteEvent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ReplicationService = {}

local REMOTE_EVENT_NAME = "FluxaReplication"
local SEND_RATE_HZ = 30
local ANIMATION_START_TIMES_INTERVAL = 0.25

local _remoteEvent = nil
local _localController = nil
local _remoteControllers = {}
local _sendConnection = nil
local _clientConnection = nil
local _serverConnection = nil
local _localReplicationEnabled = true

local function tryGetRemoteEvent()
	if _remoteEvent and _remoteEvent.Parent then
		return _remoteEvent
	end

	local existing = ReplicatedStorage:FindFirstChild(REMOTE_EVENT_NAME)
	if existing and existing:IsA("RemoteEvent") then
		_remoteEvent = existing
		return _remoteEvent
	end

	if RunService:IsServer() then
		local created = Instance.new("RemoteEvent")
		created.Name = REMOTE_EVENT_NAME
		created.Parent = ReplicatedStorage
		_remoteEvent = created
		return _remoteEvent
	end

	return nil
end

local function ensureRemoteEvent()
	local existingOrCreated = tryGetRemoteEvent()
	if existingOrCreated then
		return existingOrCreated
	end

	_remoteEvent = ReplicatedStorage:WaitForChild(REMOTE_EVENT_NAME)
	return _remoteEvent
end

local function stripAnimationStartTimes(packet)
	if packet == nil or packet.Layers == nil then
		return
	end

	for _, layerState in pairs(packet.Layers) do
		layerState.AnimationStartTimes = {}
	end
end

local function hasAnimationStartTimes(packet)
	if packet == nil or packet.Layers == nil then
		return false
	end

	for _, layerState in pairs(packet.Layers) do
		if next(layerState.AnimationStartTimes) ~= nil then
			return true
		end
	end

	return false
end

local function buildLocalPacket(includeAnimationStartTimes)
	if _localController == nil or _localController.GetReplicationPacket == nil then
		return nil
	end

	local packet = _localController:GetReplicationPacket()
	if not includeAnimationStartTimes and not hasAnimationStartTimes(packet) then
		stripAnimationStartTimes(packet)
	end

	return packet
end

local function ensureClientReceiver()
	if not RunService:IsClient() then
		return
	end

	-- Guarding on `.Connected` (not just presence of the value) is the
	-- key fix for cross-respawn replication: when the FIRST caller of
	-- ensureClientReceiver was a per-character LocalScript (Animate in
	-- StarterCharacterScripts), Roblox auto-disconnects the
	-- OnClientEvent binding when that script is torn down on death.
	-- The module variable still held the now-dead connection object,
	-- so the old truthy check blocked the reconnect and packets piled
	-- up in the RemoteEvent queue until the warning fired.  Reading
	-- .Connected means we reconnect transparently if the previous one
	-- has been invalidated.
	if _clientConnection and _clientConnection.Connected then
		return
	end
	_clientConnection = nil

	local remoteEvent = tryGetRemoteEvent()
	if remoteEvent == nil then
		return
	end

	_clientConnection = remoteEvent.OnClientEvent:Connect(function(player, packet)
		ReplicationService.ReceiveRemotePacket(player, packet)
	end)
end

local function ensureServerReceiver()
	if not RunService:IsServer() or _serverConnection then
		return
	end

	local remoteEvent = ensureRemoteEvent()
	_serverConnection = remoteEvent.OnServerEvent:Connect(function(player, packet)
		ReplicationService.ReceiveRemotePacket(player, packet)
	end)
end

function ReplicationService.StartLocalReplication(controller)
	if controller == nil then
		return
	end

	_localController = controller
	ensureClientReceiver()

	if _sendConnection then
		_sendConnection:Disconnect()
		_sendConnection = nil
	end

	local sendAccumulator = 0
	local animationStartAccumulator = ANIMATION_START_TIMES_INTERVAL

	_sendConnection = RunService.Heartbeat:Connect(function(dt)
		if not _localReplicationEnabled then
			return
		end

		ensureClientReceiver()
		local remoteEvent = tryGetRemoteEvent()
		if remoteEvent == nil then
			return
		end

		sendAccumulator += dt
		animationStartAccumulator += dt

		if sendAccumulator < (1 / SEND_RATE_HZ) then
			return
		end

		sendAccumulator = 0
		local includeAnimationStartTimes = animationStartAccumulator >= ANIMATION_START_TIMES_INTERVAL
		if includeAnimationStartTimes then
			animationStartAccumulator = 0
		end

		local packet = buildLocalPacket(includeAnimationStartTimes)
		if packet then
			remoteEvent:FireServer(packet)
		end
	end)
end

function ReplicationService.SetLocalReplicationEnabled(enabled)
	_localReplicationEnabled = enabled == true
end

-- Public handle so a persistent client script (RemoteAnimate in
-- StarterPlayerScripts) can bind the OnClientEvent receiver at session
-- start instead of leaving it to whichever caller happens to hit
-- StartLocalReplication / StartRemoteReplication first.  The connection
-- is lifetime-bound to the script that calls Connect, so pinning it to
-- a persistent script means it survives every character respawn.
function ReplicationService.EnsureClientReceiver()
	ensureClientReceiver()
end

-- Tear down the local send loop and drop our reference to the owning
-- controller.  Call from the owning client's character-death hook
-- BEFORE destroying the controller -- otherwise the Heartbeat loop
-- keeps calling GetReplicationPacket on a destroyed controller whose
-- Layers table has been cleared, which fan-outs empty packets to peers
-- for the full death->respawn interval.  A subsequent respawn just
-- calls StartLocalReplication again with the fresh controller.
function ReplicationService.StopLocalReplication()
	if _sendConnection then
		_sendConnection:Disconnect()
		_sendConnection = nil
	end
	_localController = nil
end

function ReplicationService.StartRemoteReplication(controller, player)
	if controller == nil or player == nil then
		return
	end

	_remoteControllers[player] = controller

	if RunService:IsClient() then
		ensureClientReceiver()
	else
		ensureServerReceiver()
	end
end

-- Drop the controller reference for a remote player whose character has
-- been removed (death / leave).  Without this the destroyed peer
-- controller stays registered in _remoteControllers until a fresh
-- spawn overwrites it, so any packets that arrive during the respawn
-- gap get applied to a stale Layers table on a dead controller.
function ReplicationService.ClearRemoteController(player)
	if player == nil then
		return
	end
	_remoteControllers[player] = nil
end

function ReplicationService.SendLocalPacket()
	if not _localReplicationEnabled then
		return
	end

	local remoteEvent = tryGetRemoteEvent()
	if remoteEvent == nil then
		return
	end

	local packet = buildLocalPacket(true)
	if packet then
		remoteEvent:FireServer(packet)
	end
end

function ReplicationService.ReceiveRemotePacket(player, packet)
	if player == nil or packet == nil then
		return
	end

	local remoteEvent = ensureRemoteEvent()

	if RunService:IsServer() then
		for _, targetPlayer in ipairs(Players:GetPlayers()) do
			if targetPlayer ~= player then
				remoteEvent:FireClient(targetPlayer, player, packet)
			end
		end
		return
	end

	if Players.LocalPlayer and player == Players.LocalPlayer then
		return
	end

	local controller = _remoteControllers[player]
	if controller == nil then
		return
	end

	if controller.ApplyReplicationPacket then
		controller:ApplyReplicationPacket(packet)
	end
end

if RunService:IsServer() then
	ensureServerReceiver()
end

return ReplicationService
