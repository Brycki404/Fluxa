local PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

local QueueItem = require(script.QueueItems)

export type PriorityQueue = {
	IsEmpty: (PriorityQueue)->boolean;
	Enqueue: (PriorityQueue, value:any, priority:number?)->();
	Dequeue: (PriorityQueue)->any;
}

function PriorityQueue.new()
	local self = setmetatable({}, PriorityQueue)
	
	self._first = 0
	self._last = -1
	self._queue = {}
	
	return self
end

-- Check if the queue is empty
function PriorityQueue:IsEmpty(): boolean
	return self._first > self._last
end

-- Add a value to the queue
function PriorityQueue:Enqueue(value: any, priority: number?): ()
	local last = self._last + 1
	self._last = last
	
	local queueItem = QueueItem.new()
	queueItem:SetValue(value)
	queueItem:SetPriority(priority or 0)
	
	self._queue[last] = queueItem
end

-- Remove a value from the queue
function PriorityQueue:Dequeue(): any
	local first = self._first
	if self:IsEmpty() then
		return nil
	end
	table.sort(self._queue, function(before, after)
		local priorityBefore: number, priorityAfter: number = before:GetPriority(), after:GetPriority()
		if priorityBefore ~= priorityAfter then
			-- priorities are not equal, so sort them
			return priorityBefore > priorityAfter
		end
		local beforei: number?, afteri: number? = table.find(self._queue, before), table.find(self._queue, after)
		if beforei and afteri then
			--use the order they were already in
			return beforei < afteri
		end
		-- i don't know what happens here, just return true, they will be sorted anyways
		return true
	end)
	local value = self._queue[first]
	self._queue[first] = nil
	self._first = first + 1
	return value and value:GetValue() or nil
end

return PriorityQueue