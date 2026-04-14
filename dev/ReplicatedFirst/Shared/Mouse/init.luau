--[[

UserInputServiceMouse module

Ever hate having to use the player mouse or the plugin mouse? Well here's a soltuion! This module returns a custom mouse class that uses
the UserInputService instead. Yay! No more having to worry if `plugin:Activate(true)` was called and still active!

Here's what you need to know from the API side of things. Most of this class is pretty much identical in functionality to the player or plugin mouse.
That being said I've added/changed a few things that I felt were either useful additions or how the mouse object should have behaved in the first place.

API:

Properties:
	mouse.Hit [readonly][CFrame]
		> The CFrame of the mouse’s position in 3D space.
	mouse.Origin [readonly][CFrame]
		> A DataType/CFrame positioned at the Workspace/CurrentCamera and oriented toward the Mouse's 3D position
	mouse.Target [readonly][Instance]
		> The object in 3D space the mouse is pointing to.
	mouse.TargetFilter [Instance] or [Array of Instances]
		> Determines an object (and its descendants) to be included when determining Mouse.Hit and Mouse.Target
		> Note for added functionality this can be set to either a single instance or a table of instances.
		> Defaulted to the workspace.
	mouse.TargetSurface [readonly][Enum.NormalId]
		> Describes the NormalId of the BasePart surface at which the mouse is pointing
	mouse.UnitRay [readonly][Ray]
		> A Ray directed towards the Mouse's world position, originating from the Camera's world position
	mouse.ViewSizeX [readonly][Number]
		> Describes the width of the screen in pixels
	mouse.ViewSizeY [readonly][Number]
		> Describes the height of the scree in pixels
	mouse.X [readonly][Number]
		> Describes the X (horizontal) component of the mouse’s screen position
	mouse.Y [readonly][Number]
		> Describes the Y (vertical) component of the mouse’s screen position

	mouse.TargetSurfaceNormal [readonly][Vector3]
		> Describes the SurfaceNormal of the BasePart surface at which the mouse is pointing	
	mouse.ViewSize [readonly][Vector2]
		> Describes the width and height of the screen in pixels
	mouse.Position [readonly][Vector2]
		> Describes the X and Y components of the mouse’s screen position
	mouse.TargetBlackList [Instance] or [Array of Instances]
		> Determines an object (and its descendants) to be ignored when determining Mouse.Hit and Mouse.Target
		> This can be set to either a single instance or a table of instances.
	mouse.IgnoreCharacter [boolean]
		> Only applies when a local player's character exists and is automatically set to true. This is a very odd property I admit, 
		> but for whatever reason the player mouse ignores the character so I figured I'd include this to perfectly emulate.
	mouse.IgnoreWater [boolean]
		> Should the mouse ignore terrain water? If true then it will, if false it won't.
		> By default this is false.
		
Events:
	mouse.Button1Down
		> Fired when the left mouse button is pressed.
	mouse.Button1Up
		> Fires when the left mouse button is released.
	mouse.Button2Down
		> Fires when the right mouse button is pressed.
	mouse.Button2Up
		> Fired when the right mouse button is released.
	mouse.Button3Down
		> Fires when the middle mouse button is pressed.
	mouse.Button3Up
		> Fired when the middle mouse button is released.
	mouse.Idle
		> Fired during every heartbeat that the mouse isn’t being passed to another mouse event.
	mouse.Move
		> Fired when the mouse is moved.
	mouse.WheelBackward
		> Fires when the mouse wheel is scrolled backwards.
	mouse.WheelForward
		> Fires when the mouse wheel is scrolled forwards.
		
Methods:
	mouse:Destroy()
		> Disconnects any events and removes anything related to the mouse. You should never have to call this to be completely honest,
		> but it's there just in case.
		
	mouse:IgnoreCheck(hit, position, normal, material)
		> By default this is nil and does nothing. However if the user writes this function they can define if certain objects are ignored or not.
		> The method should return true for parts you want to ignore and false for parts you do not.
		> For example if you wanted the mouse to ignore all CanCollide = false BaseParts you could define the method as such:
		
		function mouse:IgnoreCheck(hit, position, normal, material)
			return not hit.CanCollide
		end

Enjoy!
EgoMoose
--]]

