local Stack = {}
Stack.__index = Stack

export type Stack = {
	IsEmpty: (Stack)->boolean;
	Push: (Stack, value:any)->();
	Pop: (Stack)->any;
}

function Stack.new()
	local self = setmetatable({}, Stack)

	self._stack = {}

	return self
end

-- Check if the stack is empty
function Stack:IsEmpty(): boolean
	return #self._stack == 0
end

-- Put a new value onto the stack
function Stack:Push(value: any)
	self._stack[#self._stack+1] = value
end

-- Take a value off the stack
function Stack:Pop(): any
	if self:IsEmpty() then
		return nil
	end
	
	local value = self._stack[#self._stack]
	self._stack[#self._stack] = nil
	return value
end

return Stack