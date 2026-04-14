--!strict
-- FluxaController: configurable animation graph owner for tracks, drivers, blend trees, and layers.

local RunService = game:GetService("RunService")

local AnimationTrack = require(script.Parent.AnimationTrack)
local UniversalJointWriter = require(script.Parent.UniversalJointWriter)

local FluxaController = {}
FluxaController.__index = FluxaController

type NumberMap = {[string]: number}
type AnyMap = {[string]: any}
type JointMask = {[string]: boolean}
type JointMaskList = {string}
type JointMaskInput = JointMask | JointMaskList
type PoseData = {[string]: CFrame}
type LayerBlendMode = "Override" | "Additive"

export type BlendTreeResolver = (self: ControllerInstance, dt: number) -> NumberMap?

export type LayerConfig = {
	Weight: number?,
	BlendMode: LayerBlendMode?,
	Mask: JointMaskInput?,
	Order: number?,
}

export type TrackConfig = {
	Asset: any,
	TrackOptions: {[string]: any}?,
	PlayerOptions: {[string]: any}?,
	Layer: string?,
	AutoManage: boolean?,
	IsOneShot: boolean?,
	InitialWeight: number?,
}

export type NewOptions = {
	Character: Model,
	AutoApplyPose: boolean?,
	AutoStart: boolean?,
	WeightSmoothingSpeed: number?,
	Drivers: AnyMap?,
	Params: AnyMap?,
	Layers: {[string]: LayerConfig}?,
	Tracks: {[string]: TrackConfig}?,
	BlendTrees: {[string]: BlendTreeResolver}?,
	OnPreStep: ((self: ControllerInstance, dt: number) -> ())?,
	OnPostStep: ((self: ControllerInstance, dt: number, finalPose: PoseData) -> ())?,
	OnPostBlend: ((self: ControllerInstance, finalPose: PoseData, dt: number) -> PoseData?)?,
}

type LayerState = {
	Weight: number,
	BlendMode: LayerBlendMode,
	Mask: JointMask?,
	Order: number,
}

type TrackState = {
	Name: string,
	Layer: string,
	Track: any,
	AutoManage: boolean,
	IsOneShot: boolean,
}

export type ControllerInstance = {
	Character: Model,
	AutoApplyPose: boolean,
	WeightSmoothingSpeed: number,
	OnPreStep: ((self: ControllerInstance, dt: number) -> ())?,
	OnPostStep: ((self: ControllerInstance, dt: number, finalPose: PoseData) -> ())?,
	OnPostBlend: ((self: ControllerInstance, finalPose: PoseData, dt: number) -> PoseData?)?,

	AddLayer: (self: ControllerInstance, name: string, config: LayerConfig?) -> (),
	RemoveLayer: (self: ControllerInstance, name: string) -> (),
	SetLayerWeight: (self: ControllerInstance, name: string, weight: number) -> (),
	SetLayerBlendMode: (self: ControllerInstance, name: string, blendMode: LayerBlendMode) -> (),
	SetLayerMask: (self: ControllerInstance, name: string, mask: JointMaskInput?) -> (),

	AddTrack: (self: ControllerInstance, name: string, asset: any, config: TrackConfig?) -> any,
	RemoveTrack: (self: ControllerInstance, name: string) -> (),
	SetTrackLayer: (self: ControllerInstance, name: string, layerName: string) -> (),
	SetTrackWeight: (self: ControllerInstance, name: string, weight: number) -> (),
	GetTrackWeight: (self: ControllerInstance, name: string) -> number,

	CreateBlendTree: (self: ControllerInstance, name: string, resolver: BlendTreeResolver) -> (),
	RemoveBlendTree: (self: ControllerInstance, name: string) -> (),

	Set: (self: ControllerInstance, key: string, value: any) -> (),
	Get: (self: ControllerInstance, key: string) -> any,
	SetBlend: (self: ControllerInstance, key: string, value: any) -> (),
	SetDriver: (self: ControllerInstance, key: string, value: any) -> (),
	GetDriver: (self: ControllerInstance, key: string) -> any,

	Play: (self: ControllerInstance, trackName: string, fadeInTime: number?) -> (),
	StopTrack: (self: ControllerInstance, trackName: string, fadeOutTime: number?) -> (),
	Stop: (self: ControllerInstance, trackName: string?, fadeOutTime: number?) -> (),

	Step: (self: ControllerInstance, dt: number) -> PoseData,
	Start: (self: ControllerInstance) -> (),
	StopLoop: (self: ControllerInstance) -> (),
	Destroy: (self: ControllerInstance) -> (),

	_layers: {[string]: LayerState},
	_layerNames: {string},
	_tracks: {[string]: TrackState},
	_trackNames: {string},
	_trackTargets: NumberMap,
	_smoothedTrackWeights: NumberMap,
	_blendTrees: {[string]: BlendTreeResolver},
	_drivers: AnyMap,
	_jointMap: {[string]: any},
	_retarget: {[string]: string},
	_updateConnection: RBXScriptConnection?,
}

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

