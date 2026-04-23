--!strict
-- FluxaBindingSetManager: resolve binding ids into assets and apply binding sets to controllers.

local FluxaAssetManager = require(script.Parent.FluxaAssetManager)

local FluxaBindingSetManager = {}
FluxaBindingSetManager.__index = FluxaBindingSetManager

type BindingCatalogLike = {
	GetSource: (self: any, bindingId: string) -> any,
	GetFallbackBinding: (self: any, bindingId: string) -> string?,
	ResolveFallbackChain: (self: any, bindingId: string) -> {string}?,
	GetInitialTrackBindings: (self: any) -> {[string]: string},
	GetSetBindings: (self: any, setName: string, includeInitialBindings: boolean?) -> {[string]: string}?,
	ResolveBindings: (self: any, layerNames: {string}?, includeInitialBindings: boolean?) -> {[string]: string},
}

type TrackConfigMap = {[string]: {[string]: any}}
type ActiveBindingLayer = {
	Name: string,
	Bindings: {[string]: string},
}

export type NewOptions = {
	Catalog: BindingCatalogLike,
	AssetManager: any?,
	SourceContainer: Instance?,
	SourceLookup: {[string]: any}?,
}

export type BindingSetManagerInstance = {
	Catalog: BindingCatalogLike,
	AssetManager: any,

	RegisterSource: (self: BindingSetManagerInstance, name: string, source: any) -> (),
	RegisterSourcesFromContainer: (self: BindingSetManagerInstance, container: Instance) -> (),
	GetOrLoad: (self: BindingSetManagerInstance, bindingId: string) -> (any?, string?),
	AttachController: (self: BindingSetManagerInstance, controller: any) -> (),
	LoadTrack: (self: BindingSetManagerInstance, controller: any, trackName: string, trackConfig: {[string]: any}) -> any?,
	LoadTracks: (self: BindingSetManagerInstance, controller: any, trackConfigs: TrackConfigMap) -> {[string]: any},
	ApplySet: (self: BindingSetManagerInstance, controller: any, setName: string, trackConfigs: TrackConfigMap?) -> {[string]: any},
	SetBindingLayer: (self: BindingSetManagerInstance, layerName: string, bindings: {[string]: string}, controller: any?, trackConfigs: TrackConfigMap?) -> {[string]: any}?,
	SetCatalogLayer: (self: BindingSetManagerInstance, layerName: string, catalogLayerName: string, controller: any?, trackConfigs: TrackConfigMap?) -> {[string]: any}?,
	RemoveBindingLayer: (self: BindingSetManagerInstance, layerName: string, controller: any?, trackConfigs: TrackConfigMap?) -> {[string]: any}?,
	GetResolvedBindings: (self: BindingSetManagerInstance) -> {[string]: string},
	ApplyActiveLayers: (self: BindingSetManagerInstance, controller: any, trackConfigs: TrackConfigMap?) -> {[string]: any},

	_sourceLookup: {[string]: any},
	_bindingLayers: {[string]: ActiveBindingLayer},
	_bindingLayerOrder: {string},
}

function FluxaBindingSetManager.new(options: NewOptions): BindingSetManagerInstance
	assert(options ~= nil and options.Catalog ~= nil, "FluxaBindingSetManager.new requires a Catalog")

	local self = setmetatable({}, FluxaBindingSetManager) :: any
	self.Catalog = options.Catalog
	self.AssetManager = options.AssetManager or FluxaAssetManager.new()
	self._sourceLookup = table.clone(options.SourceLookup or {})
	self._bindingLayers = {}
	self._bindingLayerOrder = {}

	if options.SourceContainer ~= nil then
		self:RegisterSourcesFromContainer(options.SourceContainer)
	end

	return self :: BindingSetManagerInstance
end

local function hasLayer(order: {string}, layerName: string): boolean
	for _, existingLayerName in ipairs(order) do
		if existingLayerName == layerName then
			return true
		end
	end
	return false
end

local function removeLayer(order: {string}, layerName: string)
	for index, existingLayerName in ipairs(order) do
		if existingLayerName == layerName then
			table.remove(order, index)
			return
		end
	end
end

function FluxaBindingSetManager.RegisterSource(self: BindingSetManagerInstance, name: string, source: any)
	self._sourceLookup[name] = source
