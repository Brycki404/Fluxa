--!nonstrict
-- FluxaReplicationService: deterministic layered packet replication over RemoteEvent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FluxaTypes = require(script.Parent.FluxaTypes)
local FluxaSettings = require(script.Parent.FluxaSettings)

-- Type Imports
type ReplicationMode = FluxaTypes.ReplicationMode

local ReplicationService = {}

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

	local existing = ReplicatedStorage:FindFirstChild(FluxaSettings.Get("REMOTE_EVENT_NAME", "FluxaReplication"))
	if existing and existing:IsA("RemoteEvent") then
		_remoteEvent = existing
		return _remoteEvent
	end

	if RunService:IsServer() then
		local created = Instance.new("RemoteEvent")
		created.Name = FluxaSettings.Get("REMOTE_EVENT_NAME", "FluxaReplication")
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

	_remoteEvent = ReplicatedStorage:WaitForChild(FluxaSettings.Get("REMOTE_EVENT_NAME", "FluxaReplication"), 10)
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

local function stripTrackBindings(packet)
	if packet == nil then
		return
	end
	packet.TrackBindings = nil
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

local function buildLocalPacket(includeAnimationStartTimes, includeTrackBindings)
	if _localController == nil or _localController.GetReplicationPacket == nil then
		return nil
	end

	-- Ask the controller up front whether to include bindings; this lets the
	-- controller clear its dirty flag in one place instead of relying on the
	-- replication service to strip the field after the fact.
	local packet = _localController:GetReplicationPacket({
		IncludeTrackBindings = includeTrackBindings == true,
	})

	if not includeAnimationStartTimes and not hasAnimationStartTimes(packet) then
		stripAnimationStartTimes(packet)
	end

	if not includeTrackBindings then
		stripTrackBindings(packet)
	end

	return packet
end

local function ensureClientReceiver()
	if not RunService:IsClient() then
		return
	end

	-- Reconnect after character-script teardown (e.g. respawn) if the old connection is dead.
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

function ReplicationService.StartLocalReplication(controller, replicationMode: ReplicationMode?)
	if controller == nil then
		return
	end

	_localController = controller
	ensureClientReceiver()

	-- Determine replication mode (prefer controller property, then argument, then default)
	local mode = replicationMode or (controller.GetReplicationMode and controller:GetReplicationMode()) or controller._replicationMode or FluxaTypes.ReplicationMode.ClientOwned
	controller._replicationMode = mode

	-- ReplicationMode logic
	if mode == FluxaTypes.ReplicationMode.LocalOnly then
		-- No replication, just run locally
		return
	elseif mode == FluxaTypes.ReplicationMode.ServerOwned then
		-- If on client, do not replicate to server
		if RunService:IsClient() then
			return
		end
		-- If on server, continue to replicate to clients
	elseif mode == FluxaTypes.ReplicationMode.ClientOwned then
		-- Only the owning client should replicate to the server
		-- (On server, do not send updates; on client, allow replication)
		if RunService:IsServer() then
			return
		end
	end

	if _sendConnection then
		_sendConnection:Disconnect()
		_sendConnection = nil
	end

	local sendAccumulator = 0
	local animationStartAccumulator = FluxaSettings.Get("ANIMATION_START_TIMES_INTERVAL", 0.25)
	local trackBindingsSyncAccumulator = FluxaSettings.Get("TRACK_BINDINGS_SYNC_INTERVAL", 1.0)

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
		trackBindingsSyncAccumulator += dt

		if sendAccumulator < (1 / FluxaSettings.Get("SEND_RATE_HZ", 30)) then
			return
		end

		sendAccumulator = 0
		local includeAnimationStartTimes = animationStartAccumulator >= FluxaSettings.Get("ANIMATION_START_TIMES_INTERVAL", 0.25)
		if includeAnimationStartTimes then
			animationStartAccumulator = 0
		end

		-- Include bindings whenever they're dirty or at least once every
		-- TRACK_BINDINGS_SYNC_INTERVAL seconds so peers heal from dropped packets.
		local bindingsDirty = false
		if _localController ~= nil and _localController.IsTrackBindingsDirty ~= nil then
			bindingsDirty = _localController:IsTrackBindingsDirty() == true
		end
		local includeTrackBindings = bindingsDirty or trackBindingsSyncAccumulator >= FluxaSettings.Get("TRACK_BINDINGS_SYNC_INTERVAL", 1.0)
		if includeTrackBindings then
			trackBindingsSyncAccumulator = 0
		end

		local packet = buildLocalPacket(includeAnimationStartTimes, includeTrackBindings)
		if packet then
			remoteEvent:FireServer(packet)
			if includeTrackBindings and _localController ~= nil and _localController.MarkTrackBindingsSent ~= nil then
				_localController:MarkTrackBindingsSent()
			end
		end
	end)
end

function ReplicationService.SetLocalReplicationEnabled(enabled)
	_localReplicationEnabled = enabled == true
end

function ReplicationService.EnsureClientReceiver()
	ensureClientReceiver()
end

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

	-- Respect ReplicationMode
	local mode = (_localController and (_localController.GetReplicationMode and _localController:GetReplicationMode()))
		or (_localController and _localController._replicationMode)
		or FluxaTypes.ReplicationMode.ClientOwned

	-- In ServerOwned mode, never send local packets (neither client nor server)
	if mode == FluxaTypes.ReplicationMode.ServerOwned or mode == FluxaTypes.ReplicationMode.LocalOnly then
		return
	end

	-- Only allow sending in ClientOwned mode, and only from the client
	if mode == FluxaTypes.ReplicationMode.ClientOwned and RunService:IsClient() then
		local remoteEvent = tryGetRemoteEvent()
		if remoteEvent == nil then
			return
		end
		local packet = buildLocalPacket(true, true)
		if not packet then
			return
		end
		remoteEvent:FireServer(packet)
		if _localController ~= nil and _localController.MarkTrackBindingsSent ~= nil then
			_localController:MarkTrackBindingsSent()
		end
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