local function blendPoseOverride(target: PoseData, incoming: PoseData, weight: number, mask: JointMask?)
	if weight <= 0 then
		return
	end

	for joint, cf in pairs(incoming) do
		if mask ~= nil and not mask[joint] then
			continue
		end

		local existing = (target :: any)[joint]
		if existing then
			target[joint] = existing:Lerp(cf, clamp01(weight))
		else
			target[joint] = cf
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

local function buildLayerPose(controller: ControllerInstance, layerName: string, dt: number): PoseData
	local layerPose: PoseData = {}
	local hasBase: {[string]: boolean} = {}

	for _, trackName in ipairs(controller._trackNames) do
		local track = controller._tracks[trackName]
		if track.Layer ~= layerName then
			continue
		end

		if not track.Track.Playing then
			continue
		end

		local logicalWeight = controller._smoothedTrackWeights[trackName] or 0
		local effectiveWeight = if logicalWeight > 0 then logicalWeight * track.Track.Weight else track.Track.Weight
		local sample = track.Track:Update(dt)

		if effectiveWeight <= 0 then
			continue
		end

		for joint, cf in pairs(sample.Transforms) do
			if not hasBase[joint] then
				layerPose[joint] = cf
				hasBase[joint] = true
			else
				layerPose[joint] = layerPose[joint]:Lerp(cf, clamp01(effectiveWeight))
			end
		end
	end

	return layerPose
end

local function resolveTrackWeights(controller: ControllerInstance, dt: number): NumberMap
	local resolved: NumberMap = {}

	for _, trackName in ipairs(controller._trackNames) do
		resolved[trackName] = clamp01(controller._trackTargets[trackName] or 0)
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

function FluxaController.new(options: NewOptions): ControllerInstance
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
	self._drivers = table.clone(options.Drivers or options.Params or {})
	self._jointMap, self._retarget = UniversalJointWriter.BuildJointMap(self.Character)
	self._updateConnection = nil

	self:AddLayer("Base", { Weight = 1, BlendMode = "Override", Order = 0 })

	if options.Layers then
		for layerName, layerConfig in pairs(options.Layers) do
			self:AddLayer(layerName, layerConfig)
		end
	end

	if options.Tracks then
		for trackName, trackConfig in pairs(options.Tracks) do
			self:AddTrack(trackName, trackConfig.Asset, trackConfig)
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

