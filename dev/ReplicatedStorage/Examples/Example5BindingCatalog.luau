--!strict
-- Example5BindingCatalog: Example4-style binding catalog using Example3's R15 animation set.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fluxa = require(ReplicatedStorage.Packages.fluxa)

local Catalog = Fluxa.FluxaBindingCatalog.new({
	Version = "example5-v1",

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
		Default = {
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
	},
})

return Catalog