local Run = game:GetService("RunService")
local Players = game:GetService("Players")
local Rep = game:GetService("ReplicatedStorage")

local modules = Rep.Modules
local conreg = require(modules.ConnectionRegistry)
local signal = require(modules.Signal)
local bts = require(modules.BaseTypes)
local table = require(modules.Table)
local keybinding = require(script.Keybinding)

local module = {}

local _keybinder_string = "Keybinder"
type self = bts.BaseClass &
	{
		Active: bts.optional<boolean>;
	}
local keybinder = table.deepCopy(bts.BaseClass)
local MT = table.deepCopy(bts.BaseClass_MetaTable)
MT.__index = MT
export type Keybinder = typeof(setmetatable({} :: self, MT))

local function setupKeybinder(self: Keybinder, inits: bts.optionalTable)
	local initials = inits --:: InitialSettings
end

export type InitialSettings = {
	
};

keybinder.new = function(inits: bts.optionalTable): Keybinder
	local initials = inits
	if initials then
		initials = initials :: InitialSettings
	end

	local self = bts.BaseClass.new() :: self

	--create self
	self.__type = _keybinder_string
	--self.ConnectionRegistries.EXAMPLE = conreg.new()

	--setup without methods


	--get methods
	setmetatable(self, MT)
	self = self :: Keybinder
	
	--setup with methods
	setupKeybinder(self, initials)

	return self
end

function keybinder.Activate(self): ()
	if not self then return end
	self = self :: Keybinder
	if self.Active == true then return end
	
	self.Active = true
end

function keybinder.Deactivate(self): ()
	if not self then return end
	self = self ::Keybinder
	if self.Active == false then return end
	
	self.Active = false
end

function keybinder.MakeKeybind(self, inits: bts.optionalTable): (keybinding.Keybinding?, number?)
	if not self then return end
	self = self :: Keybinder
	if self.Active == false then return end
	
	local initials = inits :: keybinding.InitialSettings
	local newKeybind = keybinding.Class.new(initials) :: keybinding.Keybinding
	
	table.insert(self.Instances.Dependent, newKeybind)
	local index = table.find(self.Instances.Dependent, newKeybind)
	if index then
		return newKeybind, index
	end
	return newKeybind
end

module.Class_TypeString = _keybinder_string 
module.Class = keybinder
module.Class_MetaTable = MT

return module