function FluxaController.AddLayer(self: ControllerInstance, name: string, config: LayerConfig?)
	local existing = self._layers[name]
	local nextLayer: LayerState = {
		Weight = if config and config.Weight ~= nil then clamp01(config.Weight) else if existing then existing.Weight else 1,
		BlendMode = normalizeBlendMode(if config and config.BlendMode ~= nil then config.BlendMode else if existing then existing.BlendMode else "Override"),
		Mask = normalizeMask(if config then config.Mask else if existing then existing.Mask else nil),
		Order = if config and config.Order ~= nil then config.Order else if existing then existing.Order else (#self._layerNames + 1),
	}

	self._layers[name] = nextLayer
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

function FluxaController.AddTrack(self: ControllerInstance, name: string, asset: any, config: TrackConfig?)
	assert(asset ~= nil, "FluxaController:AddTrack requires animation asset")

	local trackOptions = if config and config.TrackOptions then config.TrackOptions else if config and config.PlayerOptions then config.PlayerOptions else nil
	local track = AnimationTrack.new(asset, trackOptions)

	local layerName = if config and config.Layer then config.Layer else "Base"
	if self._layers[layerName] == nil then
		self:AddLayer(layerName, nil)
	end

	self._tracks[name] = {
		Name = name,
		Layer = layerName,
		Track = track,
		AutoManage = if config and config.AutoManage ~= nil then config.AutoManage else true,
		IsOneShot = if config and config.IsOneShot ~= nil then config.IsOneShot else false,
	}

	if not hasKey(self._trackNames, name) then
		table.insert(self._trackNames, name)
	end

	local initialWeight = if config and config.InitialWeight ~= nil then config.InitialWeight else 0
	self._trackTargets[name] = clamp01(initialWeight)
	self._smoothedTrackWeights[name] = clamp01(initialWeight)

	if self._tracks[name].AutoManage and self._trackTargets[name] > 0 and not self._tracks[name].IsOneShot then
		track:Play(track.FadeInTime)
	end

	return track
end

function FluxaController.RemoveTrack(self: ControllerInstance, name: string)
	local track = self._tracks[name]
	if track and track.Track.Playing then
		track.Track:Stop(0)
	end

	self._tracks[name] = nil
	removeKey(self._trackNames, name)
	self._trackTargets[name] = nil
	self._smoothedTrackWeights[name] = nil
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

function FluxaController.SetTrackWeight(self: ControllerInstance, name: string, weight: number)
	if self._tracks[name] == nil then
		return
	end
	self._trackTargets[name] = clamp01(weight)
end

function FluxaController.GetTrackWeight(self: ControllerInstance, name: string): number
	return self._trackTargets[name] or 0
end

function FluxaController.CreateBlendTree(self: ControllerInstance, name: string, resolver: BlendTreeResolver)
	self._blendTrees[name] = resolver
end

function FluxaController.RemoveBlendTree(self: ControllerInstance, name: string)
	self._blendTrees[name] = nil
end

function FluxaController.Set(self: ControllerInstance, key: string, value: any)
	self._drivers[key] = value
end

function FluxaController.Get(self: ControllerInstance, key: string)
	return self._drivers[key]
end

function FluxaController.SetBlend(self: ControllerInstance, key: string, value: any)
	self:Set(key, value)
end

function FluxaController.SetDriver(self: ControllerInstance, key: string, value: any)
	self:Set(key, value)
end

function FluxaController.GetDriver(self: ControllerInstance, key: string)
	return self:Get(key)
end

function FluxaController.Play(self: ControllerInstance, trackName: string, fadeInTime: number?)
	local track = self._tracks[trackName]
	if not track then
		return
	end

	self._trackTargets[trackName] = 1
	track.Track:Play(fadeInTime)
end

function FluxaController.StopTrack(self: ControllerInstance, trackName: string, fadeOutTime: number?)
	local track = self._tracks[trackName]
	if not track then
		return
	end

	self._trackTargets[trackName] = 0
	track.Track:Stop(fadeOutTime)
end

function FluxaController.Stop(self: ControllerInstance, trackName: string?, fadeOutTime: number?)
	if trackName ~= nil then
		self:StopTrack(trackName, fadeOutTime)
		return
	end

	for _, name in ipairs(self._trackNames) do
		self:StopTrack(name, fadeOutTime)
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

		if track.AutoManage and not track.IsOneShot then
			if target <= 0 then
				if track.Track.Playing then
					track.Track:Stop(track.Track.FadeOutTime)
				end
			elseif not track.Track.Playing then
				track.Track:Play(track.Track.FadeInTime)
			end
		end
	end

	local finalPose: PoseData = {}
	for _, layerName in ipairs(self._layerNames) do
		local layer = self._layers[layerName]
		if layer and layer.Weight > 0 then
			local layerPose = buildLayerPose(self, layerName, dt)
			if layer.BlendMode == "Additive" then
				blendPoseAdditive(finalPose, layerPose, layer.Weight, layer.Mask)
			else
				blendPoseOverride(finalPose, layerPose, layer.Weight, layer.Mask)
			end
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

	self._updateConnection = RunService.RenderStepped:Connect(function(dt)
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
		if track.Track.Playing then
			track.Track:Stop(0)
		end
	end

	table.clear(self._layers)
	table.clear(self._layerNames)
	table.clear(self._tracks)
	table.clear(self._trackNames)
	table.clear(self._trackTargets)
	table.clear(self._smoothedTrackWeights)
	table.clear(self._blendTrees)
	table.clear(self._drivers)
end

return FluxaController