local UIS = game:GetService("UserInputService")
local PLAYERS = game:GetService("Players")
local RUNSERVICE = game:GetService("RunService")
local CAMERA = game:GetService("Workspace").CurrentCamera

local Raycast = require(script:WaitForChild("Raycast"))

-- Class

local Mouse = {}
local Mouse_mt = {}
local Mouse_properties = {}
local Mouse_storage = setmetatable({}, {__mode = "k"})

-- Private functions

local function copyArray(array)
	local t, n = {}, #array
	local i, j = 1, n
	while (i < j) do
		t[i], t[j] = array[i], array[j]
		i, j = i + 1, j - 1
	end
	if (n%2 == 1) then
		local m = math.ceil(n/2)
		t[m] = array[m]
	end
	return t
end

local function castMouseRay(self): RaycastResult?
	local whiteList = (type(self.TargetFilter) == "table") and copyArray(self.TargetFilter) or {self.TargetFilter}
	local blackList = (type(self.TargetBlackList) == "table") and copyArray(self.TargetBlackList) or {self.TargetBlackList}
	
	if (self.IgnoreCharacter) then
		table.insert(blackList, PLAYERS.LocalPlayer.Character)
	end
	
	local v = UIS:GetMouseLocation()
	local r = CAMERA:ViewportPointToRay(v.x, v.y, 0)
  local ray = Ray.new(r.Origin, r.Direction*1000)
	
	local nWhite, nBlack = #whiteList, #blackList
	
	if (nWhite > 0 and nBlack > 0 or self.IgnoreCheck) then
		return Raycast.RaycastWithCallbackWithIgnoreList(ray, blackList, self.IgnoreWater, self.CollisionGroup, self.RespectCanCollide, self.BruteForceAllSlow, function(rayResult)
			if (rayResult) then
				-- whiteList exists
				for i = 1, nWhite do
					local white = whiteList[i]
          if (white == rayResult.Instance or rayResult.Instance:IsDescendantOf(white)) then
            if (self.IgnoreCheck and self:IgnoreCheck(rayResult)) then
              table.insert(blackList, rayResult.Instance)
              return Raycast.CallBackResult.Continue
            else
              return Raycast.CallBackResult.Finished
            end
					end
				end
				
				-- whiteList doesn't exist
				if (nWhite <= 0) then
          if (self.IgnoreCheck and self:IgnoreCheck(rayResult)) then
            table.insert(blackList, rayResult.Instance)
            return Raycast.CallBackResult.Continue
          else
            return Raycast.CallBackResult.Finished
          end
				end
			else
				return Raycast.CallBackResult.Finished
			end
		end)
  elseif (nWhite > 0) then
    return Raycast.RaycastWithWhiteList(ray, whiteList, self.IgnoreWater, self.CollisionGroup, self.RespectCanCollide, self.BruteForceAllSlow)
	else
    return Raycast.RaycastWithIgnoreList(ray, blackList, self.IgnoreWater, self.CollisionGroup, self.RespectCanCollide, self.BruteForceAllSlow)
	end
end

local function planeIntersect(point, vector, origin, normal)
	local rpoint = point - origin
	local t = -rpoint:Dot(normal)/vector:Dot(normal)
	return point + t * vector, t
end

local function getMouseScreenPos()
	if (PLAYERS.LocalPlayer) then
		return UIS:GetMouseLocation() - Vector2.new(0, 36)
	end
	return UIS:GetMouseLocation()
end

