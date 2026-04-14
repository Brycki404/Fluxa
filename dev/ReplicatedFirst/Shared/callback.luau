export type CallbackSignalName = "OnSlotEquipped" | "OnSlotUnequipped" | "OnSlotAdded" | "OnSlotRemoved" | "OnSlotUpdated"

-- For these Callbacks, I use a Queue system so you never overwrite a Callback in the instance you are using numerical indices
-- Probably overkill, but I think it's cool, so let's go with it
Backpack.Callbacks = {
    OnSlotEquipped = {};
    OnSlotUnequipped = {};
    OnSlotAdded = {};
    OnSlotRemoved = {};
    OnSlotUpdated = {};
}

local CallbackQueue = DataStructures.new("Queue")
local function TackleQueue()
    while not CallbackQueue:IsEmpty() do
        local setupCallback = CallbackQueue:Dequeue()
        local returningIndex = setupCallback()
        coroutine.yield(returningIndex)
    end
end
local TackleQueueThread: thread? = nil

function Backpack:RemoveCallback(signal: CallbackSignalName, index)
    if not signal or not index then return end
    if not Backpack.Callbacks[signal] then return end
    if Backpack.Callbacks[signal][index] == nil then return end
    -- we never do table.remove() by pos because that would shift all the preexisting numerical indices which we don't want to do
    -- instead we will just fill in gaps if there are any before using table.insert()
    Backpack.Callbacks[signal][index] = nil
end

-- (queues for sequential callback index incrementing, especially for numerical indices)
local function enqueueCallback(signal: CallbackSignalName, callback, index)
    if not signal or not callback or type(callback) ~= "function" then
        return nil
    end
    CallbackQueue:Enqueue(function()
        local returningIndex = nil
        if index then
            -- we are able to freely write to the desired index
            Backpack.Callbacks[signal][index] = callback
            returningIndex = index
            return nil
        end
        -- we were not given a desired index, so set to the first hole in the numerical indices if there is one, or append to the end of the numerical indices
        local icount = #Backpack.Callbacks[signal]
        local firstHole = nil
        if icount >= 1 then
            for i = 1, icount do
                if not Backpack.Callbacks[signal][i] then
                    firstHole = i
                    break
                end
            end
        end
        if firstHole then
            Backpack.Callbacks[signal][firstHole] = callback
            returningIndex = firstHole
        else
            table.insert(Backpack.Callbacks[signal], callback)
            returningIndex = icount + 1
        end
        return returningIndex
    end)
    if not TackleQueueThread or TackleQueueThread and coroutine.status(TackleQueueThread) == "suspended" then
        if not TackleQueueThread then
            TackleQueueThread = coroutine.create(TackleQueue)
        end
        local s, result = coroutine.resume(TackleQueueThread)
        if s and result then
            return result
        end
    end
    return nil
end

-- This function is for adding callbacks to the signals
-- This function returns the index at which the callback was inserted for optional tampering later on
-- This function yeilds until the callback was Dequeued
function Backpack:AddCallback(signal: CallbackSignalName, callback, index)
    if not signal or not callback or type(callback) ~= "function" then
        warn("missing something", signal, callback)
        return
    end
    if Backpack.Callbacks[signal] == nil then
        warn("there is no table of callbacks at signal '"..signal.."'")
        return
    end
    -- check for preexisting callback at the given index (if one was passed to the function)
    if index ~= nil and Backpack.Callbacks[signal][index] ~= nil then
        warn("there is already a callback at '"..tostring(index).."'' for signal '"..tostring(signal).."'")
        return
    end
    local returnedIndex = enqueueCallback(signal, callback, index)
    return returnedIndex
end

local function handleCallbacks(callbacks, ...)
    for i: any, callback in pairs(callbacks) do
        if type(callback) ~= "function" then
            warn("callback at "..tostring(i).." is not a function")
            continue
        end
        callback(...)
    end
end