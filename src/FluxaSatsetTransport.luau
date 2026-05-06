--!nonstrict

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Workspace = game:GetService("Workspace")

local FluxaSettings = require(script.Parent.FluxaSettings)

local FluxaSatsetTransport = {}

local _satset = nil
local _initialized = false
local _transport = nil
local _satsetDemoEnabledAtStartup = FluxaSettings.Get("SATSET_ENABLED", false) == true

local function isSatsetDemoEnabled()
	return _satsetDemoEnabledAtStartup
end

local function tryGetSatset()
	if _satset == false then
		return nil
	end

	if _satset ~= nil then
		return _satset
	end

	local satsetModule = script.Parent:FindFirstChild("Satset_v0.2.0")
	if satsetModule == nil or not satsetModule:IsA("ModuleScript") then
		_satset = false
		return nil
	end

	local ok, result = pcall(require, satsetModule)
	if not ok then
		warn(("FluxaSatsetTransport: failed to require Satset (%s)"):format(tostring(result)))
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

local function createReplicationPacketType(types)
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
			local packetValue = if type(value) == "table" then value else {
				Timestamp = 0,
				Drivers = {},
				Layers = {},
				TrackBindings = nil,
			}

			types.f64.write(bufferValue, cursor, if type(packetValue.Timestamp) == "number" then packetValue.Timestamp else 0)
			local nextCursor = cursor + types.f64.getSize(if type(packetValue.Timestamp) == "number" then packetValue.Timestamp else 0)
			driverMapType.write(bufferValue, nextCursor, if type(packetValue.Drivers) == "table" then packetValue.Drivers else {})
			nextCursor += driverMapType.getSize(if type(packetValue.Drivers) == "table" then packetValue.Drivers else {})
			layersType.write(bufferValue, nextCursor, if type(packetValue.Layers) == "table" then packetValue.Layers else {})
			nextCursor += layersType.getSize(if type(packetValue.Layers) == "table" then packetValue.Layers else {})
			trackBindingsType.write(bufferValue, nextCursor, if type(packetValue.TrackBindings) == "table" then packetValue.TrackBindings else nil)
		end,
		size = 0,
		getSize = function(value)
			local packetValue = if type(value) == "table" then value else nil
			if packetValue == nil then
				return types.f64.getSize(0)
					+ driverMapType.getSize({})
					+ layersType.getSize({})
					+ trackBindingsType.getSize(nil)
			end

			local timestamp = if type(packetValue.Timestamp) == "number" then packetValue.Timestamp else 0
			local drivers = if type(packetValue.Drivers) == "table" then packetValue.Drivers else {}
			local layers = if type(packetValue.Layers) == "table" then packetValue.Layers else {}
			local trackBindings = if type(packetValue.TrackBindings) == "table" then packetValue.TrackBindings else nil
			return types.f64.getSize(timestamp)
				+ driverMapType.getSize(drivers)
				+ layersType.getSize(layers)
				+ trackBindingsType.getSize(trackBindings)
		end,
		isFixed = false,
	}
end

function FluxaSatsetTransport.Get()
	if not isSatsetDemoEnabled() then
		return nil
	end

	if _transport ~= nil then
		return _transport
	end

	local satset = tryGetSatset()
	if satset == nil then
		return nil
	end

	if not _initialized then
		_initialized = true
		local ok, result = pcall(function()
			satset.start({
				guard = {
					maxTokens = FluxaSettings.Get("SATSET_GUARD_MAX_TOKENS", 60),
					refillRate = FluxaSettings.Get("SATSET_GUARD_REFILL_RATE", 30),
					studioBypass = FluxaSettings.Get("SATSET_GUARD_STUDIO_BYPASS", true),
				},
			})

			local types = satset.Types
			local replicationPacketType = createReplicationPacketType(types)
			local animTargetType = types.enum({ "player", "id" })
			local actionType = types.enum({ "Play", "Stop" })

			_transport = {
				Satset = satset,
				Packets = {
					ClientReplication = satset.definePacket({
						name = FluxaSettings.Get("SATSET_CLIENT_PACKET_NAME", "FluxaReplication_ClientToServer"),
						schema = { Payload = replicationPacketType },
						reliable = FluxaSettings.Get("SATSET_RELIABLE", true),
					}),
					ServerReplication = satset.definePacket({
						name = FluxaSettings.Get("SATSET_SERVER_PACKET_NAME", "FluxaReplication_ServerToClient"),
						schema = {
							Payload = replicationPacketType,
							SenderUserId = types.u32,
						},
						reliable = FluxaSettings.Get("SATSET_RELIABLE", true),
					}),
					NPCReplication = satset.definePacket({
						name = FluxaSettings.Get("SATSET_FLUXA_NPC_PACKET_NAME", "FluxaService_NPCReplication"),
						schema = {
							NpcId = types.string16,
							Packet = replicationPacketType,
						},
						reliable = FluxaSettings.Get("SATSET_RELIABLE", true),
					}),
					AnimCmd = satset.definePacket({
						name = FluxaSettings.Get("SATSET_FLUXA_ANIM_PACKET_NAME", "FluxaService_AnimCmd"),
						schema = {
							Action = actionType,
							FadeTime = types.optional(types.f64),
							Speed = types.optional(types.f64),
							TargetType = animTargetType,
							TargetValueId = types.optional(types.string16),
							TargetValueUserId = types.optional(types.u32),
							TrackName = types.string16,
							Weight = types.optional(types.f64),
						},
						reliable = FluxaSettings.Get("SATSET_RELIABLE", true),
					}),
				},
			}
		end)

		if not ok then
			warn(("FluxaSatsetTransport: failed to initialize (%s)"):format(tostring(result)))
			_satset = false
			_initialized = false
			_transport = nil
			return nil
		end
	end

	return _transport
end

return FluxaSatsetTransport