local function getScreenSize()
	if (PLAYERS.LocalPlayer) then
		return CAMERA.ViewportSize - Vector2.new(0, 72)
	end
	return CAMERA.ViewportSize
end

-- Getter Properties

function Mouse_properties.TargetSurface(self)
	local v = UIS:GetMouseLocation()
	local unitRay = CAMERA:ViewportPointToRay(v.x, v.y, 0)
  local raycastResult: RaycastResult? = castMouseRay(self)
  if (raycastResult and raycastResult.Instance and raycastResult.Instance.ClassName ~= "Terrain") then
    local cf, size2 = raycastResult.Instance.CFrame, raycastResult.Instance.Size/2
		local start = cf:PointToObjectSpace(unitRay.Origin)
		local direction = cf:VectorToObjectSpace(unitRay.Direction)
		
		for i, enum in next, Enum.NormalId:GetEnumItems() do
			local ln = Vector3.FromNormalId(enum)
			local origin = ln*size2
			local p = planeIntersect(start, direction, origin, ln)

			if (ln:Dot(direction) <= 0) then
				local pass = true
				for j, enum2 in next, Enum.NormalId:GetEnumItems() do
					if (i ~= j) then
						local ln2 = Vector3.FromNormalId(enum2)
						local origin2 = ln2*size2
						
						if ((p - origin2):Dot(ln2) > 0) then
							pass = false
							break
						end
					end
				end
				if (pass) then
					return enum
				end
			end
		end
  end
end

function Mouse_properties.UnitRay(self)
	local v = UIS:GetMouseLocation()
	return CAMERA:ViewportPointToRay(v.x, v.y, 0)
end

function Mouse_properties.ViewSizeX(self)
	return getScreenSize().x
end

function Mouse_properties.ViewSizeY(self)
	return getScreenSize().y
end

function Mouse_properties.X(self)
	return getMouseScreenPos().x
end

function Mouse_properties.Y(self)
	return getMouseScreenPos().y
end

function Mouse_properties.Target(self)
  local raycastResult: RaycastResult? = castMouseRay(self)
  return raycastResult and raycastResult.Instance or nil
end

function Mouse_properties.Origin(self)
	local v = UIS:GetMouseLocation()
	local unitRay = CAMERA:ViewportPointToRay(v.x, v.y, 0)
	return CFrame.new(unitRay.Origin, unitRay.Origin + unitRay.Direction)
end

function Mouse_properties.Hit(self)
	local v = UIS:GetMouseLocation()
	local unitRay = CAMERA:ViewportPointToRay(v.x, v.y, 0)
	local raycastResult: RaycastResult? = castMouseRay(self)
  return raycastResult and raycastResult.Position and CFrame.new(raycastResult.Position, raycastResult.Position + unitRay.Direction) or nil
end

function Mouse_properties.ViewSize(self)
	return getScreenSize()
end

function Mouse_properties.Position(self)
	return getMouseScreenPos()
end

function Mouse_properties.TargetSurfaceNormal(self)
  local raycastResult: RaycastResult? = castMouseRay(self)
	return raycastResult and raycastResult.Normal or nil
end

function Mouse_properties.TargetMaterial(self)
  local raycastResult: RaycastResult? = castMouseRay(self)
	return raycastResult and raycastResult.Material or nil
end

-- Metamethods

function Mouse_mt.__index(mouse, k)
	k = k:sub(1, 1):upper() .. k:sub(2)
	
	if (Mouse[k]) then
		return Mouse[k]
	elseif (Mouse_storage[mouse].ReadOnly[k]) then
		return Mouse_storage[mouse].ReadOnly[k]
	elseif (Mouse_properties[k]) then
		return Mouse_properties[k](mouse)
	else
		error(k .. " is not a valid member of Mouse")
	end
end

function Mouse_mt.__tostring()
	return "Mouse"
end

Mouse_mt.__metatable = false

-- Constructor

