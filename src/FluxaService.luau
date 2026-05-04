--!strict
-- FluxaService: registry + server-authoritative routing for FluxaController instances.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(script.Parent.Signal)
local FluxaSatsetTransport = require(script.Parent.FluxaSatsetTransport)
local FluxaTypes = require(script.Parent.FluxaTypes)
local FluxaSettings = require(script.Parent.FluxaSettings)

-- Type Imports
type NPCEntry = FluxaTypes.NPCEntry
type ControllerInstance = FluxaTypes.ControllerInstance
type AnimTargetType = FluxaTypes.AnimTargetType
type ResolvedAnimTarget = FluxaTypes.ResolvedAnimTarget
type PlayOptions = FluxaTypes.PlayOptions
type StopOptions = FluxaTypes.StopOptions
type NPCPacketEnvelope = FluxaTypes.NPCPacketEnvelope
type AnimCmdEnvelope = FluxaTypes.AnimCmdEnvelope
type NPCReplicationOptions = FluxaTypes.NPCReplicationOptions

local IS_SERVER = RunService:IsServer()
local IS_CLIENT = RunService:IsClient()

local _registry = setmetatable({}, { __mode = "v" }) :: any
local _characterRegistry = setmetatable({}, { __mode = "kv" }) :: any
local _controllerIds = setmetatable({}, { __mode = "k" }) :: any
local _cleanupConnections = {} :: {[any]: RBXScriptConnection}
local _npcEntries = {} :: {[string]: NPCEntry}
local _playRateLimit = {} :: {[string]: number}
local _knownNPCs = {} :: {[string]: Model?}
local _npcStepConnection: RBXScriptConnection? = nil
local _satset = nil :: any
local _satsetInitialized = false
local _satsetListenersBound = false
local _satsetNPCReplicationPacket = nil :: any
local _satsetAnimCmdPacket = nil :: any

local getOrCreateRemote
local findRemote

local FluxaService = {}

FluxaService.Registered = Signal.new()
FluxaService.Unregistered = Signal.new()
FluxaService.OnNPCRegistered = nil :: ((id: string, character: Model?) -> ())?
FluxaService.OnNPCUnregistered = nil :: ((id: string) -> ())?

local function sanitizeDriverValue(value: any): any
	local valueType = typeof(value)
	if valueType == "boolean"
		or valueType == "number"
		or valueType == "string"
		or valueType == "Vector2"
		or valueType == "Vector3"
		or valueType == "Color3"
		or valueType == "CFrame" then
		return value
	end

	return nil
end

local function sanitizeDriverMap(driverMap: any): {[string]: any}
	if type(driverMap) ~= "table" then
		return {}
	end

	local sanitized: {[string]: any} = {}
	for key, value in pairs(driverMap) do
		if type(key) == "string" then
			local sanitizedValue = sanitizeDriverValue(value)
			if sanitizedValue ~= nil then
				sanitized[key] = sanitizedValue
			end
		end
	end

	return sanitized
end

local function sanitizeAnimationStartTimes(animationStartTimes: any): {[string]: number}
	if type(animationStartTimes) ~= "table" then
		return {}
	end

	local sanitized: {[string]: number} = {}
	for key, value in pairs(animationStartTimes) do
		if type(key) == "string" and type(value) == "number" then
			sanitized[key] = value
		end
	end

	return sanitized
end

local function sanitizeTrackBindings(trackBindings: any): {[string]: string}?
	if type(trackBindings) ~= "table" then
		return nil
	end

	local sanitized: {[string]: string} = {}
	for key, value in pairs(trackBindings) do
		if type(key) == "string" and type(value) == "string" then
			sanitized[key] = value
		end
	end

	return sanitized
end

