local Run = game:GetService("RunService")
local Players = game:GetService("Players")
local Rep = game:GetService("ReplicatedStorage")

local modules = Rep.Modules
local conreg = require(modules.ConnectionRegistry)
local signal = require(modules.Signal)
local bts = require(modules.BaseTypes)
local table = require(modules.Table)

local module = {}

local hitboxmode_continuous = "Continuous"
local hitboxmode_once = "Once"
type hitboxmode = "Continuous" | "Once"

local _hitbox_string = "Hitbox"
type hitbox = {
	__type: string?;
	
	Mode: hitboxmode;
	Enabled: boolean;
	
	Parts: {[any]: BasePart};
	Functions: bts.optionalFunctions;
	Signals: bts.optionalSignals;
	ConnectionRegistries: conreg.optionalConnectionRegistries;
}
local hitbox = {}
local hitboxMT = {}
hitboxMT.__index = hitboxMT
export type Hitbox = typeof(setmetatable({} :: hitbox, hitboxMT))

function hitbox.new(onhit: bts.anyFunction, parts:{[any]: BasePart}?, mode:hitboxmode?, enable:boolean?): Hitbox
	local self = {} :: hitbox
	
	--create self
	self.__type = _hitbox_string
	
	self.Functions = {}
	self.Functions.OnHit = onhit
	self.Parts = parts or {}
	self.Mode = mode or hitboxmode_once --Once or Continuous
	self.Enabled = enable or false --only for Continuous mode
	
	self.Signals = {}
	self.ConnectionRegistries = {}
	self.ConnectionRegistries.Touches = conreg.new()
	--self.ConnectionRegistries.EXAMPLE = conreg.new()
	
	--setup without methods
	
	--get methods
	setmetatable(self, hitboxMT)
	self = self :: Hitbox
	
	--setup with methods
	if self.Mode == hitboxmode_continuous then
		if self.Enabled == true then
			self:continuous(true)
		end
	end
	
	return self
end

function hitboxMT.setmode(self, mode: hitboxmode?): ()
	assert(self)
	self = self :: Hitbox
	if not mode then return end
	if mode ~= (hitboxmode_once or hitboxmode_continuous) then return end
	print("Once or Continuous")
	self.Mode = mode
end

function hitboxMT.setonhit(self, func: bts.anyFunction): ()
	assert(self)
	self = self :: Hitbox
	if not func then return end
	self.Functions.OnHit = func
end

function hitboxMT.setparts(self, parts:{[number]: BasePart}): ()
	assert(self)
	self = self :: Hitbox
	if not parts then return end
	if typeof(parts) ~= "table" then return end
	self.Parts = parts
	if self.Mode == hitboxmode_continuous then
		self:continuous(self.Enabled)
	end
end

function hitboxMT.addparts(self, parts:{[number]: BasePart}): ()
	assert(self)
	self = self :: Hitbox
	if not parts then return end
	if typeof(parts) ~= "table" then return end
	if #parts <= 0 then return end
	if not self.Parts then self.Parts = {} end
	for i:number, part:BasePart in pairs(parts) do
		local p: number = self.Parts:find(part)
		if not p then
			self.Parts:insert(part)
		end
	end
	if self.Mode == hitboxmode_continuous then
		self:continuous(self.Enabled)
	end
end

function hitboxMT.removeparts(self, parts:{[number]: BasePart}): ()
	assert(self)
	self = self :: Hitbox
	if not parts then return end
	if typeof(parts) ~= "table" then return end
	if #parts <= 0 then return end
	if not self.Parts then self.Parts = {} end
	for i:number, part:BasePart in pairs(parts) do
		local p: number = self.Parts:find(part)
		if p then
			self.Parts:remove(p)
		end
	end
	if self.Mode == hitboxmode_continuous then
		self:continuous(self.Enabled)
	end
end

function hitboxMT.once(self): ()
	assert(self)
	self = self :: Hitbox
	assert(self.Mode == hitboxmode_once, "Must be in 'Once' mode to use this function.")
	if self.Mode == hitboxmode_once then
		local touches: conreg.ConnectionRegistry = self.ConnectionRegistries.Touches
		touches:DisconnectAll()
		-- ^clears any touched connections
		local hittags = {};
		for _, part in pairs(self.Parts) do
			if not part:FindFirstChildOfClass("TouchInterest") then
				--to create a touch interest inside of parts that don't have one
				touches:Disconnect(part)
				touches:Register(part, part.Touched:Connect(function() end))
			end
			local touching = part:GetTouchingParts()
			for _, hit in pairs(touching) do
				self.Functions.OnHit(part, hit)
				--[[
				local humanoid = self.Owner.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					if humanoid.Health > 0 then
						--I (the person owning this hitbox) am alive
						local character = hit.Parent
						local hum = character:FindFirstChildOfClass("Humanoid")
						if not hum then
							warn("no hum, 1 [server-"..self.Owner.Name.."]")
							return
						end
						if hum == humanoid then warn("hitting myself, humanoid [server-"..self.Owner.Name.."]") return end
						local hitplayer = Players:GetPlayerFromCharacter(character)
						if hitplayer then
							if hitplayer == self.Owner then
								warn("hitting myself, player [server-"..self.Owner.Name.."]")
								return
							end
						end
						if not table.find(hittags, character) then
							if self.Piercing == true then
								table.insert(hittags,character)
								self.OnHit(character, hit)
							elseif self.Piercing == false then
								table.insert(hittags,character)
								self.OnHit(character, hit)
								break
							end
						end
					end
				end
				]]
			end
			touches:DisconnectAll()
			-- ^clears any touched connections
		end
	end
