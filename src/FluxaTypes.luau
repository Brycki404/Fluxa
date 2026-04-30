--!strict
-- FluxaTypes: Shared type definitions for Fluxa modules

-- Pose
export type PoseData = { [string]: CFrame }
export type PoseInstance = {
	Data: PoseData,
	Clone: (self: PoseInstance) -> PoseInstance,
	Lerp: (self: PoseInstance, other: PoseInstance, alpha: number) -> PoseInstance,
	Additive: (self: PoseInstance, addPose: PoseInstance, weight: number) -> PoseInstance,
	ApplyMask: (self: PoseInstance, mask: { [string]: boolean }) -> PoseInstance,
}

-- Universal Joint Writer
export type JointInfo = {
	Joint: Motor6D | Bone | AnimationConstraint,
	Name: string,
	Type: "Motor6D" | "Bone" | "AnimationConstraint",
	Aliases: { string },
}
export type JointMap = { [string]: JointInfo }

-- Retargeting
export type RetargetMap = { [string]: string }
export type RetargetOptions = {
	Scale: number?,
}

-- Fluxa Controller
export type NumberMap = {[string]: number}
export type AnyMap = {[string]: any}
export type JointMask = {[string]: boolean}
export type JointMaskList = {string}
export type JointMaskInput = JointMask | JointMaskList
export type LayerBlendMode = "Override" | "Additive"
export type ReplicationSeekMode = "Always" | "LoopingOnly" | "Never"
export type LayerReplicationState = {
	Drivers: {[string]: any},
	AnimationStartTimes: {[string]: number},
}
export type DriverReplicationMap = {[string]: boolean}
export type LayerDriverReplicationMap = {[string]: DriverReplicationMap}
export type TrackBindingResolver = (self: ControllerInstance, trackName: string, bindingId: string, previousBindingId: string?) -> (any?, TrackConfig?)
export type ReplicationPacket = {
	Timestamp: number,
	Drivers: {[string]: any}?,
	Layers: {[string]: LayerReplicationState},
	TrackBindings: {[string]: string}?,
}
export type ReplicationPacketOptions = {
	IncludeTrackBindings: boolean?,
}
export type ReplicationMode = "LocalOnly" | "ClientOwned" | "ServerOwned"
export type BlendTreeResolver = (self: ControllerInstance, dt: number) -> NumberMap?
export type LayerConfig = {
	Weight: number?,
	BlendMode: LayerBlendMode?,
	Mask: JointMaskInput?,
	Order: number?,
}
export type TrackConfig = {
	Asset: any,
	BindingId: string?,
	TrackOptions: {[string]: any}?,
	PreservePhaseOnSwap: boolean?,
	Layer: string?,
	AutoManage: boolean?,
	AutoReplicate: boolean?,
	InitialWeight: number?,
	ReplicationSeekMode: ReplicationSeekMode?,
}
export type TrackSwapOptions = {
	PreservePhase: boolean?,
	preservePhase: boolean?,
	BindingId: string?,
	TrackOptions: {[string]: any}?,
}
export type NewControllerOptions = {
	Character: Model,
	AutoApplyPose: boolean?,
	WeightSmoothingSpeed: number?,
	ReplicationSeekMode: ReplicationSeekMode?,
	ReplicationMode: ReplicationMode?,
	-- Opt-in for TrackBindings replication.  Projects that don't use the
	-- FluxaBindingCatalog / AssetManager pipeline don't want binding state
	-- crossing the wire at all -- they load tracks by name on both sides
	-- and peers have no resolver to turn incoming binding ids into assets.
	-- Default off so existing setups migrate to the updated controller
	-- without paying bandwidth or emitting "no resolver" warnings.
	ReplicateTrackBindings: boolean?,
	Drivers: AnyMap?,
	Params: AnyMap?,
	GlobalDriverReplication: DriverReplicationMap?,
	LayerDriverReplication: LayerDriverReplicationMap?,
	Layers: {[string]: LayerConfig}?,
	Tracks: {[string]: TrackConfig}?,
	BlendTrees: {[string]: BlendTreeResolver}?,
	TrackBindingResolver: TrackBindingResolver?,
	OnPreStep: ((self: ControllerInstance, dt: number) -> ())?,
	OnPostStep: ((self: ControllerInstance, dt: number, finalPose: PoseData) -> ())?,
	OnPostBlend: ((self: ControllerInstance, finalPose: PoseData, dt: number) -> PoseData?)?,
}
export type LayerState = {
	Weight: number,
	BlendMode: LayerBlendMode,
	Mask: JointMask?,
	Order: number,
}
export type TrackState = {
	Name: string,
	Layer: string,
	Track: any,
	AutoManage: boolean,
	AutoReplicate: boolean,
	ReplicationSeekMode: ReplicationSeekMode,
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
	SetLayerDriver: (self: ControllerInstance, layerName: string, paramName: string, value: any) -> (),
	GetLayerDriver: (self: ControllerInstance, layerName: string, paramName: string, fallbackToGlobal: boolean?) -> any,
	SetLayerDriverReplication: (self: ControllerInstance, layerName: string, paramName: string, enabled: boolean) -> (),
	GetLayerDriverReplication: (self: ControllerInstance, layerName: string, paramName: string) -> boolean,
	MarkLayerAnimationStart: (self: ControllerInstance, layerName: string, animationName: string) -> number,
	GetReplicationPacket: (self: ControllerInstance, options: ReplicationPacketOptions?) -> ReplicationPacket,
	ApplyReplicationPacket: (self: ControllerInstance, packet: ReplicationPacket) -> (),
    SetTrackBindingResolver: (self: ControllerInstance, resolver: TrackBindingResolver?) -> (),
    GetTrackBinding: (self: ControllerInstance, name: string) -> string?,
    GetTrackBindings: (self: ControllerInstance) -> {[string]: string},
    IsTrackBindingsDirty: (self: ControllerInstance) -> boolean,
    MarkTrackBindingsSent: (self: ControllerInstance) -> (),
    SetTrackBindingsReplicationEnabled: (self: ControllerInstance, enabled: boolean) -> (),
    GetTrackBindingsReplicationEnabled: (self: ControllerInstance) -> boolean,

	LoadTrack: (self: ControllerInstance, name: string, asset: any, config: TrackConfig?) -> any,
	SetTrackAsset: (self: ControllerInstance, name: string, asset: any, options: TrackSwapOptions?) -> any,
	UnloadTrack: (self: ControllerInstance, name: string) -> (),
	SetTrackLayer: (self: ControllerInstance, name: string, layerName: string) -> (),
	SetTrackAutoReplicate: (self: ControllerInstance, name: string, enabled: boolean) -> (),
	GetTrackAutoReplicate: (self: ControllerInstance, name: string) -> boolean,
	SetTrackWeight: (self: ControllerInstance, name: string, weight: number) -> (),
	GetTrackWeight: (self: ControllerInstance, name: string) -> number,
	GetTrack: (self: ControllerInstance, name: string) -> any?,
	GetPlayingTracks: (self: ControllerInstance) -> { any },

	CreateBlendTree: (self: ControllerInstance, name: string, resolver: BlendTreeResolver) -> (),
	RemoveBlendTree: (self: ControllerInstance, name: string) -> (),

	Set: (self: ControllerInstance, key: string, value: any) -> (),
	Get: (self: ControllerInstance, key: string) -> any,
	SetBlend: (self: ControllerInstance, key: string, value: any) -> (),
	SetDriver: (self: ControllerInstance, key: string, value: any) -> (),
	GetDriver: (self: ControllerInstance, key: string) -> any,
	SetGlobalDriverReplication: (self: ControllerInstance, key: string, enabled: boolean) -> (),
	GetGlobalDriverReplication: (self: ControllerInstance, key: string) -> boolean,

	Play: (self: ControllerInstance, trackName: string, fadeInTime: number?, weight: number?, speed: number?) -> (),
	StopTrack: (self: ControllerInstance, trackName: string, fadeOutTime: number?) -> (),
	Stop: (self: ControllerInstance, trackName: string?, fadeOutTime: number?) -> (),

	Step: (self: ControllerInstance, dt: number) -> PoseData,
	Start: (self: ControllerInstance) -> (),
	StopLoop: (self: ControllerInstance) -> (),
	Destroy: (self: ControllerInstance) -> (),

	Layers: {[string]: LayerReplicationState},

	_replicationMode: ReplicationMode,
	_layers: {[string]: LayerState},
	_layerNames: {string},
	_tracks: {[string]: TrackState},
	_trackNames: {string},
	_trackTargets: NumberMap,
	_smoothedTrackWeights: NumberMap,
	_blendTrees: {[string]: BlendTreeResolver},
	_trackBindings: {[string]: string},
	_trackBindingsDirty: boolean,
	_replicateTrackBindings: boolean,
	_trackBindingResolver: TrackBindingResolver?,
	_defaultReplicationSeekMode: ReplicationSeekMode,
	_appliedReplicationAnimationStartTimes: {[string]: {[string]: number}},
	_drivers: AnyMap,
	_globalDriverReplication: DriverReplicationMap,
	_layerDriverReplication: LayerDriverReplicationMap,
	_jointMap: {[string]: any},
	_retarget: {[string]: string},
	_updateConnection: RBXScriptConnection?,
}

