local Fluxa = {}

-- For now this is alphabetical, but it should probably adhere to some kind of dependency order (e.g. ReplicationService before Controller) to avoid any gotchas with modules trying to require each other in their top-level code. We could also split into multiple init steps if needed to resolve circular dependencies, but ideally the modules should be structured to avoid that.

Fluxa.AnimationAsset = require(script.AnimationAsset)
Fluxa.AnimationTrack = require(script.AnimationTrack)
Fluxa.BlendTree = require(script.BlendTree)
Fluxa.FluxaAssetManager = require(script.FluxaAssetManager)
Fluxa.FluxaBindingCatalog = require(script.FluxaBindingCatalog)
Fluxa.FluxaBindingSetManager = require(script.FluxaBindingSetManager)
Fluxa.FluxaController = require(script.FluxaController)
Fluxa.FluxaReplicationService = require(script.FluxaReplicationService)
Fluxa.FluxaService = require(script.FluxaService)
Fluxa.FluxaSettings = require(script.FluxaSettings)
-- Fluxa.FluxaTypes = require(script.FluxaTypes) -- Doesn't need to be a module since it's just type definitions, and exported types only work through direct require()
Fluxa.Pose = require(script.Pose)
Fluxa.Retargeting = require(script.Retargeting)
Fluxa.Signal = require(script.Signal)
Fluxa.UniversalJointWriter = require(script.UniversalJointWriter)

return Fluxa