--!nonstrict
--@title: Scheduler
--@author: crusherfire
--@date: 4/2/24
--[[@description:
	Allows to place 'tasks' in queue. A task can be anything (function, table, etc). These 'tasks' will be passed to
	the bound callback function responsible for handling the tasks. A new incoming task won't be available to
	the handler callback until :DoneHandlingTask() is called.
	
	Change the policy on the fly using :SetPolicy(). (FIFO is default)
	Add a predicate to filter out undesireable tasks in the queue!
	Return false from your predicate if you wish for the task to be removed from the queue.
	
	DOCUMENTATION:
	
	.new(policy: Policies?): Scheduler
	Returns a Scheduler object with an optional policy parameter. The default policy is "FIFO" if none is provided.
	
	:ChangePolicy(policy: Policies)
	Changes the policy of the scheduler. This can be changed even while the scheduler is handling tasks 
	and will be reflected when the next task is going to be chosen.
	
	:BindCallback(callback: (nextTask: any) -> ())
	Binds the callback to handle tasks given from the scheduler. This MUST be called before adding tasks to the scheduler.
	
	:UnbindCallback()
	Removes the callback that handles tasks given from the queue. This will stop the scheduler and clears 
	all tasks currently in queue. Before adding a new task, a new callback must be bound.
	
	:ConnectToQueueEmptySignal(callback: () -> ()): Signal.SignalConnection
	Returns a connection to the queue empty signal. This signal fires when there are no more tasks in the queue.
	
	:AddPredicate(predicate: (nextTask: any) -> (boolean))
	Adds an optional predicate to filter out undesirable tasks from the queue.
	
	:RemovePredicate()
	Removes the predicate.
	
	:DoneHandlingTask()
	This function notifies the scheduler that the callback is ready to receive the next task in the queue. 
	If you do not call this function, the scheduler will wait forever.
	
	:AddTask(newTask: any)
	Adds a new task to the queue. You must have a callback bound. If the scheduler is not active, this will start the scheduler.
	
	:GetNumberOfTasks()
	Returns the number of tasks currently in queue.
	
	:Destroy()
	Halts the scheduler & clears all values.
]]
-----------------------------
-- SERVICES --
-----------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-----------------------------
-- DEPENDENCIES --
-----------------------------
local Signal = require(script._signal)

-----------------------------
-- TYPES --
-----------------------------
type Policies = "LIFO" | "FIFO"
type self = {
	TasksInQueue: {any},
	NewTaskSignal: Signal.SignalType<any>,
	HandledTaskSignal: Signal.SignalType<>,
	QueueEmptySignal: Signal.SignalType<>,
	_active: boolean,
	_bound: Signal.SignalConnection | boolean,
	_policy: Policies,
	_predicate: ((nextTask: any) -> (boolean)) | boolean,
	_activeThread: thread | boolean,
}

-----------------------------
-- VARIABLES --
-----------------------------
local Scheduler = {}
local MT = {}
MT.__index = MT
MT.__newindex = function()
	error("Unable to add new fields to Scheduler object")
end
export type Scheduler = typeof(setmetatable({} :: self, MT))

-- CONSTANTS --

-----------------------------
-- PRIVATE FUNCTIONS --
-----------------------------
local function startTaskLoop(self: Scheduler)
	while self._active and self._bound do
		local index = if self._policy == "FIFO" then 1 else #self.TasksInQueue
		local currentTask = self.TasksInQueue[index]
		if not currentTask then
			self._active = false
			self.QueueEmptySignal:Fire()
			break
		end

		if typeof(self._predicate) == "function" and not self._predicate(currentTask) then
			table.remove(self.TasksInQueue, index)
			continue
		end

		local currentThread = coroutine.running()
		local wasHandled = false
		self.HandledTaskSignal:Once(function()
			wasHandled = true
			if coroutine.status(currentThread) == "suspended" then
				task.spawn(currentThread)
			end
		end)
		self.NewTaskSignal:Fire(currentTask)
		if not wasHandled then
			coroutine.yield()
		end
		table.remove(self.TasksInQueue, index)
	end
	table.clear(self.TasksInQueue)
	self._activeThread = false
end

-----------------------------
-- PUBLIC FUNCTIONS --
-----------------------------
function Scheduler.new(policy: Policies?): Scheduler
	local self = {}

	self.TasksInQueue = {}
	self.NewTaskSignal = Signal.new()
	self.HandledTaskSignal = Signal.new()
	self.QueueEmptySignal = Signal.new()
	self._active = false
	self._bound = false
	self._predicate = false
	self._activeThread = false
	self._policy = policy or "FIFO"

	setmetatable(self, MT)
	return self
end

function MT.ChangePolicy(self: Scheduler, policy: Policies)
	assert(policy == "LIFO" or policy == "FIFO", "Unexpected value passed to policy parameter!")

	self._policy = policy
end

function MT.GetNumberOfTasks(self: Scheduler)
	return #self.TasksInQueue
end

function MT.BindCallback(self: Scheduler, callback: (nextTask: any) -> ())
	if self._bound then
		warn("Function is already bound to scheduler!")
		return
	end
	assert(typeof(callback) == "function", "Callback must be a function!")

	self._bound = self.NewTaskSignal:Connect(callback) :: Signal.SignalConnection
end

function MT.ConnectToQueueEmptySignal(self: Scheduler, callback: () -> ()): Signal.SignalConnection
	assert(typeof(callback) == "function", "Expected function for callback!")

	return self.QueueEmptySignal:Connect(callback)
end

-- Unbinding the callback will halt the scheduler and clears all values in the queue.
function MT.UnbindCallback(self: Scheduler)
	if typeof(self._bound) ~= "boolean" then
		self._bound:Disconnect()
		self._bound = false
	end
end

function MT.AddPredicate(self: Scheduler, predicate: (nextTask: any) -> (boolean))
	assert(typeof(predicate) == "function", "Predicate must be a function!")

	self._predicate = predicate
end

function MT.RemovePredicate(self: Scheduler)
	self._predicate = false
end

function MT.DoneHandlingTask(self: Scheduler)
	self.HandledTaskSignal:Fire()
end

-- Callback MUST be bound before adding a task to the scheduler!
function MT.AddTask(self: Scheduler, ...: any)
	assert(self._bound, "No callback has been bound to the Scheduler!")

	local tasks = {...}
	for _, t in tasks do
		table.insert(self.TasksInQueue, t)
	end

	if not self._active then
		self._active = true
		self._activeThread = task.spawn(startTaskLoop, self)
	end
end

function MT:Destroy()
	task.cancel(self._activeThread)
	setmetatable(self, nil)
	table.clear(self)
end

-----------------------------
-- MAIN --
-----------------------------
return Scheduler