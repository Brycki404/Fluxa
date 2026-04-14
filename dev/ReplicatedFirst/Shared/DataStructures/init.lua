--By Brycki
--Partially ripped from Roblox Creator Hub's Documentation>Engine>Guides

export type StructureType = "Queue" | "Stack" | "PriorityQueue"

local structureTypes: {[number]: StructureType} = {
	"Queue";
	"Stack";
	"PriorityQueue";
}

export type DataStructure = (Queue|Stack|PriorityQueue) & {
	structureTypeIndex: number;
	structureType: StructureType;
}

local structures = {}
structures.__index = structures

function structures.getStructureIndex_FromType(structureType:string?)
	assert(structureType, "No structure type provided.")
	return table.find(structureTypes, structureType)
end

function structures.getStructureType_FromIndex(structureIndex:number?)
	assert(structureIndex, "No structure index provided.")
	return structureTypes[structureIndex]
end

local QueuesModule: ModuleScript = script:FindFirstChild("Queues")
local StacksModule: ModuleScript = script:FindFirstChild("Stacks")
local PriorityQueues: ModuleScript = script:FindFirstChild("PriorityQueues")
local Queue = require(QueuesModule)
local Stack = require(StacksModule)
local PriorityQueue = require(PriorityQueues)

export type Queue = Queue.Queue
export type Stack = Stack.Stack
export type PriorityQueue = PriorityQueue.PriorityQueue

local constructors = {
	Queue.new;
	Stack.new;
	PriorityQueue.new;
}

function structures.new(Id: StructureType|number): DataStructure|nil
	local structureTypeIndex:number?, structureType:string?
	
	if type(Id) == "number" then
		structureType = structures.getStructureType_FromIndex(Id)
		if structureType then
			structureTypeIndex = Id
		end
	elseif type(Id) == "string" then
		structureTypeIndex = structures.getStructureIndex_FromType(Id)
		if structureTypeIndex then
			structureType = Id
		end
	else
		return nil
	end

	if not structureTypeIndex or not structureType then
		warn("Invalid structure type provided. Expected one of the following:", structureTypes)
		return nil
	end

	local success, outcome = pcall(function()
		local new = constructors[structureTypeIndex]()
		new["structureTypeIndex"] = structureTypeIndex
		new["structureType"] = structureType
		return new
	end)
	if success then
		return outcome
	else
		warn(outcome)
	end
	return nil
end

return structures