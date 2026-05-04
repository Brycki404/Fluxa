--!nonstrict
-- FluxaReplicationService: deterministic layered packet replication over Satset.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FluxaTypes = require(script.Parent.FluxaTypes)
local FluxaSettings = require(script.Parent.FluxaSettings)
local FluxaSatsetTransport = require(script.Parent.FluxaSatsetTransport)

-- Type Imports
type ReplicationMode = FluxaTypes.ReplicationMode

local ReplicationService = {}

local _remoteEvent = nil
local _satset = nil
local _satsetInitialized = false
local _satsetListenBound = false
local _satsetClientToServerPacket = nil
local _satsetServerToClientPacket = nil
local _localController = nil
local _lastSentPacket = nil -- For delta compression
local _remoteControllers = {}
local _controllerOwners = setmetatable({}, {__mode = "k"}) -- controller -> player
local _sendConnection = nil
local _clientConnection = nil
local _serverConnection = nil
local _serverRelayConnection = nil
local _localReplicationEnabled = true
local _latestPacketsBySender = {}
local _warnedUnsupportedDriverPaths = {}

local tryGetRemoteEvent
local ensureRemoteEvent
local receiveRemotePacket

local function warnUnsupportedDriverValue(path, value)
	local valueType = typeof(value)
	local warningKey = path .. "::" .. valueType
	if _warnedUnsupportedDriverPaths[warningKey] then
		return
	end

	_warnedUnsupportedDriverPaths[warningKey] = true
	warn(("FluxaReplicationService: skipping unsupported replicated driver value at '%s' (type '%s')"):format(path, valueType))
end

local function isSupportedDriverValue(value)
	local valueType = typeof(value)
	return valueType == "boolean"
		or valueType == "number"
		or valueType == "string"
		or valueType == "Vector2"
		or valueType == "Vector3"
		or valueType == "Color3"
		or valueType == "CFrame"
end

local function sanitizeDriverMap(driverMap, path)
	if type(driverMap) ~= "table" then
		return {}
	end

	local sanitized = {}
	for key, value in pairs(driverMap) do
		if type(key) == "string" then
			if isSupportedDriverValue(value) then
				sanitized[key] = value
			else
				warnUnsupportedDriverValue(path .. "." .. key, value)
			end
		end
	end

	return sanitized
end

local function sanitizeAnimationStartTimes(animationStartTimes)
	if type(animationStartTimes) ~= "table" then
		return {}
	end

	local sanitized = {}
	for key, value in pairs(animationStartTimes) do
		if type(key) == "string" and type(value) == "number" then
			sanitized[key] = value
		end
	end

	return sanitized
end

local function sanitizeTrackBindings(trackBindings)
	if type(trackBindings) ~= "table" then
		return nil
	end

	local sanitized = {}
	for key, value in pairs(trackBindings) do
		if type(key) == "string" and type(value) == "string" then
			sanitized[key] = value
		end
	end

	return sanitized
end

local function sanitizeReplicationPacket(packet)
	if type(packet) ~= "table" then
		return nil
	end

	local sanitizedLayers = {}
	if type(packet.Layers) == "table" then
		for layerName, layerState in pairs(packet.Layers) do
			if type(layerName) == "string" and type(layerState) == "table" then
				sanitizedLayers[layerName] = {
					Drivers = sanitizeDriverMap(layerState.Drivers, "Layers." .. layerName .. ".Drivers"),
					AnimationStartTimes = sanitizeAnimationStartTimes(layerState.AnimationStartTimes),
				}
			end
		end
	end

	return {
		Timestamp = if type(packet.Timestamp) == "number" then packet.Timestamp else 0,
		Drivers = sanitizeDriverMap(packet.Drivers, "Drivers"),
		Layers = sanitizedLayers,
		TrackBindings = sanitizeTrackBindings(packet.TrackBindings),
	}
end

