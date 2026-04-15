--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fluxa = require(ReplicatedStorage.Packages.fluxa)

-- Requiring the service on server activates packet relay wiring.
local _replicationService = Fluxa.Replication.FluxaReplicationService

return _replicationService