end

function hitboxMT.continuous(self, enable:boolean): ()
	assert(self)
	self = self :: Hitbox
	assert(self.Mode == hitboxmode_continuous, "Must be in 'Continuous' mode to use this function.")
	if self.Mode == hitboxmode_continuous then
		local touches: conreg.ConnectionRegistry = self.ConnectionRegistries.Touches
		self.Enabled = enable
		if self.Enabled == true then
			touches:DisconnectAll()
			-- ^clears any touched connections
			local hittags = {};
			local cancel = false
			for _, part in pairs(self.Parts) do
				touches:Disconnect(part)
				touches:Register(part, part.Touched:Connect(function(hit)
					self.Functions.OnHit(part, hit)
					--[[
					local humanoid = self.Owner.Character:FindFirstChildOfClass("Humanoid")
					if humanoid then
						if humanoid.Health > 0 then
							--I (the person owning this hitbox) am alive
							local character = hit.Parent
							local hum = character:FindFirstChildOfClass("Humanoid")
							if not hum then
								warn("no hum, 1 [server-"..self.Owner.Name.."]")
							end
							if hum == humanoid then warn("hitting myself, humanoid [server-"..self.Owner.Name.."]") return end
							local hitplayer = Players:GetPlayerFromCharacter(character)
							if hitplayer then
								if hitplayer == self.Owner then
									warn("hitting myself, player [server-"..self.Owner.Name.."]")
									return
								end
							end
							if not table.find(hittags, character) then
								if touches._registrars[part] ~= nil then
									if cancel == false then
										if self.Piercing == true then
											table.insert(hittags,character)
											self.OnHit(character, hit)
										elseif self.Piercing == false then
											cancel = true
											touches:Disconnect(part)
											table.insert(hittags,character)
											self.OnHit(character, hit)
										end
									elseif cancel == true then
										touches:Disconnect(part)
									end
								end
							end
						end
					end
					]]
				end))
			end
		elseif self.Enabled == false then
			touches:DisconnectAll()
		end
	end
end

function hitboxMT.run(self, enable): ()
	assert(self)
	self = self :: Hitbox
	if not self.Mode then return end
	if self.Mode == hitboxmode_continuous then
		print(enable)
		local isboolean = typeof(enable) == "boolean"
		enable = (isboolean == true and enable) or true
		print(enable)
		self:continuous(enable)
	elseif self.Mode == hitboxmode_once then
		self:once()
	end
end

function hitboxMT.RegisterConnections(self, registryIndex: any, connections: conreg.anyConnections): ()
	assert(self)
	self = self :: Hitbox
	if not registryIndex or not connections then return end
	if not self.ConnectionRegistries then return end
	if not self.ConnectionRegistries[registryIndex] then
		self.ConnectionRegistries[registryIndex] = conreg.new()
	end
	for index: any, connection: conreg.anyConnection in pairs(connections) do
		if self.ConnectionRegistries[registryIndex] then
			self.ConnectionRegistries[registryIndex]:Register(index, connection)
		end
	end
end

function hitboxMT.Destroy(self): ()
	if self then
		self = self :: Hitbox

		self.__type = nil
		--cleanup connections
		if self.ConnectionRegistries then
			for i, connectionRegistry: conreg.ConnectionRegistry in pairs(self.ConnectionRegistries) do
				connectionRegistry:DisconnectAll()
			end
			table.clear(self.ConnectionRegistries)
		end
		self.ConnectionRegistries = nil
		--destroy instances in nil if present
		if self.Parts then
			table.clear(self.Parts)
		end
		self.Parts = nil
		if self.Functions then
			table.clear(self.Functions)
		end
		self.Functions = nil
		if self.Signals then
			table.clear(self.Signals)
		end
		self.Signals = nil
		--final cleanup stage
		table.clear(self)
		setmetatable(self, nil)
		self = nil
	end
end

module.Class_TypeString = _hitbox_string 
module.Class = hitbox
module.Class_MetaTable = hitboxMT


return module
