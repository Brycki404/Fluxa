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
	if not RunService:IsClient() or _clientConnection then
		return
	end

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