local function _tryGetSatset()
	if _satset == false then
		return nil
	end

	if _satset ~= nil then
		return _satset
	end

	local shared = ReplicatedFirst:FindFirstChild("Shared")
	local satsetModule = if shared ~= nil then shared:FindFirstChild("Satset") else nil
	if satsetModule == nil or not satsetModule:IsA("ModuleScript") then
		_satset = false
		return nil
	end

	local ok, result = pcall(require, satsetModule)
	if not ok then
		warn(("FluxaReplicationService: failed to require Satset (%s); falling back to RemoteEvent transport"):format(tostring(result)))
		_satset = false
		return nil
	end

	_satset = result
	return _satset
end

local function createDriverValueType(types)
	local tagNil = 0
	local tagBoolean = 1
	local tagNumber = 2
	local tagString = 3
	local tagVector2 = 4
	local tagVector3 = 5
	local tagColor3 = 6
	local tagCFrame = 7

	return {
		read = function(bufferValue, cursor)
			local tag = buffer.readu8(bufferValue, cursor)
			if tag == tagBoolean then
				return types.bool.read(bufferValue, cursor + 1)
			elseif tag == tagNumber then
				return types.f64.read(bufferValue, cursor + 1)
			elseif tag == tagString then
				return types.string16.read(bufferValue, cursor + 1)
			elseif tag == tagVector2 then
				return types.Vector2.read(bufferValue, cursor + 1)
			elseif tag == tagVector3 then
				return types.Vector3.read(bufferValue, cursor + 1)
			elseif tag == tagColor3 then
				return types.Color3.read(bufferValue, cursor + 1)
			elseif tag == tagCFrame then
				return types.CFrame.read(bufferValue, cursor + 1)
			end

			return nil
		end,
		write = function(bufferValue, cursor, value)
			local valueType = typeof(value)
			if valueType == "boolean" then
				buffer.writeu8(bufferValue, cursor, tagBoolean)
				types.bool.write(bufferValue, cursor + 1, value)
			elseif valueType == "number" then
				buffer.writeu8(bufferValue, cursor, tagNumber)
				types.f64.write(bufferValue, cursor + 1, value)
			elseif valueType == "string" then
				buffer.writeu8(bufferValue, cursor, tagString)
				types.string16.write(bufferValue, cursor + 1, value)
			elseif valueType == "Vector2" then
				buffer.writeu8(bufferValue, cursor, tagVector2)
				types.Vector2.write(bufferValue, cursor + 1, value)
			elseif valueType == "Vector3" then
				buffer.writeu8(bufferValue, cursor, tagVector3)
				types.Vector3.write(bufferValue, cursor + 1, value)
			elseif valueType == "Color3" then
				buffer.writeu8(bufferValue, cursor, tagColor3)
				types.Color3.write(bufferValue, cursor + 1, value)
			elseif valueType == "CFrame" then
				buffer.writeu8(bufferValue, cursor, tagCFrame)
				types.CFrame.write(bufferValue, cursor + 1, value)
			else
				buffer.writeu8(bufferValue, cursor, tagNil)
			end
		end,
		size = 1,
		getSize = function(value)
			local valueType = typeof(value)
			if valueType == "boolean" then
				return 1 + types.bool.getSize(value)
			elseif valueType == "number" then
				return 1 + types.f64.getSize(value)
			elseif valueType == "string" then
				return 1 + types.string16.getSize(value)
			elseif valueType == "Vector2" then
				return 1 + types.Vector2.getSize(value)
			elseif valueType == "Vector3" then
				return 1 + types.Vector3.getSize(value)
			elseif valueType == "Color3" then
				return 1 + types.Color3.getSize(value)
			elseif valueType == "CFrame" then
				return 1 + types.CFrame.getSize(value)
			end

			return 1
		end,
		isFixed = false,
	}
end

