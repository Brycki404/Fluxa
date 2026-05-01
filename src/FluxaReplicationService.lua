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
local _lastSentPacket = nil -- For delta compression
local _remoteControllers = {}
local _controllerOwners = setmetatable({}, {__mode = "k"}) -- controller -> player
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

-- Per-sender-per-target accumulator
local _playerSendAccumulators = {} -- [sender][target] = {accum = 0, lastRate = 10}

local function getPlayerRoot(player)
	local char = player and player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function getLODHz(distance)
	for _, tier in ipairs(FluxaSettings.Get("LOD_TIERS", {})) do
		if distance <= tier.dist then
			return tier.rate
		end
	end
	return 1
end

local function ensureServerReceiver()
	if not RunService:IsServer() or _serverConnection then
		return
	end

	local remoteEvent = ensureRemoteEvent()
	_serverConnection = remoteEvent.OnServerEvent:Connect(function(sender, packet)
		-- LOD: send to each other player at their own rate, but never back to sender
		for _, target in ipairs(Players:GetPlayers()) do
			if target ~= sender then
				local senderRoot = getPlayerRoot(sender)
				local targetRoot = getPlayerRoot(target)
				local dist = math.huge
				if senderRoot and targetRoot and senderRoot:IsA("BasePart") and targetRoot:IsA("BasePart") then
					dist = (senderRoot.Position - targetRoot.Position).Magnitude
				end
				local rate = getLODHz(dist)
				_playerSendAccumulators[sender] = _playerSendAccumulators[sender] or {}
				local acc = _playerSendAccumulators[sender][target] or {accum = 0, lastRate = rate}
				acc.accum = acc.accum + RunService.Heartbeat:Wait()
				acc.lastRate = rate
				if acc.accum >= (1 / rate) then
					acc.accum = 0
					-- Do not send back to sender
					if target ~= sender then
						remoteEvent:FireClient(target, sender, packet)
					end
				end
				_playerSendAccumulators[sender][target] = acc
			end
		end
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

	-- Only replicate if this controller is owned by the local player
	if mode ~= FluxaTypes.ReplicationMode.ClientOwned or (Players.LocalPlayer and controller.Character and controller.Character ~= Players.LocalPlayer.Character) then
		-- Disable sending for non-owned controllers
		return
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
			-- Delta compression: only send if changed
			local function shallowEqual(a, b)
				if a == b then return true end
				if type(a) ~= "table" or type(b) ~= "table" then return false end
				for k, v in pairs(a) do if b[k] ~= v then return false end end
				for k, v in pairs(b) do if a[k] ~= v then return false end end
				return true
			end

			local changed = false
			if not _lastSentPacket then
				changed = true
			else
				-- Only compare top-level fields for now (can be deepened if needed)
				for k, v in pairs(packet) do
					if not shallowEqual(v, _lastSentPacket[k]) then
						changed = true
						break
					end
				end
			end

			if changed then
				remoteEvent:FireServer(packet)
				_lastSentPacket = packet
				if includeTrackBindings and _localController ~= nil and _localController.MarkTrackBindingsSent ~= nil then
					_localController:MarkTrackBindingsSent()
				end
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
	_controllerOwners[controller] = player

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
		warn("local replication disabled")
		return
	end

	-- Respect ReplicationMode
	local mode = (_localController and (_localController.GetReplicationMode and _localController:GetReplicationMode()))
		or (_localController and _localController._replicationMode)
		or FluxaTypes.ReplicationMode.ClientOwned

	-- In ServerOwned mode, never send local packets (neither client nor server)
	if mode == FluxaTypes.ReplicationMode.ServerOwned or mode == FluxaTypes.ReplicationMode.LocalOnly then
		warn("local replication disabled due to replication mode")
		return
	end

	-- Only allow sending in ClientOwned mode, and only from the client
	if mode == FluxaTypes.ReplicationMode.ClientOwned and RunService:IsClient() then
		local remoteEvent = tryGetRemoteEvent()
		if remoteEvent == nil then
			warn("failed 1")
			return
		end
		local packet = buildLocalPacket(true, true)
		if not packet then
			warn("failed 2")
			return
		end
		remoteEvent:FireServer(packet)
		if _localController ~= nil and _localController.MarkTrackBindingsSent ~= nil then
			_localController:MarkTrackBindingsSent()
		end
	else
		warn("broke")
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
