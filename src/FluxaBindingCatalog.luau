--!strict
-- FluxaBindingCatalog: shared binding definitions and set composition helpers.

local FluxaBindingCatalog = {}
FluxaBindingCatalog.__index = FluxaBindingCatalog

export type BindingSources = {[string]: any}
export type BindingFallbacks = {[string]: string}
export type TrackBindings = {[string]: string}
export type BindingSets = {[string]: TrackBindings}
export type BindingLayers = {[string]: TrackBindings}

export type Definition = {
	Version: string?,
	Sources: BindingSources?,
	Fallbacks: BindingFallbacks?,
	InitialTrackBindings: TrackBindings?,
	Sets: BindingSets?,
	Layers: BindingLayers?,
}

export type BindingCatalogInstance = {
	Version: string,
	Sources: BindingSources,
	Fallbacks: BindingFallbacks,
	InitialTrackBindings: TrackBindings,
	Sets: BindingSets,
	Layers: BindingLayers,

	GetSource: (self: BindingCatalogInstance, bindingId: string) -> any,
	GetFallbackBinding: (self: BindingCatalogInstance, bindingId: string) -> string?,
	GetInitialTrackBinding: (self: BindingCatalogInstance, trackName: string) -> string?,
	GetInitialTrackBindings: (self: BindingCatalogInstance) -> TrackBindings,
	GetSet: (self: BindingCatalogInstance, setName: string) -> TrackBindings?,
	GetSetBindings: (self: BindingCatalogInstance, setName: string, includeInitialBindings: boolean?) -> TrackBindings?,
	GetLayer: (self: BindingCatalogInstance, layerName: string) -> TrackBindings?,
	ResolveBindings: (self: BindingCatalogInstance, layerNames: {string}?, includeInitialBindings: boolean?) -> TrackBindings,
	HasBinding: (self: BindingCatalogInstance, bindingId: string) -> boolean,
}

function FluxaBindingCatalog.new(definition: Definition?): BindingCatalogInstance
	local safeDefinition: Definition = definition or {
		Version = nil,
		Sources = nil,
		Fallbacks = nil,
		InitialTrackBindings = nil,
		Sets = nil,
		Layers = nil,
	}
	local self = setmetatable({}, FluxaBindingCatalog) :: any

	self.Version = safeDefinition.Version or "v1"
	self.Sources = table.clone(safeDefinition.Sources or {})
	self.Fallbacks = table.clone(safeDefinition.Fallbacks or {})
	self.InitialTrackBindings = table.clone(safeDefinition.InitialTrackBindings or {})
	self.Sets = {}
	self.Layers = {}

	for setName, bindings in pairs(safeDefinition.Sets or {}) do
		self.Sets[setName] = table.clone(bindings)
	end

	for layerName, bindings in pairs(safeDefinition.Layers or {}) do
		self.Layers[layerName] = table.clone(bindings)
	end

	return self :: BindingCatalogInstance
end

function FluxaBindingCatalog.GetSource(self: BindingCatalogInstance, bindingId: string)
	return self.Sources[bindingId]
end

function FluxaBindingCatalog.GetFallbackBinding(self: BindingCatalogInstance, bindingId: string): string?
	return self.Fallbacks[bindingId]
end

function FluxaBindingCatalog.GetInitialTrackBinding(self: BindingCatalogInstance, trackName: string): string?
	return self.InitialTrackBindings[trackName]
end

function FluxaBindingCatalog.GetInitialTrackBindings(self: BindingCatalogInstance): TrackBindings
	return table.clone(self.InitialTrackBindings)
end

function FluxaBindingCatalog.GetSet(self: BindingCatalogInstance, setName: string): TrackBindings?
	local bindings = self.Sets[setName]
	if bindings == nil then
		return nil
	end

	return table.clone(bindings)
end

function FluxaBindingCatalog.GetSetBindings(self: BindingCatalogInstance, setName: string, includeInitialBindings: boolean?): TrackBindings?
	local setBindings = self.Sets[setName]
	if setBindings == nil then
		return nil
	end

	local merged = if includeInitialBindings == false then {} else table.clone(self.InitialTrackBindings)
	for trackName, bindingId in pairs(setBindings) do
		merged[trackName] = bindingId
	end

	return merged
end

function FluxaBindingCatalog.GetLayer(self: BindingCatalogInstance, layerName: string): TrackBindings?
	local bindings = self.Layers[layerName]
	if bindings == nil then
		return nil
	end

	return table.clone(bindings)
end

function FluxaBindingCatalog.ResolveBindings(self: BindingCatalogInstance, layerNames: {string}?, includeInitialBindings: boolean?): TrackBindings
	local resolved = if includeInitialBindings == false then {} else table.clone(self.InitialTrackBindings)
	if layerNames == nil then
		return resolved
	end

	for _, layerName in ipairs(layerNames) do
		local layerBindings = self.Layers[layerName] or self.Sets[layerName]
		if layerBindings ~= nil then
			for trackName, bindingId in pairs(layerBindings) do
				resolved[trackName] = bindingId
			end
		end
	end

	return resolved
end

function FluxaBindingCatalog.HasBinding(self: BindingCatalogInstance, bindingId: string): boolean
	return self.Sources[bindingId] ~= nil
end

return FluxaBindingCatalog