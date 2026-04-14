local Rep = game:GetService("ReplicatedFirst")
local modules = Rep.Shared
local signal = require(modules.Signal)
local conreg = require(modules.ConnectionRegistry)

local module = {}

export type anyList<T> = conreg.anyList<T>
export type optional<T> = conreg.optional<T>

export type anyFunction = ((...any) -> (...any))
export type optionalFunction = optional<anyFunction>
export type anyFunctions = anyList<anyFunction>
export type optionalFunctions = optional<anyFunctions>

export type anyTable = anyList<any>
export type optionalTable = optional<anyTable>
export type anyTables = anyList<anyTable>
export type optionalTables = optional<anyTables>

export type anySignal = RBXScriptSignal | signal.SignalType
export type optionalSignal = optional<anySignal>
export type anySignals = anyList<anySignal>
export type optionalSignals = optional<anySignals>

local _class_string = "BaseClass"
export type baseclass = {
	__type: "BaseClass";
	Instances: {
		Dependent: anyList<Instance>;
		Independent: anyList<Instance>;
	};
	Functions: optionalFunctions;
	Signals: optionalSignals;
	ConnectionRegistries: conreg.optionalConnectionRegistries;
}
local M = {}
local MT = {}
MT.__index = MT
export type BaseClass = typeof(setmetatable({} :: baseclass, MT))

function M.new()
	local class = {} :: baseclass

	--create class
	class.__type = _class_string
	class.Instances = {}
	class.Instances.Dependent = {}
	class.Instances.Independent = {}
	class.Functions = {}
	class.Signals = {} --RBXScriptSignals and signal.SignalTypes
	class.ConnectionRegistries = {} --RBXScriptConnections and signal.ConnectionTypes
	--class.ConnectionRegistries.EXAMPLE = conreg.new()

	--setup without methods	

	--get methods
	setmetatable(class, MT)
	class = class :: BaseClass

	--setup with methods

	return class
end

function MT.RegisterConnections(class, registryIndex: any, connections: conreg.anyConnections): ()
	if class and registryIndex and connections then
		class = class :: BaseClass
		if class.ConnectionRegistries then
			if not class.ConnectionRegistries[registryIndex] then
				class.ConnectionRegistries[registryIndex] = conreg.new()
			end
			for index: any, connection: conreg.anyConnection in pairs(connections) do
				if class.ConnectionRegistries[registryIndex] then
					class.ConnectionRegistries[registryIndex]:Register(index, connection)
				end
			end
		end
	end
end

function MT.Destroy(class)
	if not class then
		return
	end
	class = class :: BaseClass
	class.__type = nil
	--cleanup connections
	if class.ConnectionRegistries then
		for i, connectionRegistry: conreg.ConnectionRegistry in pairs(class.ConnectionRegistries) do
			connectionRegistry:Destroy()
		end
		table.clear(class.ConnectionRegistries)
	end
	class.ConnectionRegistries = nil
	--destroy instances in nil if present
	if class.Instances then
		if class.Instances.Dependent then
			for i, object in pairs(class.Instances.Dependent) do
				if object:IsA("Instance") or (object.Destroy and type(object.Destroy) == "function")  then
					object:Destroy()
				end
			end
			table.clear(class.Instances.Dependent)
		end
		if class.Instances.Independent then
			table.clear(class.Instances.Independent)
		end
	end
	class.Instances = nil
	if class.Functions then
		table.clear(class.Functions)
	end
	class.Functions = nil
	if class.Signals then
		table.clear(class.Signals)
	end
	class.Signals = nil
	--final cleanup stage
	table.clear(class)
	setmetatable(class, nil)
	class = nil
end

module.BaseClass_TypeString = _class_string
module.BaseClass_Constructor = M
module.BaseClass_MetaTable = MT

return module