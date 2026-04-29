--!strict
-- FluxaTypes: Shared type definitions for Fluxa modules

-- Fluxa Controller

export type NumberMap = {[string]: number}
export type AnyMap = {[string]: any}
export type JointMask = {[string]: boolean}
export type JointMaskList = {string}
export type JointMaskInput = JointMask | JointMaskList
export type PoseData = {[string]: CFrame}
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
export type NewOptions = {
	Character: Model,
	AutoApplyPose: boolean?,
	AutoStart: boolean?,
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
export type ControllerLike = {
	Character: Model?,
	GetReplicationPacket: ((self: any, options: any?) -> any)?,
	ApplyReplicationPacket: ((self: any, packet: any) -> ())?,
	Play: ((self: any, trackName: string, fadeTime: number?, weight: number?, speed: number?) -> ())?,
	Stop: ((self: any, trackName: string?, fadeTime: number?) -> ())?,
}
export type NPCReplicationOptions = {
	Character: Model?,
	RelevanceRadius: number?,
	ShouldReplicateToPlayer: ((player: Player, npcId: string, controller: ControllerLike, character: Model?) -> boolean)?,
}
export type NPCEntry = {
	Controller: ControllerLike,
	Character: Model?,
	RelevanceRadius: number?,
	ShouldReplicateToPlayer: ((player: Player, npcId: string, controller: ControllerLike, character: Model?) -> boolean)?,
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

local module = {}

module.ReplicationMode = {
	LocalOnly = "LocalOnly",
	ClientOwned = "ClientOwned",
	ServerOwned = "ServerOwned",
}

return module