function Mouse.new()
	local self = {}

	-- Properties

	self.TargetFilter = {}
	self.TargetBlackList = {}
	self.IgnoreCharacter = true
  self.IgnoreWater = true
  self.RespectCanCollide = false
  self.CollisionGroup = "Default"
  self.BruteForceAllSlow = false
	
	-- Events
	
	local mouseEvents = {}
	
	local button1Down = Instance.new("BindableEvent")
	local button1Up = Instance.new("BindableEvent")
	local button2Down = Instance.new("BindableEvent")
	local button2Up = Instance.new("BindableEvent")
	local button3Down = Instance.new("BindableEvent")
	local button3Up = Instance.new("BindableEvent")
	local idle = Instance.new("BindableEvent")
	local move = Instance.new("BindableEvent")
	local wheelBackward = Instance.new("BindableEvent")
	local wheelForward = Instance.new("BindableEvent")
	
	table.insert(mouseEvents, UIS.InputBegan:Connect(function(input, process)
		if (process) then return end
		
		if (input.UserInputType == Enum.UserInputType.MouseButton1) then
			button1Down:Fire()
		elseif (input.UserInputType == Enum.UserInputType.MouseButton2) then
			button2Down:Fire()
		elseif (input.UserInputType == Enum.UserInputType.MouseButton3) then
			button3Down:Fire()
		end
	end))
	
	table.insert(mouseEvents, UIS.InputEnded:Connect(function(input, process)
		if (process) then return end
		
		if (input.UserInputType == Enum.UserInputType.MouseButton1) then
			button1Up:Fire()
		elseif (input.UserInputType == Enum.UserInputType.MouseButton2) then
			button2Up:Fire()
		elseif (input.UserInputType == Enum.UserInputType.MouseButton3) then
			button3Up:Fire()
		end
	end))
	
	table.insert(mouseEvents, UIS.InputChanged:Connect(function(input, process)
		if (process) then return end
		
		if (input.UserInputType == Enum.UserInputType.MouseMovement) then
			move:Fire()
		elseif (input.UserInputType == Enum.UserInputType.MouseWheel) then
			if (input.Position.z > 0) then
				wheelForward:Fire()
			else
				wheelBackward:Fire()
			end
		end
	end))
	
	local lastLocation = UIS:GetMouseLocation()
	table.insert(mouseEvents, RUNSERVICE.Heartbeat:Connect(function()
		local currentLocation = UIS:GetMouseLocation()
		if (currentLocation == lastLocation) then
			idle:Fire()
		end
		lastLocation = currentLocation
	end))
	
	-- Read only properties
	
	local readOnly = {}
	readOnly.Button1Down = button1Down.Event
	readOnly.Button1Up = button1Up.Event
	readOnly.Button2Down = button2Down.Event
	readOnly.Button2Up = button2Up.Event
	readOnly.Button3Down = button3Down.Event
	readOnly.Button3Up = button3Up.Event
	readOnly.Idle = idle.Event
	readOnly.Move = move.Event
	readOnly.WheelBackward = wheelBackward.Event
	readOnly.WheelForward = wheelForward.Event
	
	Mouse_storage[self] = {
		ReadOnly = readOnly,
		MouseEvents = mouseEvents,
		BindableEvents = {button1Down, button1Up, button2Down, button2Up, button3Down, button3Up, idle, move, wheelBackward, wheelForward},
		MouseIgnoreCheck = nil
	}
	
	return setmetatable(self, Mouse_mt);
end

-- Public methods

function Mouse:IgnoreCheck(raycastResult: RaycastResult)
	return false
end

function Mouse:Destroy()
	local store = Mouse_storage[self]
	local mouseEvents = store.MouseEvents
	local bindableEvents = store.BindableEvents
	
	for i = 1, #mouseEvents do
		mouseEvents[i]:Disconnect()
	end
	for i = 1, #bindableEvents do
		bindableEvents[i]:Destroy()
	end
end

--

return Mouse