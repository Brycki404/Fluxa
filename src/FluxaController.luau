--!strict
-- FluxaController: configurable animation graph owner for tracks, drivers, blend trees, and layers.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AnimationTrack = require(script.Parent.AnimationTrack)
local UniversalJointWriter = require(script.Parent.UniversalJointWriter)
local FluxaTypes = require(script.Parent.FluxaTypes)
local FluxaSettings = require(script.Parent.FluxaSettings)

-- Type Imports
type ControllerInstance = FluxaTypes.ControllerInstance
type TrackState = FluxaTypes.TrackState
type LayerState = FluxaTypes.LayerState
type LayerReplicationState = FluxaTypes.LayerReplicationState
type DriverReplicationMap = FluxaTypes.DriverReplicationMap
type LayerDriverReplicationMap = FluxaTypes.LayerDriverReplicationMap
type JointMaskInput = FluxaTypes.JointMaskInput
type JointMask = FluxaTypes.JointMask
type LayerBlendMode = FluxaTypes.LayerBlendMode
type ReplicationSeekMode = FluxaTypes.ReplicationSeekMode
type AnyMap = FluxaTypes.AnyMap
type TrackConfig = FluxaTypes.TrackConfig
type TrackSwapOptions = FluxaTypes.TrackSwapOptions
type PoseData = FluxaTypes.PoseData
type NumberMap = FluxaTypes.NumberMap
type NewControllerOptions = FluxaTypes.NewControllerOptions
type ReplicationMode = FluxaTypes.ReplicationMode
type LayerConfig = FluxaTypes.LayerConfig
type ReplicationPacketOptions = FluxaTypes.ReplicationPacketOptions
type ReplicationPacket = FluxaTypes.ReplicationPacket
type BlendTreeResolver = FluxaTypes.BlendTreeResolver
type TrackBindingResolver = FluxaTypes.TrackBindingResolver

local FluxaController = {}
FluxaController.__index = FluxaController

local function clamp01(v: number): number
	return math.clamp(v, 0, 1)
end

local function sortLayerNames(layerNames: {string}, layers: {[string]: LayerState})
	table.sort(layerNames, function(a, b)
		local la = layers[a]
		local lb = layers[b]
		if la.Order == lb.Order then
			return a < b
		end
		return la.Order < lb.Order
	end)
end

local function hasKey(arr: {string}, key: string): boolean
	for _, value in ipairs(arr) do
		if value == key then
			return true
		end
	end
	return false
end

local function removeKey(arr: {string}, key: string)
	for i, value in ipairs(arr) do
		if value == key then
			table.remove(arr, i)
			return
		end
	end
end

local function normalizeMask(mask: JointMaskInput?): JointMask?
	if mask == nil then
		return nil
	end

	local map: JointMask = {}
	for key, value in pairs(mask :: any) do
		if type(key) == "number" then
			if type(value) == "string" then
				map[value] = true
			end
		elseif type(key) == "string" and type(value) == "boolean" and value then
			map[key] = true
		end
	end

	return map
end

local function normalizeBlendMode(mode: LayerBlendMode?): LayerBlendMode
	if mode == "Additive" then
		return "Additive"
	end
	return "Override"
end

local function normalizeReplicationSeekMode(mode: ReplicationSeekMode?): ReplicationSeekMode
	if mode == "Always" then
		return "Always"
	elseif mode == "Never" then
		return "Never"
	end
	return "LoopingOnly"
end

local function getReplicationClock(): number
	local ok, serverNow = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok and type(serverNow) == "number" then
		return serverNow
	end
	return os.clock()
end

local function cloneLayerReplicationState(state: LayerReplicationState): LayerReplicationState
	return {
		Drivers = table.clone(state.Drivers),
		AnimationStartTimes = table.clone(state.AnimationStartTimes),
	}
end

local function createDefaultLayerReplicationState(): LayerReplicationState
	return {
		Drivers = {},
		AnimationStartTimes = {},
	}
end

local function collectRecentAnimationStartTimes(animationStartTimes: {[string]: number}, now: number): {[string]: number}
	local recentAnimationStartTimes: {[string]: number} = {}

	for animationName, startTime in pairs(animationStartTimes) do
		if now - startTime <= FluxaSettings.Get("ANIMATION_START_TIMES_INTERVAL", 0.25) then
			recentAnimationStartTimes[animationName] = startTime
		else
			animationStartTimes[animationName] = nil
		end
	end

	return recentAnimationStartTimes
end

