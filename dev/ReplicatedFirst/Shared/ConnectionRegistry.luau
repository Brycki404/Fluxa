--!nonstrict
local modules = script.Parent
local signal = require(modules.Signal)
local datastructures = require(modules.DataStructures)

export type anyList<T> = {[any]: T}
export type optional<T> = T?

export type anyConnection = RBXScriptConnection | signal.ConnectionType
export type optionalConnection = optional<anyConnection>
export type anyConnections = anyList<anyConnection>
export type optionalConnections = optional<anyConnections>

type self = {
	__type: string;
	_length: number;
	_registrars: anyConnections;
	_queue: datastructures.Queue;
	_tackler: optional<thread>;
}

local module = {};
local metatable = {};
metatable.__index = metatable;
metatable.__len = function(t)
  return t._length
end;
metatable.__newindex = function(t, k, v)
	if k ~= "_tackler" then
		error("Cannot write to this table. ConnectionRegistry is write-protected. Use the provided methods to interact with the registry.", 2)
	else
		rawset(t, k, v)
	end
end;
metatable.__metatable = "This metatable is locked.";
export type ConnectionRegistry = typeof(setmetatable({} :: self, metatable))
export type anyConnectionRegistries = {[any]: ConnectionRegistry}
export type optionalConnectionRegistries = anyConnectionRegistries?

local huge = math.huge;

function module.new(): ConnectionRegistry
	local self = {} :: self
	self.__type = "ConnectionRegistry"
	self._length = 0
	self._registrars = {}
	self._queue = datastructures.new("Queue")
	self._tackler = nil;
	setmetatable(self, metatable)
	return self
end

function metatable:Disconnect(index: any): ()
	self = self :: ConnectionRegistry
	local connection: anyConnection = self._registrars[index]
	if not connection then
		return
	end
	if connection.Connected then
		connection:Disconnect()
	end
	self._registrars[index] = nil
	self._length = math.clamp(self._length-1, 0, huge)
end

function metatable:_tackleQueue(): ()
	while not self._queue:IsEmpty() do
        local setupFunc = self._queue:Dequeue()
        local returningIndex = setupFunc()
        coroutine.yield(returningIndex)
    end
end

-- (queues for sequential callback index incrementing, especially for numerical indices)
function metatable:_enqueueConnection(connection: anyConnection, index)
    if not connection then
        return nil
    end
	self = self :: ConnectionRegistry
    self._queue:Enqueue(function()
        local returningIndex = nil
        if index then
            -- we are able to freely write to the desired index
            self._registrars[index] = connection
            returningIndex = index
			return returningIndex
        end
        -- we were not given a desired index, so set to the first hole in the numerical indices if there is one, or append to the end of the numerical indices
        local icount = #self._registrars
        local firstHole = nil
        if icount >= 1 then
            for i = 1, icount do
                if not self._registrars[i] then
                    firstHole = i
                    break
                end
            end
        end
        if firstHole then
            self._registrars[firstHole] = connection
            returningIndex = firstHole
        else
            table.insert(self._registrars, connection)
            returningIndex = icount + 1
        end
        return returningIndex
    end)
	local tackler = self._tackler
	if tackler == nil or coroutine.status(tackler) == "dead" then
		tackler = coroutine.create(function()
			self:_tackleQueue()
		end)
		rawset(self, "_tackler", tackler)
	end

	if coroutine.status(tackler) == "suspended" then
		local s, result = coroutine.resume(tackler)
		if s then
			return result
		end
		error(result)
	end

    return nil
end

-- Returns the index of the registered connection, or nil if the connection was not registered (if the connection was invalid, or if the index provided was already taken)
function metatable:Register(connection: anyConnection, index: any): any
	if not connection then
		return nil
	end
	self = self :: ConnectionRegistry
	if index == nil then
		index = self:_enqueueConnection(connection)
	elseif self._registrars[index] ~= nil then
		--we don't want memory leaks, so disable overwriting registers
		warn("You may not overwrite an existing connection. Please disconnect the existing connection before registering a new one at the same index.")
		return nil
	else
		index = self:_enqueueConnection(connection, index)
	end
	if index == nil then
		return nil
	end
 	self._length = math.clamp(self._length+1, 0, huge)
	return index
end
function metatable:DisconnectAll(): ()
	self = self :: ConnectionRegistry
	for index, _connection: anyConnection in pairs(self._registrars) do
		self:Disconnect(index)
	end
end
function metatable:Destroy(): ()
	self = self :: ConnectionRegistry
	self:DisconnectAll()
	self.__type = nil
	table.clear(self._registrars)
	self._registrars = nil
	self._length = nil
end

return module