local function createLayerStateType(driverMapType, animationStartTimesType)
	return {
		read = function(bufferValue, cursor)
			local drivers = driverMapType.read(bufferValue, cursor)
			local nextCursor = cursor + driverMapType.getSize(drivers)
			local animationStartTimes = animationStartTimesType.read(bufferValue, nextCursor)
			return {
				Drivers = drivers,
				AnimationStartTimes = animationStartTimes,
			}
		end,
		write = function(bufferValue, cursor, value)
			local stateValue = if type(value) == "table" then value else {}
			local drivers = if type(stateValue.Drivers) == "table" then stateValue.Drivers else {}
			driverMapType.write(bufferValue, cursor, drivers)
			local nextCursor = cursor + driverMapType.getSize(drivers)
			local animationStartTimes = if type(stateValue.AnimationStartTimes) == "table" then stateValue.AnimationStartTimes else {}
			animationStartTimesType.write(bufferValue, nextCursor, animationStartTimes)
		end,
		size = 0,
		getSize = function(value)
			local stateValue = if type(value) == "table" then value else {}
			local drivers = if type(stateValue.Drivers) == "table" then stateValue.Drivers else {}
			local animationStartTimes = if type(stateValue.AnimationStartTimes) == "table" then stateValue.AnimationStartTimes else {}
			return driverMapType.getSize(drivers) + animationStartTimesType.getSize(animationStartTimes)
		end,
		isFixed = false,
	}
end

local function _createReplicationPacketType(types)
	local driverValueType = createDriverValueType(types)
	local driverMapType = types.map(types.string16, driverValueType)
	local animationStartTimesType = types.map(types.string16, types.f64)
	local layerStateType = createLayerStateType(driverMapType, animationStartTimesType)
	local layersType = types.map(types.string16, layerStateType)
	local trackBindingsType = types.optional(types.map(types.string16, types.string16))

	return {
		read = function(bufferValue, cursor)
			local timestamp = types.f64.read(bufferValue, cursor)
			local nextCursor = cursor + types.f64.getSize(timestamp)
			local drivers = driverMapType.read(bufferValue, nextCursor)
			nextCursor += driverMapType.getSize(drivers)
			local layers = layersType.read(bufferValue, nextCursor)
			nextCursor += layersType.getSize(layers)
			local trackBindings = trackBindingsType.read(bufferValue, nextCursor)
			return {
				Timestamp = timestamp,
				Drivers = drivers,
				Layers = layers,
				TrackBindings = trackBindings,
			}
		end,
		write = function(bufferValue, cursor, value)
			local packetValue = sanitizeReplicationPacket(value)
			if packetValue == nil then
				packetValue = {
					Timestamp = 0,
					Drivers = {},
					Layers = {},
					TrackBindings = nil,
				}
			end

			types.f64.write(bufferValue, cursor, packetValue.Timestamp)
			local nextCursor = cursor + types.f64.getSize(packetValue.Timestamp)
			driverMapType.write(bufferValue, nextCursor, packetValue.Drivers)
			nextCursor += driverMapType.getSize(packetValue.Drivers)
			layersType.write(bufferValue, nextCursor, packetValue.Layers)
			nextCursor += layersType.getSize(packetValue.Layers)
			trackBindingsType.write(bufferValue, nextCursor, packetValue.TrackBindings)
		end,
		size = 0,
		getSize = function(value)
			local packetValue = sanitizeReplicationPacket(value)
			if packetValue == nil then
				return types.f64.getSize(0)
					+ driverMapType.getSize({})
					+ layersType.getSize({})
					+ trackBindingsType.getSize(nil)
			end

			return types.f64.getSize(packetValue.Timestamp)
				+ driverMapType.getSize(packetValue.Drivers)
				+ layersType.getSize(packetValue.Layers)
				+ trackBindingsType.getSize(packetValue.TrackBindings)
		end,
		isFixed = false,
	}
end

local function ensureSatsetTransport()
	local transport = FluxaSatsetTransport.Get()
	if transport == nil then
		return nil
	end

	if not _satsetInitialized then
		_satsetInitialized = true
		_satset = transport.Satset
		_satsetClientToServerPacket = transport.Packets.ClientReplication
		_satsetServerToClientPacket = transport.Packets.ServerReplication
	end

	if not _satsetListenBound then
		_satsetListenBound = true
		if RunService:IsServer() then
			_satsetClientToServerPacket:listen(function(data, sender)
				if sender == nil or type(data) ~= "table" then
					return
				end

				local packet = sanitizeReplicationPacket(data.Payload)
				if packet == nil then
					return
				end

				_latestPacketsBySender[sender] = packet
			end)
		else
			_satsetServerToClientPacket:listen(function(data)
				if type(data) ~= "table" then
					return
				end

				local senderUserId = data.SenderUserId
				if type(senderUserId) ~= "number" then
					return
				end

				local player = Players:GetPlayerByUserId(senderUserId)
				if player == nil then
					return
				end

				receiveRemotePacket(player, sanitizeReplicationPacket(data.Payload))
			end)
		end
	end

	return _satset
