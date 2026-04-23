--!strict
-- Example4BindingCatalog: shared binding ids and sources used by all clients.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fluxa = require(ReplicatedStorage.Packages.fluxa)

local Catalog = Fluxa.FluxaBindingCatalog.new({
	Version = "example4-v1",

	Sources = {
		Idle = "Idle",
		Walk = "Walk",
		Run = "Run",
		SlowWalk = "SlowWalk",
		Jump = "Jump",
		Fall = "Fall",
		Land = "Land",
		Climb = "Climb",
		Attack = "Attack",

		RifleIdle = "RifleIdle",
		RifleWalk = "RifleWalk",
		RifleRun = "RifleRun",
		RifleSlowWalk = "RifleSlowWalk",
		RifleAttack = "RifleAttack",
	},

	Fallbacks = {
		RifleIdle = "Idle",
		RifleWalk = "Walk",
		RifleRun = "Run",
		RifleSlowWalk = "SlowWalk",
		RifleAttack = "Attack",
	},

	InitialTrackBindings = {
		Idle = "Idle",
		Walk = "Walk",
		Run = "Run",
		SlowWalk = "SlowWalk",
		Jump = "Jump",
		Fall = "Fall",
		Land = "Land",
		Climb = "Climb",
		Attack = "Attack",
	},

	Sets = {
		Unarmed = {
			Idle = "Idle",
			Walk = "Walk",
			Run = "Run",
			SlowWalk = "SlowWalk",
			Attack = "Attack",
		},
		Rifle = {
			Idle = "RifleIdle",
			Walk = "RifleWalk",
			Run = "RifleRun",
			SlowWalk = "RifleSlowWalk",
			Attack = "RifleAttack",
		},
	},
})

return Catalog