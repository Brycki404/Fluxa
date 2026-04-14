local Run = game:GetService("RunService")
local Players = game:GetService("Players")
local Rep = game:GetService("ReplicatedStorage")
local RepFirst = game:GetService("ReplicatedFirst")
local ContextActionService = game:GetService("ContextActionService")
local UIS = game:GetService("UserInputService")

local modules = RepFirst.Shared
local conreg = require(modules.ConnectionRegistry)
local signal = require(modules.Signal)
local bts = require(modules.BaseTypes)
local table = require(modules.Table)

local module = {}

local _keybinding_string = "Keybinding"
type self = {
	__type: string?;
	ActionString: string; --the name of the action connected to the keybind
	Keycode: (Enum.KeyCode | Enum.UserInputType)?; --the actual list of keycodes with settings like Hold, HoldOrder, or SequenceOrder
	Function: bts.optionalFunction; --the function executed after the signal
	Signal: bts.optionalSignal; --the signal the function is being connected to
	Connection: conreg.optionalConnection; --the connection made between the signal and the function
	Enabled: boolean;
}
local keybinding = {}
local MT = {}
MT.__index = MT
export type Keybinding = typeof(setmetatable({} :: self, MT))
export type InitialSettings = {
	ActionString: string?;
	Keycode: (Enum.KeyCode | Enum.UserInputType)?;
	Function: bts.optionalFunction?;
	Enabled: boolean?;
}

local function getStringFromKeycode(keycode: (Enum.KeyCode | Enum.UserInputType)?)
	local compiled = ""
	local name = keycode and keycode.Name or ""
	compiled = compiled..name
	return compiled
end

local function setupKeybinding(self: Keybinding, inits: bts.optionalTable)
	local initials = inits :: InitialSettings	
	
end

function keybinding.new(inits: bts.optionalTable): Keybinding
	local initials = inits :: InitialSettings

	local self = {} :: self

	--create self
	self.__type = _keybinding_string
	self.ActionString = initials.ActionString
	self.Keycode = initials.Keycode
	self.Function = initials.Function
	self.Enabled = initials.Enabled or false;
	--self.ConnectionRegistries.EXAMPLE = conreg.new()

	--setup without methods


	--get methods
	setmetatable(self, MT)
	self = self :: Keybinding

	--setup with methods
	setupKeybinding(self, initials)

	return self
end

function MT.Destroy(self): ()
	if not self then return end
	self = self :: Keybinding

	--kill type
	self.__type = nil
	--cleanup connections
	local connection = self.Connection
	if connection then
		if connection.Connected then
			connection:Disconnect()
		end
	end
	self.Connection = nil
	--cleanup
	self.ActionString = nil
	self.Keycode = nil
	self.Signal = nil
	self.Function = nil
	--final cleanup stage
	table.clear(self)
	setmetatable(self, nil)
	self = nil
end

module.Class_TypeString = _keybinding_string 
module.Class = keybinding
module.Class_MetaTable = MT

return module