end

local function sendPacketToClient(targetPlayer, player, packet)
	local satset = ensureSatsetTransport()
	if satset ~= nil then
		_satsetServerToClientPacket:fireClient(targetPlayer, {
			SenderUserId = player.UserId,
			Payload = packet,
		})
		return true
	end

	local remoteEvent = ensureRemoteEvent()
	if remoteEvent == nil then
		return false
	end

	remoteEvent:FireClient(targetPlayer, player, packet)
	return true
end

local function sendPacketToServer(packet)
	local satset = ensureSatsetTransport()
	if satset ~= nil then
		_satsetClientToServerPacket:fireServer({
			Payload = packet,
		})
		return true
	end

	local remoteEvent = tryGetRemoteEvent()
	if remoteEvent == nil then
		return false
	end

	remoteEvent:FireServer(packet)
	return true
end

tryGetRemoteEvent = function()
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

ensureRemoteEvent = function()
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

	if ensureSatsetTransport() ~= nil then
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
	if not RunService:IsServer() then
		return
	end

	if ensureSatsetTransport() ~= nil then
		if _serverRelayConnection and _serverRelayConnection.Connected then
			return
		end

		_serverRelayConnection = RunService.Heartbeat:Connect(function(dt)
			for sender, packet in pairs(_latestPacketsBySender) do
				if sender == nil or sender.Parent == nil then
					_latestPacketsBySender[sender] = nil
					_playerSendAccumulators[sender] = nil
					continue
				end

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
						acc.accum += dt
						acc.lastRate = rate
						if acc.accum >= (1 / rate) then
							acc.accum = 0
							sendPacketToClient(target, sender, packet)
						end
						_playerSendAccumulators[sender][target] = acc
					end
				end
			end
		end)
		return
	end

	if _serverConnection then
		return
	end

	local remoteEvent = ensureRemoteEvent()
	_serverConnection = remoteEvent.OnServerEvent:Connect(function(sender, packet)
		packet = sanitizeReplicationPacket(packet)
		if packet == nil then
			return
		end

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
				acc.accum = acc.accum + (1 / math.max(FluxaSettings.Get("SEND_RATE_HZ", 30), 1))
				acc.lastRate = rate
				if acc.accum >= (1 / rate) then
					acc.accum = 0
					-- Do not send back to sender
					if target ~= sender then
						sendPacketToClient(target, sender, packet)
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
			packet = sanitizeReplicationPacket(packet)
			if packet == nil then
				return
			end

			-- Delta compression: only send if any leaf value changed
			local function deepEqual(a, b)
				if a == b then
					return true
				end
				if type(a) ~= "table" or type(b) ~= "table" then
					return false
				end
				for k, v in pairs(a) do
					if not deepEqual(v, b[k]) then
						return false
					end
				end
				for k in pairs(b) do
					if a[k] == nil then
						return false
					end
				end
				return true
			end

			local changed = not deepEqual(packet, _lastSentPacket)

			if changed then
				sendPacketToServer(packet)
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
		if ensureSatsetTransport() == nil and tryGetRemoteEvent() == nil then
			warn("failed 1")
			return
		end
		local packet = buildLocalPacket(true, true)
		if not packet then
			warn("failed 2")
			return
		end
		packet = sanitizeReplicationPacket(packet)
		if packet == nil then
			warn("failed 3")
			return
		end
		sendPacketToServer(packet)
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

	if RunService:IsServer() then
		for _, targetPlayer in ipairs(Players:GetPlayers()) do
			if targetPlayer ~= player then
				sendPacketToClient(targetPlayer, player, packet)
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

receiveRemotePacket = ReplicationService.ReceiveRemotePacket

if RunService:IsServer() then
	ensureServerReceiver()
end

return ReplicationService