-- Fluxa Service
export type NPCReplicationOptions = {
	Character: Model?,
	RelevanceRadius: number?,
	ShouldReplicateToPlayer: ((player: Player, npcId: string, controller: ControllerInstance, character: Model?) -> boolean)?,
}
export type NPCEntry = {
	Controller: ControllerInstance,
	Character: Model?,
	RelevanceRadius: number?,
	ShouldReplicateToPlayer: ((player: Player, npcId: string, controller: ControllerInstance, character: Model?) -> boolean)?,
	SendAccumulator: number,
	StartTimeAccumulator: number,
}
export type AnimTargetType = "player" | "character" | "id"
export type ResolvedAnimTarget = {
	TargetType: AnimTargetType,
	TargetValue: any,
}
export type PlayOptions = {
	FadeTime: number?,
	FadeInTime: number?,
	Weight: number?,
	Speed: number?,
	RateLimitWindow: number?,
	RateLimitKey: string?,
}
export type StopOptions = {
	FadeTime: number?,
	FadeOutTime: number?,
}
export type AnimCmdEnvelope = {
	Authority: "server",
	Action: "Play" | "Stop",
	TargetType: AnimTargetType,
	TargetValue: any,
	TrackName: string,
	FadeTime: number?,
	Weight: number?,
	Speed: number?,
}
export type NPCPacketEnvelope = {
	Authority: "server",
	NpcId: string,
	Packet: any,
}