end

function FluxaBindingSetManager.RegisterSourcesFromContainer(self: BindingSetManagerInstance, container: Instance)
	for _, child in ipairs(container:GetDescendants()) do
		if child:IsA("Animation") or child:IsA("KeyframeSequence") then
			self:RegisterSource(child.Name, child)
		end
	end
end

local function resolveSource(self: BindingSetManagerInstance, bindingId: string)
	local source = self.Catalog:GetSource(bindingId)
	if source == nil then
		return nil
	end

	if type(source) == "string" then
		return self._sourceLookup[source] or source
	end

	return source
end

local function shouldDestroyResolvedSource(self: BindingSetManagerInstance, source: any): boolean
	if typeof(source) ~= "Instance" then
		return false
	end

	for _, registeredSource in pairs(self._sourceLookup) do
		if registeredSource == source then
			return false
		end
	end

	return true
end

local function loadBinding(self: BindingSetManagerInstance, bindingId: string): any?
	local existing = self.AssetManager:Get(bindingId)
	if existing ~= nil then
		return existing
	end

	local source = resolveSource(self, bindingId)
	if source == nil then
		return nil
	end

	local ok, loaded = pcall(function()
		return self.AssetManager:Load(bindingId, source, {
			DestroySourceInstance = shouldDestroyResolvedSource(self, source),
			Overwrite = false,
		})
	end)
	if not ok then
		warn(("Failed to load binding '%s': %s"):format(bindingId, tostring(loaded)))
		return nil
	end

	return loaded
end

function FluxaBindingSetManager.GetOrLoad(self: BindingSetManagerInstance, bindingId: string): (any?, string?)
	-- Prefer the full fallback chain so catalogs can express multi-step
	-- fallbacks (e.g. pistol_reload_tactical -> pistol_reload_generic -> reload_generic).
	-- Single-hop fallback was the original behavior; chains make partially-
	-- populated catalogs viable and cycles in the catalog are clamped by
	-- ResolveFallbackChain itself.
	local chain: {string}
	if self.Catalog.ResolveFallbackChain ~= nil then
		chain = self.Catalog:ResolveFallbackChain(bindingId) or { bindingId }
	else
		chain = { bindingId }
		local fallback = self.Catalog:GetFallbackBinding(bindingId)
		if fallback ~= nil and fallback ~= bindingId then
			table.insert(chain, fallback)
		end
	end

	for _, id in ipairs(chain) do
		local asset = loadBinding(self, id)
		if asset ~= nil then
			return asset, id
		end
	end

	return nil, nil
end

function FluxaBindingSetManager.AttachController(self: BindingSetManagerInstance, controller: any)
	controller:SetTrackBindingResolver(function(_innerController: any, _trackName: string, bindingId: string, _previousBindingId: string?)
		local asset, resolvedBindingId = self:GetOrLoad(bindingId)
		if asset == nil then
			return nil
		end

		return asset, {
			BindingId = resolvedBindingId,
		}
	end)
end

function FluxaBindingSetManager.LoadTrack(self: BindingSetManagerInstance, controller: any, trackName: string, trackConfig: any)
	local bindingId = trackConfig.BindingId
	local asset, resolvedBindingId = self:GetOrLoad(bindingId)
	if asset == nil or resolvedBindingId == nil then
		warn(("Missing binding '%s' for track '%s'"):format(tostring(bindingId), trackName))
		return nil
	end

	local config = table.clone(trackConfig :: {[string]: any})
	config.BindingId = resolvedBindingId

	local preservePhase = false
	if config.PreservePhaseOnSwap ~= nil then
		preservePhase = config.PreservePhaseOnSwap == true
	end
	config.PreservePhaseOnSwap = nil

	if controller:GetTrack(trackName) ~= nil then
		return controller:SetTrackAsset(trackName, asset, {
			BindingId = resolvedBindingId,
			TrackOptions = config.TrackOptions,
			PreservePhase = preservePhase,
		})
	end

	return controller:LoadTrack(trackName, asset, config)
end

function FluxaBindingSetManager.LoadTracks(self: BindingSetManagerInstance, controller: any, trackConfigs: TrackConfigMap): {[string]: any}
	local loadedTracks = {}
	for trackName, trackConfig in pairs(trackConfigs) do
		local track = self:LoadTrack(controller, trackName, trackConfig)
		if track ~= nil then
			loadedTracks[trackName] = track
		end
	end

	return loadedTracks
