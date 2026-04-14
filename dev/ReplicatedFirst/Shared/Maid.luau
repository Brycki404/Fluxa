--[[

	maid = Maid.new()

	maid:GiveTask(task)
		> task is an event connection, function, or instance/table with a 'Destroy' method

	maid:GivePromise(promise)
		> Give the maid a promise as a task, which will call 'promise:Cancel()' on cleanup

	maid:DoCleaning()
		> Alias for Destroy

	maid:Destroy()
		> Goes through each task & disconnects events, destroys instances, and calls functions

]]

local Maid = {}
Maid.ClassName = "Maid"

local Promise = require(script.Parent.Promise)

function Maid.new()
	local self = setmetatable({
		_tasks = {},
	}, Maid)
	return self
end

function Maid:__index(index)
	if (Maid[index]) then
		return Maid[index]
	else
		return self._tasks[index]
	end
end

function Maid:__newindex(index, newTask)
	if (Maid[index] ~= nil) then
		error(("'%s' is reserved"):format(tostring(index)), 2)
	end

	local tasks = self._tasks
	local oldTask = tasks[index]
	tasks[index] = newTask

	if (oldTask) then
		if (type(oldTask) == "function") then
			oldTask()
		elseif (typeof(oldTask) == "RBXScriptConnection") then
			oldTask:Disconnect()
		elseif (oldTask.Destroy) then
			oldTask:Destroy()
		elseif (Promise.is(oldTask)) then
			oldTask:Cancel()
		end
	end
end

function Maid:GiveTask(task)
	assert(task, "Task cannot be false or nil")

	local taskId = (#self._tasks + 1)
	self[taskId] = task

	if (type(task) == "table" and (not task.Destroy) and (not Promise.is(task))) then
		warn("[Maid.GiveTask] - Gave table task without .Destroy\n\n"..debug.traceback())
	end

	return taskId
end

function Maid:GivePromise(promise)
	assert(Promise.is(promise), "Expected promise")

	if (promise:GetStatus() ~= Promise.Status.Started) then
		return promise
	end

	local newPromise = Promise.Resolve(promise)
	local id = self:GiveTask(newPromise)

	newPromise:Finally(function()
		self[id] = nil
	end)

	return newPromise
end

function Maid:DoCleaning()
	local tasks = self._tasks

	for index, task in pairs(tasks) do
		if (typeof(task) == "RBXScriptConnection") then
			tasks[index] = nil
			task:Disconnect()
		end
	end

	local index, task = next(tasks)

	while (task ~= nil) do
		tasks[index] = nil

		if (type(task) == "function") then
			task()
		elseif (typeof(task) == "RBXScriptConnection") then
			task:Disconnect()
		elseif (task.Destroy) then
			task:Destroy()
		elseif (Promise.is(task)) then
			task:Cancel()
		end

		index, task = next(tasks)
	end
end

Maid.Destroy = Maid.DoCleaning

export type MaidType = typeof(setmetatable({}, {__index = Maid}))

return Maid