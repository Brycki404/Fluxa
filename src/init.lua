local Fluxa = {}

Fluxa.AnimationAsset = require(script.AnimationAsset)
Fluxa.AnimationTrack = require(script.AnimationTrack)
Fluxa.BlendTree = require(script.BlendTree)
Fluxa.Pose = require(script.Pose)
Fluxa.Retargeting = require(script.Retargeting)
Fluxa.UniversalJointWriter = require(script.UniversalJointWriter)
Fluxa.FluxaController = require(script.FluxaController)
Fluxa.FluxaReplicationService = require(script.FluxaReplicationService)

Fluxa.IK = {}
Fluxa.IK.CCD = require(script.IK.CCD)
Fluxa.IK.FABRIK = require(script.IK.FABRIK)
Fluxa.IK.FootPlanting = require(script.IK.FootPlanting)
Fluxa.IK.LookAt = require(script.IK.LookAt)
Fluxa.IK.TwoBoneIK = require(script.IK.TwoBoneIK)

return Fluxa