local WORKSPACE = game:GetService("Workspace")

local CALLBACKRESULT 	= {}
CALLBACKRESULT.Continue = 1
CALLBACKRESULT.Finished = 2
CALLBACKRESULT.Fail 	= 3

local Raycast = {}
Raycast.CallBackResult = CALLBACKRESULT

--

function Raycast.Raycast(ray: Ray, ignoreWater: boolean?, collisionGroup: string?, respectCanCollide: boolean?, bruteForceAllSlow: boolean?)
  local rayparams: RaycastParams = RaycastParams.new()
  rayparams.FilterType = Enum.RaycastFilterType.Exclude
  rayparams.FilterDescendantsInstances = {}
  rayparams.IgnoreWater = ignoreWater or true
  rayparams.CollisionGroup = collisionGroup or "Default"
  rayparams.RespectCanCollide = respectCanCollide or false
  rayparams.BruteForceAllSlow = bruteForceAllSlow or false
  
  local raycastResult = workspace:Raycast(ray.Origin, ray.Direction, rayparams)
  return raycastResult
end

function Raycast.RaycastWithIgnoreList(ray: Ray, ignoreList, ignoreWater: boolean?, collisionGroup: string?, respectCanCollide: boolean?, bruteForceAllSlow: boolean?)
  local rayparams: RaycastParams = RaycastParams.new()
  rayparams.FilterType = Enum.RaycastFilterType.Exclude
  rayparams.FilterDescendantsInstances = ignoreList
  rayparams.IgnoreWater = ignoreWater or true
  rayparams.CollisionGroup = collisionGroup or "Default"
  rayparams.RespectCanCollide = respectCanCollide or false
  rayparams.BruteForceAllSlow = bruteForceAllSlow or false 
  
  local raycastResult = workspace:Raycast(ray.Origin, ray.Direction, rayparams)
  return raycastResult
end

function Raycast.RaycastWithWhiteList(ray: Ray, whiteList, ignoreWater: boolean?, collisionGroup: string?, respectCanCollide: boolean?, bruteForceAllSlow: boolean?)
  local rayparams: RaycastParams = RaycastParams.new()
  rayparams.FilterType = Enum.RaycastFilterType.Include
  rayparams.FilterDescendantsInstances = whiteList
  rayparams.IgnoreWater = ignoreWater or true
  rayparams.CollisionGroup = collisionGroup or "Default"
  rayparams.RespectCanCollide = respectCanCollide or false
  rayparams.BruteForceAllSlow = bruteForceAllSlow or false
  
  local raycastResult = workspace:Raycast(ray.Origin, ray.Direction, rayparams)
  return raycastResult
end

--

function Raycast.RaycastWithCallbackWithIgnoreList(ray: Ray, list, ignoreWater: boolean?, collisionGroup: string?, respectCanCollide: boolean?, bruteForceAllSlow: boolean?, callbackFunc) 
	local maxDistance = ray.Direction.Magnitude
	local direction = ray.Direction.Unit
	
	local lastPosition = ray.Origin
  local distance = 0
  
  local rayparams: RaycastParams = RaycastParams.new()
  rayparams.FilterType = Enum.RaycastFilterType.Exclude
  rayparams.FilterDescendantsInstances = list
  rayparams.IgnoreWater = ignoreWater or true
  rayparams.CollisionGroup = collisionGroup or "Default"
  rayparams.RespectCanCollide = respectCanCollide or false
  rayparams.BruteForceAllSlow = bruteForceAllSlow or false
  
  local raycastResult
  
	repeat
		local r = Ray.new(lastPosition, direction * (maxDistance - distance))
		raycastResult = WORKSPACE:Raycast(ray.Origin, ray.Direction, rayparams)
		local result = callbackFunc(raycastResult)
		
		if (result == CALLBACKRESULT.Continue) then
      distance = (ray.Origin - raycastResult.Position).Magnitude
      lastPosition = raycastResult.Position
		elseif (result == CALLBACKRESULT.Finished) then
      return raycastResult
		elseif (result == CALLBACKRESULT.Fail or result == nil) then
			break
		end
	until (distance >= maxDistance - 0.1)
	
	return
end

function Raycast.RaycastWithCallbackWithWhiteList(ray: Ray, list, ignoreWater: boolean?, collisionGroup: string?, respectCanCollide: boolean?, bruteForceAllSlow: boolean?, callbackFunc) 
	local maxDistance = ray.Direction.Magnitude
	local direction = ray.Direction.Unit
	
	local lastPosition = ray.Origin
  local distance = 0
  
  local rayparams: RaycastParams = RaycastParams.new()
  rayparams.FilterType = Enum.RaycastFilterType.Include
  rayparams.FilterDescendantsInstances = list
  rayparams.IgnoreWater = ignoreWater or true
  rayparams.CollisionGroup = collisionGroup or "Default"
  rayparams.RespectCanCollide = respectCanCollide or false
  rayparams.BruteForceAllSlow = bruteForceAllSlow or false
  
  local raycastResult
	
	repeat
		local r = Ray.new(lastPosition, direction * (maxDistance - distance))
    raycastResult = WORKSPACE:Raycast(ray.Origin, ray.Direction, rayparams)
    local result = callbackFunc(raycastResult)
		
		if (result == CALLBACKRESULT.Continue) then
      distance = (ray.Origin - raycastResult.Position).Magnitude
      lastPosition = raycastResult.Position
		elseif (result == CALLBACKRESULT.Finished) then
      return raycastResult
		elseif (result == CALLBACKRESULT.Fail or result == nil) then
			break
		end
	until (distance >= maxDistance - 0.1)
	
	return
end

function Raycast.RaycastWithCallback(ray: Ray, ignore, ignoreWater: boolean?, collisionGroup: string?, respectCanCollide: boolean?, bruteForceAllSlow: boolean?, callbackFunc) 
  return Raycast.RaycastWithCallbackWithIgnoreList(ray, {ignore}, ignoreWater, collisionGroup, respectCanCollide, bruteForceAllSlow, callbackFunc) 
end

--

return Raycast