local function collectReplicatedDrivers(drivers: AnyMap, replicationMap: DriverReplicationMap): AnyMap
	local replicated: AnyMap = {}
	for key, value in pairs(drivers) do
		if replicationMap[key] ~= false then
			replicated[key] = value
		end
	end
	return replicated
end

local function cloneLayerDriverReplicationMap(map: LayerDriverReplicationMap?): LayerDriverReplicationMap
	local cloned: LayerDriverReplicationMap = {}
	if map == nil then
		return cloned
	end

	for layerName, driverMap in pairs(map) do
		cloned[layerName] = table.clone(driverMap)
	end

	return cloned
end

local function resolveBindingId(name: string, asset: any, config: TrackConfig?): string
	if config ~= nil and type(config.BindingId) == "string" and config.BindingId ~= "" then
		return config.BindingId
	end

	if asset ~= nil then
		local candidate = (asset :: any).Name
		if type(candidate) == "string" and candidate ~= "" then
			return candidate
		end
	end

	return name
end

local function getTrackSwapPreservePhase(options: TrackSwapOptions?): boolean
	if options == nil then
		return false
	end

	if options.PreservePhase ~= nil then
		return options.PreservePhase == true
	end

	if options.preservePhase ~= nil then
		return options.preservePhase == true
	end

	return false
end

local function getTrackNormalizedPhase(track: any): number?
	local asset = track.Asset
	if asset == nil or asset.GetLength == nil then
		return nil
	end

	local duration = asset:GetLength()
	if type(duration) ~= "number" or duration <= 0 then
		return nil
	end

	local timePosition = if (track :: any).TimePosition ~= nil then (track :: any).TimePosition else (track :: any).Time
	if type(timePosition) ~= "number" then
		return nil
	end

	return math.clamp(timePosition / duration, 0, 1)
end

local function applyTrackNormalizedPhase(track: any, normalizedPhase: number?)
	if normalizedPhase == nil then
		return
	end

	local asset = track.Asset
	if asset == nil or asset.GetLength == nil then
		return
	end

	local duration = asset:GetLength()
	if type(duration) ~= "number" or duration <= 0 then
		return
	end

	local nextTimePosition = math.clamp(normalizedPhase, 0, 1) * duration
	if (track :: any).TimePosition ~= nil then
		(track :: any).TimePosition = nextTimePosition
	end
	if (track :: any).Time ~= nil then
		(track :: any).Time = nextTimePosition
	end
end

local function shouldTrackAutoReplicate(trackState: TrackState): boolean
	if trackState.AutoReplicate then
		return true
	end

	local track = trackState.Track
	if track ~= nil and (track :: any).AutoReplicate == true then
		return true
	end

	return false
end

local function beginTrackPlayback(controller: ControllerInstance, trackName: string, trackState: TrackState, fadeInTime: number?, weight: number?, speed: number?)
	if shouldTrackAutoReplicate(trackState) then
		controller:MarkLayerAnimationStart(trackState.Layer, trackName)
	end

	trackState.Track:Play(fadeInTime, weight, speed)
end

local function blendPoseOverride(target: PoseData, incoming: PoseData, weight: number, mask: JointMask?)
	if weight <= 0 then
		return
	end

	local alpha = clamp01(weight)

	for joint, cf in pairs(incoming) do
		if mask ~= nil and not mask[joint] then
			continue
		end

		local existing = (target :: any)[joint]
		if existing then
			target[joint] = existing:Lerp(cf, alpha)
		else
			-- No lower-layer pose for this joint: still honor layer weight for constructive stacking.
			target[joint] = CFrame.new():Lerp(cf, alpha)
		end
	end
end

local function blendPoseAdditive(target: PoseData, incoming: PoseData, weight: number, mask: JointMask?)
	if weight <= 0 then
		return
	end

	local alpha = clamp01(weight)
	for joint, cf in pairs(incoming) do
		if mask ~= nil and not mask[joint] then
			continue
		end

		local delta = CFrame.new():Lerp(cf, alpha)
		local existing = (target :: any)[joint]
		if existing then
			target[joint] = existing * delta
		else
			target[joint] = delta
		end
	end
end

local function blendLayerTracksIntoPose(controller: ControllerInstance, finalPose: PoseData, layerName: string, layer: LayerState, dt: number)
	for _, trackName in ipairs(controller._trackNames) do
		local track = controller._tracks[trackName]
		if track.Layer ~= layerName or not track.Track.IsPlaying then
			continue
		end

		local logicalWeight = controller._smoothedTrackWeights[trackName] or 0
		local effectiveWeight = logicalWeight * track.Track.Weight
		-- Always update to advance fade weight and animation time, even if we won't blend this frame.
		local sample = track.Track:Update(dt)
		local combinedWeight = clamp01(effectiveWeight * layer.Weight)
		if combinedWeight <= 0 then
			continue
		end

		if layer.BlendMode == "Additive" then
			blendPoseAdditive(finalPose, sample.Transforms, combinedWeight, layer.Mask)
		else
			blendPoseOverride(finalPose, sample.Transforms, combinedWeight, layer.Mask)
		end
	end