end

function FluxaBindingSetManager.ApplySet(self: BindingSetManagerInstance, controller: any, setName: string, trackConfigs: TrackConfigMap?): {[string]: any}
	local setBindings = self.Catalog:GetSetBindings(setName, true)
	if setBindings == nil then
		return {}
	end

	local loadedTracks = {}
	for trackName, bindingId in pairs(setBindings) do
		local baseConfig: {[string]: any} = if trackConfigs ~= nil and trackConfigs[trackName] ~= nil then table.clone(trackConfigs[trackName]) else {}
		baseConfig.BindingId = bindingId
		local track = self:LoadTrack(controller, trackName, baseConfig)
		if track ~= nil then
			loadedTracks[trackName] = track
		end
	end

	return loadedTracks
end

function FluxaBindingSetManager.SetBindingLayer(self: BindingSetManagerInstance, layerName: string, bindings: {[string]: string}, controller: any?, trackConfigs: TrackConfigMap?): {[string]: any}?
	self._bindingLayers[layerName] = {
		Name = layerName,
		Bindings = table.clone(bindings),
	}
	if not hasLayer(self._bindingLayerOrder, layerName) then
		table.insert(self._bindingLayerOrder, layerName)
	end

	if controller ~= nil then
		return self:ApplyActiveLayers(controller, trackConfigs)
	end

	return nil
end

function FluxaBindingSetManager.SetCatalogLayer(self: BindingSetManagerInstance, layerName: string, catalogLayerName: string, controller: any?, trackConfigs: TrackConfigMap?): {[string]: any}?
	local bindings = self.Catalog:ResolveBindings({catalogLayerName}, false)
	return self:SetBindingLayer(layerName, bindings, controller, trackConfigs)
end

function FluxaBindingSetManager.RemoveBindingLayer(self: BindingSetManagerInstance, layerName: string, controller: any?, trackConfigs: TrackConfigMap?): {[string]: any}?
	self._bindingLayers[layerName] = nil
	removeLayer(self._bindingLayerOrder, layerName)

	if controller ~= nil then
		return self:ApplyActiveLayers(controller, trackConfigs)
	end

	return nil
end

function FluxaBindingSetManager.GetResolvedBindings(self: BindingSetManagerInstance): {[string]: string}
	local resolved = self.Catalog:GetInitialTrackBindings()
	for _, layerName in ipairs(self._bindingLayerOrder) do
		local layer = self._bindingLayers[layerName]
		if layer ~= nil then
			for trackName, bindingId in pairs(layer.Bindings) do
				resolved[trackName] = bindingId
			end
		end
	end
	return resolved
end

function FluxaBindingSetManager.ApplyActiveLayers(self: BindingSetManagerInstance, controller: any, trackConfigs: TrackConfigMap?): {[string]: any}
	local resolvedBindings = self:GetResolvedBindings()
	local loadedTracks = {}

	-- Delta apply: only touch tracks whose binding actually changes between
	-- the controller's current state and the resolved set.  This is critical
	-- when higher layers are added/removed, otherwise every base-layer track
	-- gets rebuilt (stopping, re-creating, resetting phase) every time any
	-- single track's binding is overridden in a sibling layer.
	local currentBindings: {[string]: string} = {}
	if controller.GetTrackBindings ~= nil then
		currentBindings = controller:GetTrackBindings()
	end

	for trackName, bindingId in pairs(resolvedBindings) do
		if currentBindings[trackName] == bindingId and controller.GetTrack ~= nil and controller:GetTrack(trackName) ~= nil then
			-- Track already bound to the correct binding; keep it.
			loadedTracks[trackName] = controller:GetTrack(trackName)
			continue
		end

		local baseConfig: {[string]: any} = if trackConfigs ~= nil and trackConfigs[trackName] ~= nil then table.clone(trackConfigs[trackName]) else {}
		baseConfig.BindingId = bindingId
		local track = self:LoadTrack(controller, trackName, baseConfig)
		if track ~= nil then
			loadedTracks[trackName] = track
		end
	end

	return loadedTracks
end

return FluxaBindingSetManager