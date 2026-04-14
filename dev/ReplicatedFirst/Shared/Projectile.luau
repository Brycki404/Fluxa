--!nonstrict
local module = {}

local RunService: RunService = game:GetService("RunService")
local heartbeat: RBXScriptSignal = RunService.Heartbeat
local Debris: Debris = game:GetService("Debris")
local ws = workspace
local Terrain = ws.Terrain
local DebugVisuals = ws.DebugVisuals

local V3 = Vector3
local NEWV3 = V3.new
local ZEROV3 = V3.zero
local ONEV3 = V3.one
local XAXISV3 = V3.xAxis
local YAXISV3 = V3.yAxis
local ZAXISV3 = V3.zAxis
local CF = CFrame
local NEWCF = CF.new
local LOOKATCF = CF.lookAt
local LOOKALONGCF = CF.lookAlong
local ANGLESCF = CF.Angles

--[[
rate1 = meters/studs
rate1*studs = meters
studs = meters/rate1

rate2 = feet/meters
rate2*meters = feet
meters = feet/rate2

studs*rate1*rate2 = feet
studs = feet/(rate1*rate2)
rate1*rate2 = feet/studs
]]

local metersPerStud = 0.28
local feetPerMeter = 3.2808399
local feetPerStud = metersPerStud*feetPerMeter
--[[
  According to Roblox's Game Settings tab,
  On Default Settings:
    1 stud == 0.28 meters
    1 meter == 3.2808399 feet
]]

local projectileSettings = {}

function projectileSettings.new()
  local self = {}
  
  self.__type = "ProjectileSettings";
  self.Units = "meters"; --"studs"|"meters"|"feet"|nil
  self.GravityWeight = 1; --number? (0.05(smallscale) or then 0.5(pistol))
  self.RaycastParameters = nil; --RaycastParams?
  self.WindWeight = 1; --number? (fraction of wind to apply)
  self.Lifetime = 5; --number?
  self.DebugMode = true; --boolean?
  
  return self
end

local projectile = {}
local projectile_methods = {}

function projectile_methods.Cast(self, Start:Vector3, Destination:Vector3, InitialVelocity:number): RaycastResult?
		--[[
		
		EQUATIONS:
		
		V = Vi + a*t
		d = Vi*t + 0.5*a*t^2
		P = Pi + d
		P = Pi + Vi*t + 0.5*a*t^2
		
		All directions move independetly
		
		]]--
  local InitVelocity: Vector3 = (Destination - Start).Unit * InitialVelocity/self.UnitConversion
  local Position: Vector3 = Start
  local Velocity: Vector3 = InitVelocity
  local Acceleration: Vector3 = NEWV3()
  local t: number = 0
  local raycastResult: RaycastResult? = nil
  local found: boolean = false
  local myDebugVisuals = nil

  local function stopPhysics()
    found = true
    if myDebugVisuals then
      myDebugVisuals:Destroy()
    end
  end
  local function checkToStopPhysics()
    if raycastResult or (self.Settings.Lifetime and t > self.Settings.Lifetime) then
      stopPhysics()
    end
  end
  local function createDebugVisual(position, velocity)
    if not myDebugVisuals then
      myDebugVisuals = Instance.new("Folder")
      myDebugVisuals.Parent = DebugVisuals
    end
    local adornment: ConeHandleAdornment = Instance.new("ConeHandleAdornment")
    adornment.Visible = false
    adornment.Parent = myDebugVisuals
    adornment.Adornee = Terrain
    adornment.AdornCullingMode = Enum.AdornCullingMode.Automatic
    adornment.AlwaysOnTop = false
    adornment.ZIndex = -1
    adornment.Color3 = Color3.new(1,0,0)
    adornment.Transparency = 0.4
    adornment.Height = 0.4
    adornment.Radius = 0.2
    adornment.CFrame = LOOKALONGCF(position, velocity)
    adornment.Visible = true
  end
  local function physicsLoop(dt)
    local wind = ws.GlobalWind
    local gravity = ws.Gravity

    t += dt
    Acceleration = NEWV3(
      (wind.X*self.UnitConversion*self.Settings.WindWeight),
      (wind.Y*self.UnitConversion*self.Settings.WindWeight) - (gravity*self.UnitConversion*self.Settings.GravityWeight),
      (wind.Z*self.UnitConversion*self.Settings.WindWeight)
    )
			--[[WIND
			Acceleration = NEWV3(
				UnitConversion*((wind.X*self.Settings.WindWeight)),
				UnitConversion*((wind.Y*self.Settings.WindWeight) - (gravity*self.Settings.GravityWeight)),
				UnitConversion*((wind.Z*self.Settings.WindWeight))
			)
			]]--
    Velocity = NEWV3(
      Velocity.X + Acceleration.X*dt,
      Velocity.Y + Acceleration.Y*dt,
      Velocity.Z + Acceleration.Z*dt
    )
    local newPosition = NEWV3(
      Position.X + Velocity.X*dt,
      Position.Y + Velocity.Y*dt,
      Position.Z + Velocity.Z*dt
    )

    raycastResult = workspace:Raycast(Position, newPosition - Position, self.Settings.RaycastParameters)
    Position = newPosition

    if self.Settings.DebugMode == true then
      createDebugVisual(newPosition, Velocity)
    end

    checkToStopPhysics()
  end
  local Connection = heartbeat:Connect(physicsLoop)

  while not found do
    task.wait()
  end

  Connection:Disconnect()

  if raycastResult ~= nil then
    print("Collision", raycastResult.Instance.Name)
    return raycastResult
  end
  return nil
end

function projectile.new(projectileSettings)
  local self = {}
  
  self.__type = "Projectile"
	self.Settings = (projectileSettings and projectileSettings["__type"] == "ProjectileSettings" and projectileSettings) or {}
  local unitsSetting = self.Settings["Units"]
  -- Gonna be honest, had no clue what I was doing here originally
  -- OUTPUT(studs)/robloxgravity(studs) = VARIABLE(unit)/realgravity(unit)

  if unitsSetting == "meters" then
    self.UnitConversion = metersPerStud
		--gravity = 9.81 m/s^2
  elseif unitsSetting == "feet" then
    self.UnitConversion = feetPerStud
		--gravity = 32.18 ft/s^2
	elseif unitsSetting == "studs" or unitsSetting == nil then
    self.UnitConversion = 1
    --gravity = 196.2 studs/s^2
  end
  
  for i,v in pairs(projectile_methods) do
    self[i] = v
  end
  
  return self
end

module.projectileSettings = projectileSettings
module.projectile = projectile

return module