end

local function resolveTrackWeights(controller: ControllerInstance, dt: number): NumberMap
	local resolved: NumberMap = {}

	for _, trackName in ipairs(controller._trackNames) do
		local trackState = controller._tracks[trackName]
		if trackState ~= nil and trackState.AutoManage then
			resolved[trackName] = 0
		else
			resolved[trackName] = clamp01(controller._trackTargets[trackName] or 0)
		end
	end

	for _, resolver in pairs(controller._blendTrees) do
		local result = resolver(controller, dt)
		if result then
			for trackName, weight in pairs(result) do
				if controller._tracks[trackName] ~= nil then
					local w = clamp01(weight)
					if w > (resolved[trackName] or 0) then
						resolved[trackName] = w
					end
				end
			end
		end
	end

	return resolved
end

function FluxaController.new(options: NewControllerOptions): ControllerInstance
	assert(options.Character, "FluxaController.new requires Character")

	local self = setmetatable({}, FluxaController) :: any
	self.Character = options.Character
	self.AutoApplyPose = if options.AutoApplyPose ~= nil then options.AutoApplyPose else true
	self.WeightSmoothingSpeed = options.WeightSmoothingSpeed or 12
	self.OnPreStep = options.OnPreStep
	self.OnPostStep = options.OnPostStep
	self.OnPostBlend = options.OnPostBlend

	self._layers = {}
	self._layerNames = {}
	self._tracks = {}
	self._trackNames = {}
	self._trackTargets = {}
	self._smoothedTrackWeights = {}
	self._blendTrees = {}
	self._trackBindings = {}
	self._trackBindingsDirty = true
	self._replicateTrackBindings = options.ReplicateTrackBindings == true
	self._trackBindingResolver = options.TrackBindingResolver
	self._defaultReplicationSeekMode = normalizeReplicationSeekMode(options.ReplicationSeekMode)
	self._appliedReplicationAnimationStartTimes = {}
	self._drivers = table.clone(options.Drivers or options.Params or {})
	self._globalDriverReplication = table.clone(options.GlobalDriverReplication or {})
	self._layerDriverReplication = cloneLayerDriverReplicationMap(options.LayerDriverReplication)
	for key in pairs(self._drivers) do
		if self._globalDriverReplication[key] == nil then
			self._globalDriverReplication[key] = true
		end
	end
	self.Layers = {}
	self._jointMap, self._retarget = UniversalJointWriter.BuildJointMap(self.Character)
	self._updateConnection = nil
	self._replicationMode = options.ReplicationMode or FluxaTypes.ReplicationMode.ServerOwned

	self:AddLayer("Base", { Weight = 1, BlendMode = "Override", Order = 0 })

	if options.Layers then
		for layerName, layerConfig in pairs(options.Layers) do
			self:AddLayer(layerName, layerConfig)
		end
	end

	if options.Tracks then
		for trackName, trackConfig in pairs(options.Tracks) do
			self:LoadTrack(trackName, trackConfig.Asset, trackConfig)
		end
	end

	if options.BlendTrees then
		for treeName, resolver in pairs(options.BlendTrees) do
			self:CreateBlendTree(treeName, resolver)
		end
	end

	if options.AutoStart then
		self:Start()
	end

	return self :: ControllerInstance
end

function FluxaController:SetReplicationMode(mode: ReplicationMode)
	self._replicationMode = mode
end

function FluxaController:GetReplicationMode()
	return self._replicationMode
end

