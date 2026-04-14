local module = {}

local metatable = {__index = table}

module.random = function(t)
	assert(#t > 0)
	local n = math.random(1, #t)
	return t[n], n
end

module.chop = function(t, start, finish)
	
	assert(start > 0)
	assert(#t > 0)
	assert(finish <= #t)
	
	for i = finish, start, -1  do
		table.remove(t, i)
	end

	return t
end

module.keys = function(tble)
	local t = {}
	for key, _ in pairs(tble) do
		t[#t+1] = key
	end
	return t
end

module.values = function(tble)
	local t = {}
	for _, value in pairs(tble) do
		t[#t+1] = value
	end
	return t
end

module.toArray = function(dictionary)
	local t = {}
	for key, value in pairs(dictionary) do
		t[#t+1] = {Key = key, Value = value}
	end
	return t
end

module.filter = function(tble, condition)
	for i = #tble, 1, -1  do
		if not condition(tble[i]) then
			table.remove(tble, i)
		end
	end
end

module.indexOf = function(tble, condition)
	for key, value in pairs(tble) do
		local result = condition(key, value)
		if result then
			return key
		end
	end
	return -1
end

module.shallowCopy = function(t)
	local t2 = {}
	t.__index = nil
	for key, value in pairs(t) do
		value = rawget(t, key)
		t2[key] = value
	end
	return t2
end

module.deepCopy = function(t)
	local t2 = {}
	t.__index = nil
	for key, value in pairs(t) do
		value = rawget(t, key)
		if type(value) == "table" then
			value = module.deepCopy(value)
		end
		t2[key] = value   
	end
	return t2
end

module.flip = function(t)
  local t2 = {}
  for key, value in pairs(t) do
    t2[value] = key
  end
  return t2
end

module.dictionaryLength = function(t)
	local n = 0
	for _, _ in pairs(t) do
		n += 1
	end
	return n
end

module.bringIn = function(t, t2)
	for i,v in pairs(t2) do
		t[i] = v
	end
end

return setmetatable(module, metatable)