local function sanitizeReplicationPacket(packet: any): any
	if type(packet) ~= "table" then
		return nil
	end

	local sanitizedLayers = {}
	if type(packet.Layers) == "table" then
		for layerName, layerState in pairs(packet.Layers) do
			if type(layerName) == "string" and type(layerState) == "table" then
				sanitizedLayers[layerName] = {
					Drivers = sanitizeDriverMap(layerState.Drivers),
					AnimationStartTimes = sanitizeAnimationStartTimes(layerState.AnimationStartTimes),
				}
			end
		end
	end

	return {
		Timestamp = if type(packet.Timestamp) == "number" then packet.Timestamp else 0,
		Drivers = sanitizeDriverMap(packet.Drivers),
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
		warn(("FluxaService: failed to require Satset (%s); falling back to RemoteEvent transport"):format(tostring(result)))
		_satset = false
		return nil
	end

	_satset = result
	return _satset
end

local function createDriverValueType(types: any)
	local tagNil = 0
	local tagBoolean = 1
	local tagNumber = 2
	local tagString = 3
	local tagVector2 = 4
	local tagVector3 = 5
	local tagColor3 = 6
	local tagCFrame = 7

	return {
		read = function(bufferValue: buffer, cursor: number)
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
		write = function(bufferValue: buffer, cursor: number, value: any)
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
		getSize = function(value: any)
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

local function createLayerStateType(driverMapType: any, animationStartTimesType: any)
	return {
		read = function(bufferValue: buffer, cursor: number)
			local drivers = driverMapType.read(bufferValue, cursor)
			local nextCursor = cursor + driverMapType.getSize(drivers)
			local animationStartTimes = animationStartTimesType.read(bufferValue, nextCursor)
			return {
				Drivers = drivers,
				AnimationStartTimes = animationStartTimes,
			}
		end,
		write = function(bufferValue: buffer, cursor: number, value: any)
			local stateValue = if type(value) == "table" then value else {}
			local drivers = if type(stateValue.Drivers) == "table" then stateValue.Drivers else {}
			driverMapType.write(bufferValue, cursor, drivers)
			local nextCursor = cursor + driverMapType.getSize(drivers)
			local animationStartTimes = if type(stateValue.AnimationStartTimes) == "table" then stateValue.AnimationStartTimes else {}
			animationStartTimesType.write(bufferValue, nextCursor, animationStartTimes)
		end,
		size = 0,
		getSize = function(value: any)
			local stateValue = if type(value) == "table" then value else {}
			local drivers = if type(stateValue.Drivers) == "table" then stateValue.Drivers else {}
			local animationStartTimes = if type(stateValue.AnimationStartTimes) == "table" then stateValue.AnimationStartTimes else {}
			return driverMapType.getSize(drivers) + animationStartTimesType.getSize(animationStartTimes)
		end,
		isFixed = false,
	}
end

local function _createReplicationPacketType(types: any)
	local driverValueType = createDriverValueType(types)
	local driverMapType = types.map(types.string16, driverValueType)
	local animationStartTimesType = types.map(types.string16, types.f64)
	local layerStateType = createLayerStateType(driverMapType, animationStartTimesType)
	local layersType = types.map(types.string16, layerStateType)
	local trackBindingsType = types.optional(types.map(types.string16, types.string16))

	return {
		read = function(bufferValue: buffer, cursor: number)
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
		write = function(bufferValue: buffer, cursor: number, value: any)
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
		getSize = function(value: any)
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

local function encodeTargetForSatset(target: ResolvedAnimTarget): { TargetType: string, TargetValue: any }?
	if target.TargetType == "player" then
		local player = target.TargetValue
		if typeof(player) == "Instance" and player:IsA("Player") then
			return {
				TargetType = "player",
				TargetValue = player.UserId,
			}
		end
		if type(player) == "number" then
			return {
				TargetType = "player",
				TargetValue = player,
			}
		end
	elseif target.TargetType == "id" then
		if type(target.TargetValue) == "string" then
			return {
				TargetType = "id",
				TargetValue = target.TargetValue,
			}
		end
	elseif target.TargetType == "character" then
		local character = target.TargetValue
		if typeof(character) == "Instance" and character:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(character)
			if player ~= nil then
				return {
					TargetType = "player",
					TargetValue = player.UserId,
				}
			end

			local controller = _characterRegistry[character]
			local id = if controller ~= nil then _controllerIds[controller] else nil
			if type(id) == "string" then
				return {
					TargetType = "id",
					TargetValue = id,
				}
			end
		end
	end

	return nil
end

local function resolveSatsetTarget(targetType: string, targetValue: any): ControllerInstance?
	if targetType == "player" then
		if type(targetValue) ~= "number" then
			return nil
		end

		local player = Players:GetPlayerByUserId(targetValue)
		if player == nil then
			return nil
		end

		return _registry[player]
	elseif targetType == "id" then
		return _registry[targetValue]
	end

	return nil
end

local function ensureSatsetTransport()
	local transport = FluxaSatsetTransport.Get()
	if transport == nil then
		return nil
	end

	if not _satsetInitialized then
		_satsetInitialized = true
		_satset = transport.Satset
		_satsetNPCReplicationPacket = transport.Packets.NPCReplication
		_satsetAnimCmdPacket = transport.Packets.AnimCmd
	end

	if not _satsetListenersBound then
		_satsetListenersBound = true
		if IS_CLIENT then
			_satsetNPCReplicationPacket:listen(function(data)
				if type(data) ~= "table" or type(data.NpcId) ~= "string" then
					return
				end

				local controller = _registry[data.NpcId]
				local applyReplicationPacket = if controller ~= nil then controller.ApplyReplicationPacket else nil
				if controller ~= nil and applyReplicationPacket ~= nil then
					applyReplicationPacket(controller, sanitizeReplicationPacket(data.Packet))
				end
			end)

			_satsetAnimCmdPacket:listen(function(data)
				if type(data) ~= "table" then
					return
				end

				local targetType = data.TargetType
				local targetValue = if targetType == "player" then data.TargetValueUserId else data.TargetValueId
				local controller = resolveSatsetTarget(targetType, targetValue)
				if controller == nil then
					return
				end

				if data.Action == "Play" then
					local play = controller.Play
					if play ~= nil then
						play(controller, data.TrackName, data.FadeTime, data.Weight, data.Speed)
					end
				elseif data.Action == "Stop" then
					local stop = controller.Stop
					if stop ~= nil then
						local trackName = if data.TrackName ~= "" then data.TrackName else nil
						stop(controller, trackName, data.FadeTime)
					end
				end
			end)
		end
	end

	return _satset
end

local function sendNPCPacketToPlayer(player: Player, envelope: NPCPacketEnvelope)
	if ensureSatsetTransport() ~= nil and _satsetNPCReplicationPacket ~= nil then
		_satsetNPCReplicationPacket:fireClient(player, {
			NpcId = envelope.NpcId,
			Packet = sanitizeReplicationPacket(envelope.Packet),
		})
		return
	end

	local remote = findRemote(FluxaSettings.Get("NPC_REPLICATION_REMOTE", "FluxaService_NPCReplication"))
	if remote ~= nil then
		remote:FireClient(player, envelope)
	end
end

local function trySendAnimEnvelopeToPlayer(player: Player, envelope: AnimCmdEnvelope): boolean
	if ensureSatsetTransport() ~= nil and _satsetAnimCmdPacket ~= nil then
		local encodedTarget = encodeTargetForSatset({
			TargetType = envelope.TargetType,
			TargetValue = envelope.TargetValue,
		})
		if encodedTarget ~= nil then
			_satsetAnimCmdPacket:fireClient(player, {
				Action = envelope.Action,
				FadeTime = envelope.FadeTime,
				Speed = envelope.Speed,
				TargetType = encodedTarget.TargetType,
				TargetValueId = if encodedTarget.TargetType == "id" then encodedTarget.TargetValue else nil,
				TargetValueUserId = if encodedTarget.TargetType == "player" then encodedTarget.TargetValue else nil,
				TrackName = envelope.TrackName,
				Weight = envelope.Weight,
			})
			return true
		end
	end

	local remote = getOrCreateRemote(FluxaSettings.Get("ANIM_CMD_REMOTE", "FluxaService_AnimCmd"))
	remote:FireClient(player, envelope)
	return false
end

local function trySendAnimEnvelopeToAll(envelope: AnimCmdEnvelope): boolean
	if ensureSatsetTransport() ~= nil and _satsetAnimCmdPacket ~= nil then
		local encodedTarget = encodeTargetForSatset({
			TargetType = envelope.TargetType,
			TargetValue = envelope.TargetValue,
		})
		if encodedTarget ~= nil then
			_satsetAnimCmdPacket:fireAllClients({
				Action = envelope.Action,
				FadeTime = envelope.FadeTime,
				Speed = envelope.Speed,
				TargetType = encodedTarget.TargetType,
				TargetValueId = if encodedTarget.TargetType == "id" then encodedTarget.TargetValue else nil,
				TargetValueUserId = if encodedTarget.TargetType == "player" then encodedTarget.TargetValue else nil,
				TrackName = envelope.TrackName,
				Weight = envelope.Weight,
			})
			return true
		end
	end

	local remote = getOrCreateRemote(FluxaSettings.Get("ANIM_CMD_REMOTE", "FluxaService_AnimCmd"))
	remote:FireAllClients(envelope)
	return false
end

getOrCreateRemote = function(name: string): RemoteEvent
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	if IS_SERVER then
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = ReplicatedStorage
		return remote
	end

	local found = ReplicatedStorage:WaitForChild(name, 10)
	assert(found ~= nil and found:IsA("RemoteEvent"), ("FluxaService: missing RemoteEvent '%s'"):format(name))
	return found :: RemoteEvent
end

findRemote = function(name: string): RemoteEvent?
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	return nil
end

local function stripAnimationStartTimes(packet: any)
	if packet == nil or packet.Layers == nil then
		return
	end

	for _, layerState in pairs(packet.Layers) do
		layerState.AnimationStartTimes = {}
	end
end

local function disconnectCleanup(id: any)
	local connection: RBXScriptConnection? = _cleanupConnections[id]
	if connection ~= nil then
		connection:Disconnect()
		_cleanupConnections[id] = nil
	end
end

local function getControllerCharacter(controller: ControllerInstance): Model?
	local character = controller.Character :: any
	if character ~= nil and character:IsA("Model") then
		return character
	end
	return nil
end

local function resolveAnimTarget(target: any): ResolvedAnimTarget
	if typeof(target) == "Instance" then
		if target:IsA("Player") then
			return {
				TargetType = "player",
				TargetValue = target,
			}
		elseif target:IsA("Model") then
			return {
				TargetType = "character",
				TargetValue = target,
			}
		end
	end

	if type(target) == "string" then
		return {
			TargetType = "id",
			TargetValue = target,
		}
	end

	error("FluxaService: animation target must be a Player, Model, or string id")
end

local function getControllerForTarget(targetType: AnimTargetType, targetValue: any): ControllerInstance?
	if targetType == "character" then
		local character = targetValue
		if typeof(character) == "Instance" and character:IsA("Model") then
			return _characterRegistry[character]
		end
		return nil
	end

	return _registry[targetValue]
end

local function makePlayRateLimitKey(target: ResolvedAnimTarget, trackName: string, options: PlayOptions?): string
	if options ~= nil and options.RateLimitKey ~= nil and options.RateLimitKey ~= "" then
		return options.RateLimitKey
	end

	return table.concat({
		target.TargetType,
		tostring(target.TargetValue),
		trackName,
	}, "|")
end

local function isRateLimited(target: ResolvedAnimTarget, trackName: string, options: PlayOptions?): boolean
	local window = FluxaSettings.Get("DEFAULT_PLAY_RATE_LIMIT_WINDOW", 0.05)
	if options ~= nil and options.RateLimitWindow ~= nil then
		window = options.RateLimitWindow
	end

	if window <= 0 then
		return false
	end

	local now = os.clock()
	local key = makePlayRateLimitKey(target, trackName, options)
	local last = _playRateLimit[key]
	if last ~= nil and (now - last) < window then
		return true
	end

	_playRateLimit[key] = now
	return false
end

local function shouldReplicateNpcToPlayer(entry: NPCEntry, player: Player, npcId: string): boolean
	if entry.ShouldReplicateToPlayer ~= nil then
		return entry.ShouldReplicateToPlayer(player, npcId, entry.Controller, entry.Character) == true
	end

	local radius = entry.RelevanceRadius
	if radius == nil then
		return true
	end

	local npcCharacter = entry.Character
	local playerCharacter = player.Character
	if npcCharacter == nil or playerCharacter == nil then
		return false
	end

	local npcRoot = npcCharacter:FindFirstChild("HumanoidRootPart")
	local playerRoot = playerCharacter:FindFirstChild("HumanoidRootPart")
	if npcRoot == nil or playerRoot == nil then
		return false
	end

	if not npcRoot:IsA("BasePart") or not playerRoot:IsA("BasePart") then
		return false
	end

	return (npcRoot.Position - playerRoot.Position).Magnitude <= radius
end

function FluxaService.RegisterController(id: any, controller: ControllerInstance)
	assert(id ~= nil, "FluxaService.RegisterController: id cannot be nil")
	assert(controller ~= nil, "FluxaService.RegisterController: controller cannot be nil")

	local previousIdForController = _controllerIds[controller]
	if previousIdForController ~= nil and previousIdForController ~= id then
		FluxaService.UnregisterController(previousIdForController)
	end

	if _registry[id] ~= nil and _registry[id] ~= controller then
		FluxaService.UnregisterController(id)
	end

	local character = getControllerCharacter(controller)
	if character ~= nil then
		local existingController = _characterRegistry[character]
		if existingController ~= nil and existingController ~= controller then
			local existingId = _controllerIds[existingController]
			if existingId ~= nil then
				FluxaService.UnregisterController(existingId)
			else
				for registeredId, registeredController in pairs(_registry) do
					if registeredController == existingController then
						FluxaService.UnregisterController(registeredId)
						break
					end
				end
			end
		end
	end

	disconnectCleanup(id)
	_registry[id] = controller
	_controllerIds[controller] = id

	if character ~= nil then
		_characterRegistry[character] = controller
		_cleanupConnections[id] = character.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				FluxaService.UnregisterController(id)
			end
		end)
	end

	FluxaService.Registered:Fire(id, controller)
end

function FluxaService.UnregisterController(id: any)
	local controller = _registry[id]
	if controller == nil then
		disconnectCleanup(id)
		return
	end

	disconnectCleanup(id)
	_registry[id] = nil
	if _controllerIds[controller] == id then
		_controllerIds[controller] = nil
	end

	local character = getControllerCharacter(controller)
	if character ~= nil and _characterRegistry[character] == controller then
		_characterRegistry[character] = nil
	end

	FluxaService.Unregistered:Fire(id, controller)
end

function FluxaService.GetController(id: any): ControllerInstance?
	return _registry[id]
end

function FluxaService.Get(id: any): ControllerInstance?
	return FluxaService.GetController(id)
end

function FluxaService.GetAllControllers(): {[any]: ControllerInstance}
	local result = {}
	for id, controller in pairs(_registry) do
		if controller ~= nil then
			result[id] = controller
		end
	end
	return result
end

function FluxaService.GetAll(): {[any]: ControllerInstance}
	return FluxaService.GetAllControllers()
end

function FluxaService.GetControllerByCharacter(character: Model): ControllerInstance?
	local direct = _characterRegistry[character]
	if direct ~= nil then
		return direct
	end

	for _, controller in pairs(_registry) do
		if controller ~= nil and controller.Character == character then
			_characterRegistry[character] = controller
			return controller
		end
	end

	return nil
end

function FluxaService.GetDebugSnapshot(): {[string]: any}
	local entries = {}
	for id, controller in pairs(_registry) do
		if controller ~= nil then
			local character = getControllerCharacter(controller)
			table.insert(entries, {
				Id = tostring(id),
				Character = if character ~= nil then character:GetFullName() else nil,
				HasReplicationPacket = controller.GetReplicationPacket ~= nil,
			})
		end
	end

	local npcCount = 0
	for _ in pairs(_npcEntries) do
		npcCount += 1
	end

	return {
		ControllerCount = #entries,
		NPCCount = npcCount,
		Entries = entries,
	}
end

function FluxaService.GetKnownNPCs(): {[string]: Model?}
	return table.clone(_knownNPCs)
end

function FluxaService.DebugDump(): string
	local snapshot = FluxaService.GetDebugSnapshot()
	local lines = {
		("FluxaService controllers=%d npcs=%d"):format(snapshot.ControllerCount, snapshot.NPCCount),
	}

	for _, entry in ipairs(snapshot.Entries) do
		table.insert(lines, ("- id=%s character=%s replication=%s"):format(
			entry.Id,
			tostring(entry.Character),
			tostring(entry.HasReplicationPacket)
		))
	end

	return table.concat(lines, "\n")
end

local function notifyPlayersAboutNpc(eventName: "added" | "removed", npcId: string, entry: NPCEntry?)
	local remote = findRemote(FluxaSettings.Get("NPC_NOTIFY_REMOTE", "FluxaService_NPCNotify"))
	if remote == nil then
		return
	end

	if eventName == "removed" or entry == nil then
		remote:FireAllClients(eventName, npcId)
		return
	end

	local sentToAll = entry.RelevanceRadius == nil and entry.ShouldReplicateToPlayer == nil
	if sentToAll then
		remote:FireAllClients("added", npcId, entry.Character)
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if shouldReplicateNpcToPlayer(entry, player, npcId) then
			remote:FireClient(player, "added", npcId, entry.Character)
		end
	end
end

local _npcPlayerSendAccumulators = {} -- [npcId][player] = {accum = 0, lastRate = 10}
local function getPlayerRoot(player)
	local char = player and player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end
local function getNPCRoot(entry: NPCEntry): BasePart?
	local char = entry.Character
	if char == nil then
		return nil
	end

	local root = char:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end

	return nil
end
local function getLODHz(distance)
	for _, tier in ipairs(FluxaSettings.Get("LOD_TIERS", {})) do
		if distance <= tier.dist then
			return tier.rate
		end
	end
	return 1
end

local function tickNPCReplication(dt: number)
	if ensureSatsetTransport() == nil and findRemote(FluxaSettings.Get("NPC_REPLICATION_REMOTE", "FluxaService_NPCReplication")) == nil then
		return
	end

	for npcId, entry in pairs(_npcEntries) do
		entry.SendAccumulator += dt
		entry.StartTimeAccumulator += dt

		-- Remove global send rate check; handled per-player below

		local controller = entry.Controller
		local getReplicationPacket = if controller ~= nil then controller.GetReplicationPacket else nil
		if controller == nil or getReplicationPacket == nil then
			continue
		end

		local packet = getReplicationPacket(controller, { IncludeTrackBindings = false })
		if packet == nil then
			continue
		end

		local envelope: NPCPacketEnvelope = {
			Authority = "server",
			NpcId = npcId,
			Packet = packet,
		}

		if entry.StartTimeAccumulator < FluxaSettings.Get("NPC_START_TIMES_INTERVAL", 0.25) then
			stripAnimationStartTimes(envelope.Packet)
		else
			entry.StartTimeAccumulator = 0
		end

		for _, player in ipairs(Players:GetPlayers()) do
			if shouldReplicateNpcToPlayer(entry, player, npcId) then
				local npcRoot = getNPCRoot(entry)
				local playerRoot = getPlayerRoot(player)
				local dist = math.huge
				if npcRoot and playerRoot and npcRoot:IsA("BasePart") and playerRoot:IsA("BasePart") then
					dist = (npcRoot.Position - playerRoot.Position).Magnitude
				end
				local rate = getLODHz(dist)
				_npcPlayerSendAccumulators[npcId] = _npcPlayerSendAccumulators[npcId] or {}
				local acc = _npcPlayerSendAccumulators[npcId][player] or {accum = 0, lastRate = rate}
				acc.accum = acc.accum + dt
				acc.lastRate = rate
				if acc.accum >= (1 / rate) then
					acc.accum = 0
					sendNPCPacketToPlayer(player, envelope)
				end
				_npcPlayerSendAccumulators[npcId][player] = acc
			end
		end
	end
end

local function normalizeNPCOptions(characterOrOptions: Model | NPCReplicationOptions?, options: NPCReplicationOptions?): NPCReplicationOptions
	if typeof(characterOrOptions) == "Instance" then
		return {
			Character = characterOrOptions,
			RelevanceRadius = if options ~= nil then options.RelevanceRadius else nil,
			ShouldReplicateToPlayer = if options ~= nil then options.ShouldReplicateToPlayer else nil,
		}
	end

	return characterOrOptions or options or {}
end

function FluxaService.StartNPCReplication(id: string, controller: ControllerInstance, characterOrOptions: Model | NPCReplicationOptions?, options: NPCReplicationOptions?)
	assert(IS_SERVER, "FluxaService.StartNPCReplication must be called from the server")
	assert(type(id) == "string" and id ~= "", "FluxaService.StartNPCReplication: id must be a non-empty string")
	assert(controller ~= nil, "FluxaService.StartNPCReplication: controller cannot be nil")

	ensureSatsetTransport()
	getOrCreateRemote(FluxaSettings.Get("NPC_REPLICATION_REMOTE", "FluxaService_NPCReplication"))
	getOrCreateRemote(FluxaSettings.Get("NPC_NOTIFY_REMOTE", "FluxaService_NPCNotify"))

	local npcOptions = normalizeNPCOptions(characterOrOptions, options)
	local entry: NPCEntry = {
		Controller = controller,
		Character = npcOptions.Character,
		RelevanceRadius = npcOptions.RelevanceRadius,
		ShouldReplicateToPlayer = npcOptions.ShouldReplicateToPlayer,
		SendAccumulator = 0,
		StartTimeAccumulator = 0,
	}

	_npcEntries[id] = entry
	FluxaService.RegisterController(id, controller)
	notifyPlayersAboutNpc("added", id, entry)

	if _npcStepConnection == nil then
		_npcStepConnection = RunService.Heartbeat:Connect(tickNPCReplication)
	end
end

function FluxaService.StopNPCReplication(id: string)
	assert(IS_SERVER, "FluxaService.StopNPCReplication must be called from the server")

	_npcEntries[id] = nil
	FluxaService.UnregisterController(id)
	notifyPlayersAboutNpc("removed", id, nil)

	if next(_npcEntries) == nil and _npcStepConnection ~= nil then
		_npcStepConnection:Disconnect()
		_npcStepConnection = nil
	end
end

local function buildPlayEnvelope(target: ResolvedAnimTarget, trackName: string, options: PlayOptions?): AnimCmdEnvelope
	return {
		Authority = "server",
		Action = "Play",
		TargetType = target.TargetType,
		TargetValue = target.TargetValue,
		TrackName = trackName,
		FadeTime = if options ~= nil
			then if options.FadeInTime ~= nil then options.FadeInTime else options.FadeTime
			else nil,
		Weight = if options ~= nil then options.Weight else nil,
		Speed = if options ~= nil then options.Speed else nil,
	}
end

local function buildStopEnvelope(target: ResolvedAnimTarget, trackName: string?, options: StopOptions?): AnimCmdEnvelope
	return {
		Authority = "server",
		Action = "Stop",
		TargetType = target.TargetType,
		TargetValue = target.TargetValue,
		TrackName = trackName or "",
		FadeTime = if options ~= nil
			then if options.FadeOutTime ~= nil then options.FadeOutTime else options.FadeTime
			else nil,
		Weight = nil,
		Speed = nil,
	}
end

function FluxaService.PlayOnAll(target: any, trackName: string, options: PlayOptions?)
	assert(IS_SERVER, "FluxaService.PlayOnAll must be called from the server")
	local resolved = resolveAnimTarget(target)
	if isRateLimited(resolved, trackName, options) then
		return false
	end
	trySendAnimEnvelopeToAll(buildPlayEnvelope(resolved, trackName, options))
	return true
end

function FluxaService.PlayFor(player: Player, target: any, trackName: string, options: PlayOptions?)
	assert(IS_SERVER, "FluxaService.PlayFor must be called from the server")
	local resolved = resolveAnimTarget(target)
	if isRateLimited(resolved, trackName, options) then
		return false
	end
	trySendAnimEnvelopeToPlayer(player, buildPlayEnvelope(resolved, trackName, options))
	return true
end

function FluxaService.PlayInRange(position: Vector3, radius: number, target: any, trackName: string, options: PlayOptions?)
	assert(IS_SERVER, "FluxaService.PlayInRange must be called from the server")
	local resolved = resolveAnimTarget(target)
	if isRateLimited(resolved, trackName, options) then
		return false
	end

	local envelope = buildPlayEnvelope(resolved, trackName, options)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if root ~= nil and root:IsA("BasePart") and (root.Position - position).Magnitude <= radius then
			trySendAnimEnvelopeToPlayer(player, envelope)
		end
	end
	return true
end

function FluxaService.StopOnAll(target: any, trackName: string?, options: StopOptions?)
	assert(IS_SERVER, "FluxaService.StopOnAll must be called from the server")
	local resolved = resolveAnimTarget(target)
	trySendAnimEnvelopeToAll(buildStopEnvelope(resolved, trackName, options))
end

function FluxaService.StopFor(player: Player, target: any, trackName: string?, options: StopOptions?)
	assert(IS_SERVER, "FluxaService.StopFor must be called from the server")
	local resolved = resolveAnimTarget(target)
	trySendAnimEnvelopeToPlayer(player, buildStopEnvelope(resolved, trackName, options))
end

function FluxaService.StopInRange(position: Vector3, radius: number, target: any, trackName: string?, options: StopOptions?)
	assert(IS_SERVER, "FluxaService.StopInRange must be called from the server")
	local resolved = resolveAnimTarget(target)
	local envelope = buildStopEnvelope(resolved, trackName, options)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if root ~= nil and root:IsA("BasePart") and (root.Position - position).Magnitude <= radius then
			trySendAnimEnvelopeToPlayer(player, envelope)
		end
	end
end

function FluxaService.PlayOnPlayer(player: Player, trackName: string, fadeInTime: number?, weight: number?, speed: number?)
	return FluxaService.PlayOnAll(player, trackName, {
		FadeInTime = fadeInTime,
		Weight = weight,
		Speed = speed,
	})
end

function FluxaService.StopOnPlayer(player: Player, trackName: string?, fadeOutTime: number?)
	FluxaService.StopOnAll(player, trackName, {
		FadeOutTime = fadeOutTime,
	})
end

function FluxaService.PlayOnNPC(id: string, trackName: string, fadeInTime: number?, weight: number?, speed: number?)
	return FluxaService.PlayOnAll(id, trackName, {
		FadeInTime = fadeInTime,
		Weight = weight,
		Speed = speed,
	})
end

function FluxaService.StopOnNPC(id: string, trackName: string?, fadeOutTime: number?)
	FluxaService.StopOnAll(id, trackName, {
		FadeOutTime = fadeOutTime,
	})
end

if IS_CLIENT then
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild(FluxaSettings.Get("NPC_NOTIFY_REMOTE", "FluxaService_NPCNotify"), 10)
		if remote == nil or not remote:IsA("RemoteEvent") then
			return
		end

		remote.OnClientEvent:Connect(function(eventName: string, npcId: string, character: Model?)
			if eventName == "added" then
				_knownNPCs[npcId] = character
				if FluxaService.OnNPCRegistered ~= nil then
					FluxaService.OnNPCRegistered(npcId, character)
				end
			elseif eventName == "removed" then
				_knownNPCs[npcId] = nil
				if FluxaService.OnNPCUnregistered ~= nil then
					FluxaService.OnNPCUnregistered(npcId)
				end
			end
		end)
	end)

	task.spawn(function()
		if ensureSatsetTransport() ~= nil then
			return
		end

		local remote = ReplicatedStorage:WaitForChild(FluxaSettings.Get("NPC_REPLICATION_REMOTE", "FluxaService_NPCReplication"), 10)
		if remote == nil or not remote:IsA("RemoteEvent") then
			return
		end

		remote.OnClientEvent:Connect(function(envelope: NPCPacketEnvelope)
			if envelope == nil or envelope.Authority ~= "server" then
				return
			end

			local controller = _registry[envelope.NpcId]
			local applyReplicationPacket = if controller ~= nil then controller.ApplyReplicationPacket else nil
			if controller ~= nil and applyReplicationPacket ~= nil then
				applyReplicationPacket(controller, envelope.Packet)
			end
		end)
	end)

	task.spawn(function()
		if ensureSatsetTransport() ~= nil then
			return
		end

		local remote = ReplicatedStorage:WaitForChild(FluxaSettings.Get("ANIM_CMD_REMOTE", "FluxaService_AnimCmd"), 10)
		if remote == nil or not remote:IsA("RemoteEvent") then
			return
		end

		remote.OnClientEvent:Connect(function(envelope: AnimCmdEnvelope)
			if envelope == nil or envelope.Authority ~= "server" then
				return
			end

			local controller = getControllerForTarget(envelope.TargetType, envelope.TargetValue)
			if controller == nil then
				return
			end

			if envelope.Action == "Play" then
				local play = controller.Play
				if play ~= nil then
					play(controller, envelope.TrackName, envelope.FadeTime, envelope.Weight, envelope.Speed)
				end
			elseif envelope.Action == "Stop" then
				local stop = controller.Stop
				if stop ~= nil then
					local trackName = if envelope.TrackName ~= "" then envelope.TrackName else nil
					stop(controller, trackName, envelope.FadeTime)
				end
			end
		end)
	end)
end

if IS_SERVER then
	Players.PlayerAdded:Connect(function(player)
		local remote = findRemote(FluxaSettings.Get("NPC_NOTIFY_REMOTE", "FluxaService_NPCNotify"))
		 -- If the remote doesn't exist, there's no need to notify anyone about NPCs
		if remote == nil then
			return
		end

		for npcId, entry in pairs(_npcEntries) do
			if shouldReplicateNpcToPlayer(entry, player, npcId) then
				remote:FireClient(player, "added", npcId, entry.Character)
			end
		end
	end)

	
end

-- workspace.SignalBehavior has to be Immediate for Fluxa to sit in between Humanoid.Animator / AnimationController instances and IKControl instances in the Task Scheduler.

if IS_CLIENT then
	local _bound = false
	local _bindingUpdateConnection: RBXScriptConnection? = nil
	local function stepAllControllers(dt)
		-- Gather all controllers and sort by priority:
		-- 1. LocalPlayer
		-- 2. ReplicatedPlayers
		-- 3. NPCs
		-- 4. LocalOnly animations
		local stepped = {}
		local LocalPlayer = game:GetService("Players").LocalPlayer

		-- Helper to classify controller type
		local function getPriority(controller, id)
			-- LocalPlayer controller
			if controller.Character and LocalPlayer and controller.Character == LocalPlayer.Character then
				return 1
			end
			-- ReplicatedPlayer (any Player except LocalPlayer)
			if controller.Character and controller.Character:IsA("Model") then
				local humanoid = controller.Character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Parent then
					local player = game:GetService("Players"):GetPlayerFromCharacter(controller.Character)
					if player and player ~= LocalPlayer then
						return 2
					end
				end
			end
			-- NPC (registered in _npcEntries)
			if _npcEntries[id] ~= nil then
				return 3
			end
			-- LocalOnly (not a player, not an NPC)
			return 4
		end

		for id, controller in pairs(_registry) do
			if controller and controller.Step then
				table.insert(stepped, {priority = getPriority(controller, id), controller = controller})
			end
		end

		table.sort(stepped, function(a, b)
			return a.priority < b.priority
		end)

		for _, entry in ipairs(stepped) do
			entry.controller:Step(dt)
		end
	end

	function FluxaService.Start()
		if not _bound then
			_bound = true
			_bindingUpdateConnection = RunService.Stepped:Connect(function(_t: number, dt: number) 
				stepAllControllers(dt)
			end)
		end
	end

	function FluxaService.StopLoop()
		if _bound then
			_bound = false
			if _bindingUpdateConnection then
				_bindingUpdateConnection:Disconnect()
				_bindingUpdateConnection = nil
			end
		end
	end
end

return FluxaService