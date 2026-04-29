--!strict
-- FluxaAssetManager: load/store AnimationAssets from AnimationId, Animation instances, or KeyframeSequences.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local AnimationAsset = require(script.Parent.AnimationAsset)
local FluxaTypes = require(script.Parent.FluxaTypes)

local FluxaAssetManager = {}
FluxaAssetManager.__index = FluxaAssetManager

-- Type Imports
type AnimationAssetInstance = FluxaTypes.AnimationAssetInstance
type AnimationAssetSource = FluxaTypes.AnimationAssetSource
type LoadOptions = FluxaTypes.LoadOptions
type LoadManyEntry = FluxaTypes.LoadManyEntry
type AssetManagerInstance = FluxaTypes.AssetManagerInstance

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

local function sourceSignatureFor(source: any): any
	-- Use a stable identity so we can detect "different source for same name"
	-- without retaining strong refs to destroyed instances.
	if typeof(source) == "Instance" then
		return source
	end
	if type(source) == "number" then
		return source
	end
	if type(source) == "string" then
		return source
	end
	if type(source) == "table" then
		return source
	end
	return source
end

function FluxaAssetManager.new(): AssetManagerInstance
	local self = setmetatable({}, FluxaAssetManager) :: any
	self._assets = {} :: {[string]: AnimationAssetInstance}
	-- Keep a weak map of "what source produced this name" so we can surface
	-- mismatches when callers accidentally shadow an asset.  Weak values so
	-- destroyed KeyframeSequences don't leak here.
	self._sources = setmetatable({}, { __mode = "v" }) :: any
	return self :: AssetManagerInstance
end

function FluxaAssetManager.Load(self: AssetManagerInstance, name: string, source: AnimationAssetSource, options: LoadOptions?): AnimationAssetInstance
	assert(type(name) == "string" and name ~= "", "FluxaAssetManager:Load requires a non-empty asset name")
	local sourceAny = source :: any

	if self._assets[name] ~= nil and not shouldOverwriteExisting(options) then
		local previousSource = self._sources[name]
		local newSignature = sourceSignatureFor(sourceAny)
		if previousSource ~= nil and previousSource ~= newSignature then
			local suppress = options ~= nil and options.SuppressMismatchWarning == true
			if not suppress then
				warn(("FluxaAssetManager:Load('%s') ignored a different source because Overwrite=false; the cached asset was kept.  Pass Overwrite=true to replace, or SuppressMismatchWarning=true to silence."):format(name))
			end
		end
		return self._assets[name]
	end

	local asset = buildAssetFromSource(name, source)
	self._assets[name] = asset
	self._sources[name] = sourceSignatureFor(sourceAny)

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

	local recursive = true
	if options ~= nil and options.Recursive ~= nil then
		recursive = options.Recursive == true
	end

	local loaded: {[string]: AnimationAssetInstance} = {}
	local descendants = if recursive then container:GetDescendants() else container:GetChildren()
	for _, child in ipairs(descendants) do
		if child:IsA("Animation") or child:IsA("KeyframeSequence") then
			if loaded[child.Name] ~= nil then
				-- Duplicate asset names across subfolders are almost always a
				-- catalog authoring mistake.  Surface it instead of silently
				-- stomping the earlier entry.
				warn(("FluxaAssetManager:LoadFromContainer: duplicate asset name '%s' at %s"):format(child.Name, child:GetFullName()))
			end
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
	self._sources[name] = nil
end

function FluxaAssetManager.Clear(self: AssetManagerInstance)
	table.clear(self._assets)
	table.clear(self._sources)
end

return FluxaAssetManager