-- Animation Asset
export type AnimationKeyframe = {
	Name: string,
	Time: number;
	Value: CFrame;
}
export type AnimationChannel = {
	Name: string;
	Keyframes: { AnimationKeyframe };
}
export type AnimationEvent = {
	Time: number;
	Name: string;
	Value: string;
}
export type AnimationSample = {
	Transforms: { [string]: CFrame };
}
export type AnimationAssetInstance = {
	Name: string;
	Duration: number;
	Channels: { [string]: {AnimationKeyframe} };
	Events: { AnimationEvent };

	Sample: (self: AnimationAssetInstance, time: number) -> AnimationSample;
	GetLength: (self: AnimationAssetInstance) -> number;
	GetEventsAt: (self: AnimationAssetInstance, time: number, window: number?) -> { AnimationEvent };
}

-- Animation Track
export type SignalType = any
export type AnimationTrackOptions = {
	Speed: number?,
	Looped: boolean?,
	FadeInTime: number?,
	FadeOutTime: number?,
}
export type AnimationTrackInstance = {
	Asset: any,
	Animation: any,
	Length: number,
	Time: number,
	Speed: number,
	Looped: boolean,
	FadeInTime: number,
	FadeOutTime: number,
	Weight: number,
	IsPlaying: boolean,
	TimePosition: number,
	Stopped: SignalType,
	Ended: SignalType,
	DidLoop: SignalType,
	KeyframeReached: SignalType,
	_FadeDir: number,
	_ActiveFadeInTime: number,
	_ActiveFadeOutTime: number,
	_PlayTargetWeight: number,
	_MarkerSignals: { [string]: SignalType },
	_StoppedFired: boolean,
	_EndedFired: boolean,
	Play: (self: AnimationTrackInstance, fadeInTime: number?, weight: number?, speed: number?) -> nil,
	Stop: (self: AnimationTrackInstance, fadeOutTime: number?) -> nil,
	AdjustSpeed: (self: AnimationTrackInstance, speed: number) -> nil,
	GetMarkerReachedSignal: (self: AnimationTrackInstance, markerName: string) -> SignalType,
	GetTimeOfKeyframe: (self: AnimationTrackInstance, keyframeName: string) -> number,
	Destroy: (self: AnimationTrackInstance) -> nil,
	Update: (self: AnimationTrackInstance, dt: number) -> any,
}

