--!strict
-- FluxaBindingCatalog: shared binding definitions and set composition helpers.

local FluxaTypes = require(script.Parent.FluxaTypes)
type BindingSources = FluxaTypes.BindingSources
type BindingFallbacks = FluxaTypes.BindingFallbacks
type TrackBindings = FluxaTypes.TrackBindings
type BindingSets = FluxaTypes.BindingSets
type BindingLayers = FluxaTypes.BindingLayers
type BindingCatalogDefinition = FluxaTypes.BindingCatalogDefinition
type BindingCatalogInstance = FluxaTypes.BindingCatalogInstance

local FluxaBindingCatalog = {}
FluxaBindingCatalog.__index = FluxaBindingCatalog

function FluxaBindingCatalog.new(definition: BindingCatalogDefinition?): BindingCatalogInstance
	local safeDefinition: BindingCatalogDefinition = definition or {
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

-- Walk the fallback map until we hit a cycle, a missing link, or a self-
-- reference.  Callers can then try each id in order to find one that
-- actually has a loadable source.  Guards against malformed catalogs so a
-- cycle (A -> B -> A) doesn't hang the load path.
function FluxaBindingCatalog.ResolveFallbackChain(self: BindingCatalogInstance, bindingId: string): {string}
	local chain: {string} = { bindingId }
	local visited: {[string]: boolean} = { [bindingId] = true }

	local current = bindingId
	while true do
		local next = self.Fallbacks[current]
		if next == nil or next == "" or visited[next] or next == current then
			break
		end
		table.insert(chain, next)
		visited[next] = true
		current = next
	end

	return chain
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