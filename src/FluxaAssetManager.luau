--!strict
-- FluxaAssetManager: load/store AnimationAssets from AnimationId, Animation instances, or KeyframeSequences.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local AnimationAsset = require(script.Parent.AnimationAsset)

local FluxaAssetManager = {}
FluxaAssetManager.__index = FluxaAssetManager

type AnimationAssetInstance = AnimationAsset.AnimationAssetInstance
type AnimationAssetSource = AnimationAssetInstance | number | string | Animation | KeyframeSequence

export type LoadOptions = {
	DestroySourceInstance: boolean?,
	Overwrite: boolean?,
}

export type LoadManyEntry = {
	Name: string,
	Source: AnimationAssetSource,
	Options: LoadOptions?,
}

export type AssetManagerInstance = {
	Load: (self: AssetManagerInstance, name: string, source: AnimationAssetSource, options: LoadOptions?) -> AnimationAssetInstance,
	LoadMany: (self: AssetManagerInstance, entries: {[string]: AnimationAssetSource} | {LoadManyEntry}, options: LoadOptions?) -> {[string]: AnimationAssetInstance},
	LoadFromContainer: (self: AssetManagerInstance, container: Instance, options: LoadOptions?) -> {[string]: AnimationAssetInstance},
	Get: (self: AssetManagerInstance, name: string) -> AnimationAssetInstance?,
	GetAll: (self: AssetManagerInstance) -> {[string]: AnimationAssetInstance},
	Has: (self: AssetManagerInstance, name: string) -> boolean,
	Unload: (self: AssetManagerInstance, name: string) -> (),
	Clear: (self: AssetManagerInstance) -> (),

	_assets: {[string]: AnimationAssetInstance},
}

local function normalizeAnimationIdFromString(value: string): number?
	local numericText = string.match(value, "%d+")
	if numericText == nil then
		return nil
	end

	local id = tonumber(numericText)
	if id == nil or id <= 0 then
		return nil
	end

	return math.floor(id)
end

local function isAnimationAssetInstance(value: any): boolean
	return type(value) == "table" and type((value :: any).Sample) == "function" and type((value :: any).GetLength) == "function"
end

local function resolveAnimationId(source: any): number?
	local sourceType = typeof(source)
	if sourceType == "number" then
		if source <= 0 then
			return nil
		end
		return math.floor(source)
	elseif sourceType == "string" then
		return normalizeAnimationIdFromString(source)
	elseif sourceType == "Instance" and source:IsA("Animation") then
		return normalizeAnimationIdFromString(source.AnimationId)
	end

	return nil
end

local function shouldDestroySourceInstance(source: any, options: LoadOptions?): boolean
	if options ~= nil and options.DestroySourceInstance ~= nil then
		return options.DestroySourceInstance == true
	end

	return typeof(source) == "Instance"
end

local function shouldOverwriteExisting(options: LoadOptions?): boolean
	if options ~= nil and options.Overwrite ~= nil then
		return options.Overwrite == true
	end

	return true
end

local function buildAssetFromAnimationId(animationId: number, assetName: string): AnimationAssetInstance
	local ok, sequence = pcall(function()
		return KeyframeSequenceProvider:GetKeyframeSequenceAsync(animationId)
	end)
	if not ok or sequence == nil then
		error(("FluxaAssetManager: failed to load AnimationId %d for '%s'"):format(animationId, assetName), 3)
	end

	local asset = AnimationAsset.new(sequence, assetName)
	sequence:Destroy()
	return asset
end

local function buildAssetFromSource(name: string, source: AnimationAssetSource): AnimationAssetInstance
	if isAnimationAssetInstance(source) then
		return source :: AnimationAssetInstance
	end

	if typeof(source) == "Instance" and source:IsA("KeyframeSequence") then
		return AnimationAsset.new(source, name)
	end

	local animationId = resolveAnimationId(source)
	if animationId ~= nil then
		return buildAssetFromAnimationId(animationId, name)
	end

	error(("FluxaAssetManager: unsupported source for '%s' (expected AnimationId, Animation, or KeyframeSequence)"):format(name), 3)
end

function FluxaAssetManager.new(): AssetManagerInstance
	local self = setmetatable({}, FluxaAssetManager) :: any
	self._assets = {} :: {[string]: AnimationAssetInstance}
	return self :: AssetManagerInstance
end

function FluxaAssetManager.Load(self: AssetManagerInstance, name: string, source: AnimationAssetSource, options: LoadOptions?): AnimationAssetInstance
	assert(type(name) == "string" and name ~= "", "FluxaAssetManager:Load requires a non-empty asset name")
	local sourceAny = source :: any

	if self._assets[name] ~= nil and not shouldOverwriteExisting(options) then
		return self._assets[name]
	end

	local asset = buildAssetFromSource(name, source)
	self._assets[name] = asset

	if shouldDestroySourceInstance(sourceAny, options) then
		local sourceInstance = sourceAny
		if sourceInstance.Parent ~= nil then
			sourceInstance:Destroy()
		end
	end

	return asset
end

function FluxaAssetManager.LoadMany(self: AssetManagerInstance, entries: any, options: LoadOptions?): {[string]: AnimationAssetInstance}
	local loaded: {[string]: AnimationAssetInstance} = {}

	for key, value in pairs(entries) do
		if type(key) == "string" then
			loaded[key] = self:Load(key, value :: any, options)
		elseif type(key) == "number" and type(value) == "table" then
			local entry = value :: any
			if type(entry.Name) ~= "string" or entry.Name == "" then
				error("FluxaAssetManager:LoadMany entry is missing a valid Name", 2)
			end
			loaded[entry.Name] = self:Load(entry.Name, entry.Source :: AnimationAssetSource, entry.Options or options)
		end
	end

	return loaded
end

function FluxaAssetManager.LoadFromContainer(self: AssetManagerInstance, container: Instance, options: LoadOptions?): {[string]: AnimationAssetInstance}
	assert(typeof(container) == "Instance", "FluxaAssetManager:LoadFromContainer requires a valid container Instance")

	local loaded: {[string]: AnimationAssetInstance} = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Animation") or child:IsA("KeyframeSequence") then
			loaded[child.Name] = self:Load(child.Name, child, options)
		end
	end

	return loaded
end

function FluxaAssetManager.Get(self: AssetManagerInstance, name: string): AnimationAssetInstance?
	return self._assets[name]
end

function FluxaAssetManager.GetAll(self: AssetManagerInstance): {[string]: AnimationAssetInstance}
	return table.clone(self._assets)
end

function FluxaAssetManager.Has(self: AssetManagerInstance, name: string): boolean
	return self._assets[name] ~= nil
end

function FluxaAssetManager.Unload(self: AssetManagerInstance, name: string)
	self._assets[name] = nil
end

function FluxaAssetManager.Clear(self: AssetManagerInstance)
	table.clear(self._assets)
end

return FluxaAssetManager