function FluxaController.AddLayer(self: ControllerInstance, name: string, config: LayerConfig?)
	local existing = self._layers[name]
	local nextLayer: LayerState = {
		Weight = if config and config.Weight ~= nil then clamp01(config.Weight) else if existing then existing.Weight else 1,
		BlendMode = normalizeBlendMode(if config and config.BlendMode ~= nil then config.BlendMode else if existing then existing.BlendMode else "Override"),
		Mask = normalizeMask(if config then config.Mask else if existing then existing.Mask else nil),
		Order = if config and config.Order ~= nil then config.Order else if existing then existing.Order else (#self._layerNames + 1),
	}

	self._layers[name] = nextLayer
	if self.Layers[name] == nil then
		self.Layers[name] = createDefaultLayerReplicationState()
	end
	if self._layerDriverReplication[name] == nil then
		self._layerDriverReplication[name] = {}
	end

	if not hasKey(self._layerNames, name) then
		table.insert(self._layerNames, name)
	end
	sortLayerNames(self._layerNames, self._layers)
end

function FluxaController.RemoveLayer(self: ControllerInstance, name: string)
	if name == "Base" then
		return
	end

	self._layers[name] = nil
	self.Layers[name] = nil
	self._layerDriverReplication[name] = nil
	removeKey(self._layerNames, name)

	for _, track in pairs(self._tracks) do
		if track.Layer == name then
			track.Layer = "Base"
		end
	end
end

function FluxaController.SetLayerWeight(self: ControllerInstance, name: string, weight: number)
	local layer = self._layers[name]
	if not layer then
		return
	end
	layer.Weight = clamp01(weight)
end

function FluxaController.SetLayerBlendMode(self: ControllerInstance, name: string, blendMode: LayerBlendMode)
	local layer = self._layers[name]
	if not layer then
		return
	end
	layer.BlendMode = blendMode
end

function FluxaController.SetLayerMask(self: ControllerInstance, name: string, mask: JointMaskInput?)
	local layer = self._layers[name]
	if not layer then
		return
	end
	layer.Mask = normalizeMask(mask)
end

function FluxaController.SetLayerDriver(self: ControllerInstance, layerName: string, paramName: string, value: any)
	if self._layers[layerName] == nil then
		self:AddLayer(layerName, nil)
	end

	local layerState = self.Layers[layerName]
	if layerState == nil then
		layerState = createDefaultLayerReplicationState()
		self.Layers[layerName] = layerState
	end

	layerState.Drivers[paramName] = value
	local replicationMap = self._layerDriverReplication[layerName]
	if replicationMap == nil then
		replicationMap = {}
		self._layerDriverReplication[layerName] = replicationMap
	end
	if replicationMap[paramName] == nil then
		replicationMap[paramName] = true
	end
end

function FluxaController.GetLayerDriver(self: ControllerInstance, layerName: string, paramName: string, fallbackToGlobal: boolean?)
	local layerState = self.Layers[layerName]
	if layerState ~= nil then
		local layerValue = layerState.Drivers[paramName]
		if layerValue ~= nil then
			return layerValue
		end
	end

	if fallbackToGlobal ~= false then
		return self._drivers[paramName]
	end

	return nil
end

function FluxaController.SetLayerDriverReplication(self: ControllerInstance, layerName: string, paramName: string, enabled: boolean)
	if self._layers[layerName] == nil then
		self:AddLayer(layerName, nil)
	end

	local replicationMap = self._layerDriverReplication[layerName]
	if replicationMap == nil then
		replicationMap = {}
		self._layerDriverReplication[layerName] = replicationMap
	end

	replicationMap[paramName] = enabled == true
end

function FluxaController.GetLayerDriverReplication(self: ControllerInstance, layerName: string, paramName: string): boolean
	local replicationMap = self._layerDriverReplication[layerName]
	if replicationMap == nil then
		return true
	end

	return replicationMap[paramName] ~= false
end

function FluxaController.MarkLayerAnimationStart(self: ControllerInstance, layerName: string, animationName: string): number
	if self._layers[layerName] == nil then
		self:AddLayer(layerName, nil)
	end

	local layerState = self.Layers[layerName]
	if layerState == nil then
		layerState = createDefaultLayerReplicationState()
		self.Layers[layerName] = layerState
	end

	local timestamp = getReplicationClock()
	layerState.AnimationStartTimes[animationName] = timestamp
	return timestamp
end

function FluxaController.GetReplicationPacket(self: ControllerInstance, options: ReplicationPacketOptions?): ReplicationPacket
	local now = getReplicationClock()
	local layers: {[string]: LayerReplicationState} = {}
	for layerName, layerState in pairs(self.Layers) do
		local clonedLayerState = cloneLayerReplicationState(layerState)
		clonedLayerState.Drivers = collectReplicatedDrivers(layerState.Drivers, self._layerDriverReplication[layerName] or {})
		clonedLayerState.AnimationStartTimes = collectRecentAnimationStartTimes(layerState.AnimationStartTimes, now)
		layers[layerName] = clonedLayerState
	end

	-- Track bindings are rarely mutated but cost bandwidth if included every
	-- packet (30Hz by default).  Include by explicit request, otherwise only
	-- when something has mutated since the last send.  Projects that haven't
	-- opted into binding replication (ReplicateTrackBindings = false) never
	-- include bindings regardless of the dirty flag so the feature is truly
	-- opt-in.
	local includeBindings = true
	if not self._replicateTrackBindings then
		includeBindings = false
	elseif options ~= nil and options.IncludeTrackBindings ~= nil then
		includeBindings = options.IncludeTrackBindings == true
	else
		includeBindings = self._trackBindingsDirty
	end

	local trackBindings: {[string]: string}? = nil
	if includeBindings then
		trackBindings = table.clone(self._trackBindings)
	end

	return {
		Timestamp = now,
		Drivers = collectReplicatedDrivers(self._drivers, self._globalDriverReplication),
		Layers = layers,
		TrackBindings = trackBindings,
	}
end

function FluxaController.IsTrackBindingsDirty(self: ControllerInstance): boolean
	return self._trackBindingsDirty == true
end

function FluxaController.MarkTrackBindingsSent(self: ControllerInstance)
	self._trackBindingsDirty = false
end

function FluxaController.SetTrackBindingsReplicationEnabled(self: ControllerInstance, enabled: boolean)
	self._replicateTrackBindings = enabled == true
	if enabled then
		self._trackBindingsDirty = true
	end
end

function FluxaController.GetTrackBindingsReplicationEnabled(self: ControllerInstance): boolean
	return self._replicateTrackBindings == true
end

function FluxaController.ApplyReplicationPacket(self: ControllerInstance, packet: ReplicationPacket)
	if packet == nil or type(packet) ~= "table" then
		return
	end

	if type(packet.TrackBindings) == "table" then
		local incomingBindings = packet.TrackBindings :: {[string]: string}

		-- An empty incoming map is almost always a transient sender state
		-- (e.g. a controller that's mid-rebuild during a respawn). Treat it
		-- as "no information" instead of nuking every local track.  When the
		-- sender legitimately has zero bindings they can still send the
		-- individual unload by simply not repopulating -- peers won't
		-- spuriously destroy state during respawns.
		local hasAnyIncoming = next(incomingBindings) ~= nil

		if hasAnyIncoming then
			for trackName in pairs(self._trackBindings) do
				if incomingBindings[trackName] == nil then
					self:UnloadTrack(trackName)
				end
			end
		end

		for trackName, bindingId in pairs(incomingBindings) do
			if type(bindingId) ~= "string" or bindingId == "" then
				continue
			end

			local currentBindingId = self._trackBindings[trackName]
			if currentBindingId == bindingId and self._tracks[trackName] ~= nil then
				continue
			end

			if self._trackBindingResolver ~= nil then
				local asset, trackConfig = self._trackBindingResolver(self, trackName, bindingId, currentBindingId)
				if asset ~= nil then
					local configAny: any = trackConfig or {}
					configAny.BindingId = bindingId
					configAny.Asset = asset

					if self._tracks[trackName] ~= nil then
						-- Live track: swap the asset in-place so peers keep phase,
						-- playback state and smoothed weight across a binding swap
						-- (e.g. gun variant changes, walk->walk_pistol).
						local swapOptions: TrackSwapOptions = {
							PreservePhase = true,
							BindingId = bindingId,
							TrackOptions = configAny.TrackOptions,
						}
						self:SetTrackAsset(trackName, asset, swapOptions)
					else
						self:LoadTrack(trackName, asset, configAny :: TrackConfig)
					end
				else
					warn(("FluxaController: TrackBindingResolver returned nil for track '%s' binding '%s'; unloading"):format(trackName, bindingId))
					self:UnloadTrack(trackName)
				end
			else
				-- No resolver registered: record the incoming binding so peers
				-- can still inspect it (e.g. tooling) but we can't apply a new
				-- asset.  Warn once per mismatch so integration bugs surface.
				if currentBindingId ~= bindingId then
					warn(("FluxaController: received binding '%s' for track '%s' but no TrackBindingResolver is registered"):format(bindingId, trackName))
				end
				self._trackBindings[trackName] = bindingId
				self._trackBindingsDirty = true
			end
		end
	end

	if type(packet.Drivers) == "table" then
		table.clear(self._drivers)
		for key, value in pairs(packet.Drivers) do
			self._drivers[key] = value
		end
	end

	local incomingLayers = packet.Layers
	if incomingLayers == nil then
		return
	end

	local now = getReplicationClock()

	for layerName, incomingState in pairs(incomingLayers) do
		if self._layers[layerName] == nil then
			self:AddLayer(layerName, nil)
		end

		local layerState = self.Layers[layerName]
		if layerState == nil then
			layerState = createDefaultLayerReplicationState()
			self.Layers[layerName] = layerState
		end

		local appliedAnimationStartTimes = self._appliedReplicationAnimationStartTimes[layerName]
		if appliedAnimationStartTimes == nil then
			appliedAnimationStartTimes = {}
			self._appliedReplicationAnimationStartTimes[layerName] = appliedAnimationStartTimes
		end

		table.clear(layerState.Drivers)
		for key, value in pairs(incomingState.Drivers or {}) do
			layerState.Drivers[key] = value
		end
		
		table.clear(layerState.AnimationStartTimes)
		for animationName, startTime in pairs(incomingState.AnimationStartTimes or {}) do
			if type(startTime) == "number" then
				layerState.AnimationStartTimes[animationName] = startTime

				if appliedAnimationStartTimes[animationName] == startTime then
					continue
				end
				appliedAnimationStartTimes[animationName] = startTime

				local trackState = self._tracks[animationName]
				if trackState ~= nil then
					local track = trackState.Track

					if not track.Looped then
						-- Always restart non-looped tracks from the beginning when a new start time arrives.
						if track.IsPlaying then
							track:Stop(0)
						end
						track:Play(0)
						if (track :: any).TimePosition ~= nil then
							(track :: any).TimePosition = 0
						elseif (track :: any).Time ~= nil then
							(track :: any).Time = 0
						end
					else
						if not track.IsPlaying then
							track:Play(0)
						end

						local shouldSeekReplicationTime = false
						if trackState.ReplicationSeekMode == "Always" then
							shouldSeekReplicationTime = true
						elseif trackState.ReplicationSeekMode == "LoopingOnly" then
							shouldSeekReplicationTime = track.Looped
						end

						if shouldSeekReplicationTime then
							local replicatedTime = math.max(0, now - startTime)
							if (track :: any).TimePosition ~= nil then
								(track :: any).TimePosition = replicatedTime
							elseif (track :: any).Time ~= nil then
								(track :: any).Time = replicatedTime
							end
						end
					end
				end
			end
		end
	end
end

function FluxaController.LoadTrack(self: ControllerInstance, name: string, asset: any, config: TrackConfig?)
	assert(asset ~= nil, "FluxaController:LoadTrack requires animation asset")

	local previousTrackState = self._tracks[name]
	local previousTargetWeight = self._trackTargets[name]
	local previousSmoothedWeight = self._smoothedTrackWeights[name]

	if previousTrackState ~= nil then
		self:UnloadTrack(name)
	end

	local rawTrackOptions = if config and config.TrackOptions then config.TrackOptions else nil
	local trackOptions: {[string]: any} = if rawTrackOptions ~= nil then table.clone(rawTrackOptions) else {}
	local track = AnimationTrack.new(asset, trackOptions)

	local layerName = if config and config.Layer then config.Layer else if previousTrackState ~= nil then previousTrackState.Layer else "Base"
	local autoManage = if config and config.AutoManage ~= nil then config.AutoManage else if previousTrackState ~= nil then previousTrackState.AutoManage else true
	local autoReplicate = if config and config.AutoReplicate ~= nil then config.AutoReplicate else if previousTrackState ~= nil then previousTrackState.AutoReplicate else false
	local replicationSeekMode: ReplicationSeekMode = self._defaultReplicationSeekMode
	if previousTrackState ~= nil then
		replicationSeekMode = previousTrackState.ReplicationSeekMode
	end
	if config and config.ReplicationSeekMode ~= nil then
		replicationSeekMode = normalizeReplicationSeekMode(config.ReplicationSeekMode)
	end
	if self._layers[layerName] == nil then
		self:AddLayer(layerName, nil)
	end

	local bindingId = resolveBindingId(name, asset, config)

	local nextTrackState: TrackState = {
		Name = name,
		Layer = layerName,
		Track = track,
		AutoManage = autoManage,
		AutoReplicate = autoReplicate,
		ReplicationSeekMode = replicationSeekMode,
	}
	self._tracks[name] = nextTrackState
	if self._trackBindings[name] ~= bindingId then
		self._trackBindings[name] = bindingId
		self._trackBindingsDirty = true
	end
	local trackInstance = track :: any
	trackInstance.AutoReplicate = autoReplicate

	if not hasKey(self._trackNames, name) then
		table.insert(self._trackNames, name)
	end

	local initialWeight = if config and config.InitialWeight ~= nil
		then config.InitialWeight
		else if previousTargetWeight ~= nil then previousTargetWeight else 0
	self._trackTargets[name] = clamp01(initialWeight)
	self._smoothedTrackWeights[name] = if previousSmoothedWeight ~= nil then clamp01(previousSmoothedWeight) else clamp01(initialWeight)

	if self._tracks[name].AutoManage and self._trackTargets[name] > 0 and self._tracks[name].Track.Looped then
		beginTrackPlayback(self, name, self._tracks[name], track.FadeInTime)
	end

	return track
end

function FluxaController.SetTrackAsset(self: ControllerInstance, name: string, asset: any, options: TrackSwapOptions?)
	assert(asset ~= nil, "FluxaController:SetTrackAsset requires animation asset")

	local previousTrackState = self._tracks[name]
	local preservePhase = getTrackSwapPreservePhase(options)
	local previousNormalizedPhase = nil
	local previousWasPlaying = false

	if previousTrackState ~= nil then
		local previousTrack = previousTrackState.Track
		previousWasPlaying = previousTrack.IsPlaying == true
		if preservePhase then
			previousNormalizedPhase = getTrackNormalizedPhase(previousTrack)
		end
	end

	local trackConfig: TrackConfig = {
		Asset = asset,
		BindingId = if options ~= nil then options.BindingId else nil,
		TrackOptions = if options ~= nil and options.TrackOptions ~= nil then options.TrackOptions else nil,
	}

	local nextTrack = self:LoadTrack(name, asset, trackConfig)
	if previousTrackState == nil then
		return nextTrack
	end

	local nextTrackAny = nextTrack :: any
	if previousWasPlaying and not nextTrack.IsPlaying then
		nextTrack:Play(0)
	end

	if preservePhase then
		applyTrackNormalizedPhase(nextTrackAny, previousNormalizedPhase)
	end

	return nextTrack
end

function FluxaController.UnloadTrack(self: ControllerInstance, name: string)
	local track = self._tracks[name]
	if track then
		if track.Track.IsPlaying then
			track.Track:Stop(0)
		end
		if (track.Track :: any).Destroy ~= nil then
			track.Track:Destroy()
		end
	end

	self._tracks[name] = nil
	removeKey(self._trackNames, name)
	self._trackTargets[name] = nil
	self._smoothedTrackWeights[name] = nil
	if self._trackBindings[name] ~= nil then
		self._trackBindings[name] = nil
		self._trackBindingsDirty = true
	end
end

function FluxaController.SetTrackLayer(self: ControllerInstance, name: string, layerName: string)
	local track = self._tracks[name]
	if not track then
		return
	end
	if self._layers[layerName] == nil then
		self:AddLayer(layerName, nil)
	end
	track.Layer = layerName
end

function FluxaController.SetTrackAutoReplicate(self: ControllerInstance, name: string, enabled: boolean)
	local track = self._tracks[name]
	if not track then
		return
	end

	local value = enabled == true
	track.AutoReplicate = value
	local trackInstance = track.Track :: any
	trackInstance.AutoReplicate = value
end

function FluxaController.GetTrackAutoReplicate(self: ControllerInstance, name: string): boolean
	local track = self._tracks[name]
	if not track then
		return false
	end

	return shouldTrackAutoReplicate(track)
end

function FluxaController.SetTrackWeight(self: ControllerInstance, name: string, weight: number)
	if self._tracks[name] == nil then
		return
	end
	self._trackTargets[name] = clamp01(weight)
end

function FluxaController.GetTrackWeight(self: ControllerInstance, name: string): number
	return self._trackTargets[name] or 0
end

function FluxaController.GetTrack(self: ControllerInstance, name: string): any?
	local state = self._tracks[name]
	return if state then state.Track else nil
end

function FluxaController.SetTrackBindingResolver(self: ControllerInstance, resolver: TrackBindingResolver?)
	self._trackBindingResolver = resolver
end

function FluxaController.GetTrackBinding(self: ControllerInstance, name: string): string?
	return self._trackBindings[name]
end

function FluxaController.GetTrackBindings(self: ControllerInstance): {[string]: string}
	return table.clone(self._trackBindings)
end

function FluxaController.GetPlayingTracks(self: ControllerInstance): { any }
	local result = {}
	for _, trackName in ipairs(self._trackNames) do
		local state = self._tracks[trackName]
		if state and state.Track.Weight > 0 then
			table.insert(result, state.Track)
		end
	end
	return result
end

function FluxaController.CreateBlendTree(self: ControllerInstance, name: string, resolver: BlendTreeResolver)
	self._blendTrees[name] = resolver
end

function FluxaController.RemoveBlendTree(self: ControllerInstance, name: string)
	self._blendTrees[name] = nil
end

function FluxaController.SetGlobalDriver(self: ControllerInstance, key: string, value: any)
	self._drivers[key] = value
	if self._globalDriverReplication[key] == nil then
		self._globalDriverReplication[key] = true
	end
end

function FluxaController.GetGlobalDriver(self: ControllerInstance, key: string)
	return self._drivers[key]
end

function FluxaController.SetGlobalDriverReplication(self: ControllerInstance, key: string, enabled: boolean)
	self._globalDriverReplication[key] = enabled == true
end

function FluxaController.GetGlobalDriverReplication(self: ControllerInstance, key: string): boolean
	return self._globalDriverReplication[key] ~= false
end

function FluxaController.Play(self: ControllerInstance, trackName: string, fadeInTime: number?, weight: number?, speed: number?)
	local track = self._tracks[trackName]
	if not track then
		return
	end

	local targetWeight = if weight ~= nil then clamp01(weight) else 1
	self._trackTargets[trackName] = targetWeight
	if fadeInTime ~= nil and fadeInTime <= 0 then
		self._smoothedTrackWeights[trackName] = targetWeight
	end
	beginTrackPlayback(self, trackName, track, fadeInTime, weight, speed)
end

function FluxaController.Stop(self: ControllerInstance, trackName: string, fadeOutTime: number?)
	local track = self._tracks[trackName]
	if not track then
		return
	end

	self._trackTargets[trackName] = 0
	track.Track:Stop(fadeOutTime)
end

function FluxaController.StopAll(self: ControllerInstance, fadeOutTime: number?)
	for _, name in ipairs(self._trackNames) do
		self:Stop(name, fadeOutTime)
	end
end

function FluxaController.Step(self: ControllerInstance, dt: number): PoseData
	if self.OnPreStep then
		self.OnPreStep(self, dt)
	end

	local resolvedWeights = resolveTrackWeights(self, dt)

	for _, trackName in ipairs(self._trackNames) do
		local track = self._tracks[trackName]
		local target = resolvedWeights[trackName] or 0
		local current = self._smoothedTrackWeights[trackName] or 0
		self._smoothedTrackWeights[trackName] = current + (target - current) * clamp01(dt * self.WeightSmoothingSpeed)

		if track.AutoManage and track.Track.Looped then
			if target <= 0 then
				if track.Track.IsPlaying then
					track.Track:Stop(track.Track.FadeOutTime)
				end
			elseif not track.Track.IsPlaying then
				beginTrackPlayback(self, trackName, track, track.Track.FadeInTime)
			end
		end
	end

	local finalPose: PoseData = {}
	for _, layerName in ipairs(self._layerNames) do
		local layer = self._layers[layerName]
		if layer and layer.Weight > 0 then
			blendLayerTracksIntoPose(self, finalPose, layerName, layer, dt)
		end
	end

	if self.OnPostBlend then
		local postPose = self.OnPostBlend(self, finalPose, dt)
		if postPose then
			finalPose = postPose
		end
	end

	if self.AutoApplyPose then
		UniversalJointWriter.ApplyPose(self._jointMap, self._retarget, finalPose)
	end

	if self.OnPostStep then
		self.OnPostStep(self, dt, finalPose)
	end

	return finalPose
end

function FluxaController.Start(self: ControllerInstance)
	if self._updateConnection then
		return
	end

	-- Allows for existence of Roblox Animator and AnimationController on the same character, stepping after Roblox's built-in animation system to ensure our poses apply on top, but allows for IKControl instances to still run overtop of Fluxa!!! :D
	-- Note! Worskpace.SignalBehavior needs to be Default and not Deferred for IKControls to work with Fluxa!
	self._updateConnection = RunService.Stepped:Connect(function(_t, dt)
		self:Step(dt)
	end)
end

function FluxaController.StopLoop(self: ControllerInstance)
	if self._updateConnection then
		self._updateConnection:Disconnect()
		self._updateConnection = nil
	end
end

function FluxaController.Destroy(self: ControllerInstance)
	self:StopLoop()

	for _, track in pairs(self._tracks) do
		if track.Track.IsPlaying then
			track.Track:Stop(0)
		end
		if (track.Track :: any).Destroy ~= nil then
			track.Track:Destroy()
		end
	end

	table.clear(self._layers)
	table.clear(self._layerNames)
	table.clear(self._tracks)
	table.clear(self._trackNames)
	table.clear(self._trackTargets)
	table.clear(self._smoothedTrackWeights)
	table.clear(self._blendTrees)
	table.clear(self._trackBindings)
	self._trackBindingsDirty = false
	table.clear(self._appliedReplicationAnimationStartTimes)
	table.clear(self._drivers)
	table.clear(self._globalDriverReplication)
	table.clear(self._layerDriverReplication)
	table.clear(self.Layers)
end

return FluxaController