-- Fluxa Asset Manager
export type AnimationAssetSource = AnimationAssetInstance | number | string | Animation | KeyframeSequence
export type LoadOptions = {
	DestroySourceInstance: boolean?,
	Overwrite: boolean?,
	-- When true (default), LoadFromContainer walks descendants recursively.
	-- Ignored by Load.
	Recursive: boolean?,
	-- When true, suppress the "ignored source mismatch" warning that fires
	-- when Load is called with Overwrite=false and a different source from
	-- what was previously cached under the same name.
	SuppressMismatchWarning: boolean?,
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
	_sources: {[string]: any},
}

-- Fluxa Binding Catalog
export type BindingSources = {[string]: any}
export type BindingFallbacks = {[string]: string}
export type TrackBindings = {[string]: string}
export type BindingSets = {[string]: TrackBindings}
export type BindingLayers = {[string]: TrackBindings}
export type BindingCatalogDefinition = {
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
	ResolveFallbackChain: (self: BindingCatalogInstance, bindingId: string) -> {string},
	GetInitialTrackBinding: (self: BindingCatalogInstance, trackName: string) -> string?,
	GetInitialTrackBindings: (self: BindingCatalogInstance) -> TrackBindings,
	GetSet: (self: BindingCatalogInstance, setName: string) -> TrackBindings?,
	GetSetBindings: (self: BindingCatalogInstance, setName: string, includeInitialBindings: boolean?) -> TrackBindings?,
	GetLayer: (self: BindingCatalogInstance, layerName: string) -> TrackBindings?,
	ResolveBindings: (self: BindingCatalogInstance, layerNames: {string}?, includeInitialBindings: boolean?) -> TrackBindings,
	HasBinding: (self: BindingCatalogInstance, bindingId: string) -> boolean,
}

-- Fluxa Binding Set Manager
export type TrackConfigMap = {[string]: {[string]: any}}
export type ActiveBindingLayer = {
	Name: string,
	Bindings: {[string]: string},
}
export type BindingSetManagerNewOptions = {
	Catalog: BindingCatalogInstance,
	AssetManager: any?,
	SourceContainer: Instance?,
	SourceLookup: {[string]: any}?,
}
export type BindingSetManagerInstance = {
	Catalog: BindingCatalogInstance,
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


local module = {}

-- Enums
module.ReplicationMode = {
	LocalOnly = "LocalOnly",
	ClientOwned = "ClientOwned",
	ServerOwned = "ServerOwned",
}

return module