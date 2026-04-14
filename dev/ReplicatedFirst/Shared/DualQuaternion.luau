--!strict

local Quaternion = require(script.Parent.Quaternion)

--[[
	Algorithmic credit: https://www.euclideanspace.com/maths/algebra/realNormedAlgebra/other/dualQuaternion/index.htm
]]

--[=[
	@within DualQuaternion
	@interface DualQuaternion
	.Real Quaternion
	.Dual Quaternion

	Similar to DualQuaternions, DualDualQuaternions are immutable. You cannot manually set the individual properties
	of a DualDualQuaternion. Instead, a new DualDualQuaternion must first be constructed.
]=]
export type DualQuaternion = {
	Real: Quaternion.Quaternion,
	Dual: Quaternion.Quaternion,
	
	Conjugate: (self: DualQuaternion) -> DualQuaternion,
	Normalized: (self: DualQuaternion) -> DualQuaternion,
	Screw: (self: DualQuaternion) -> (number, Vector3, number, Vector3),
	Power: (self: DualQuaternion, n: number) -> DualQuaternion,
	ToCFrame: (self: DualQuaternion) -> CFrame,
	Lerp: (self: DualQuaternion, other: DualQuaternion, t: number) -> DualQuaternion
}

local EPSILON = 1e-5

--[=[
	@class DualQuaternion
	Represents a DualQuaternion. DualQuaternions are 4D structs that represent rotations
	in 3D space. DualQuaternions are often used in 3D graphics to avoid the ambiguity
	that comes with Euler angles (e.g. gimbal lock).

	Roblox represents the transformation of an object via CFrame values, which are
	matrices that hold positional and rotational information. DualQuaternions can be converted
	to and from CFrame values through the `ToCFrame` method and `cframe` constructor.
]=]
local DualQuaternion = {}
DualQuaternion.__index = DualQuaternion

--[=[
	Constructs a DualQuaternion.

	:::caution
	The `new` constructor assumes the given arguments represent a proper DualQuaternion. This
	constructor should only be used if you really know what you're doing.
]=]
function DualQuaternion.new(real: Quaternion.Quaternion, dual: Quaternion.Quaternion): DualQuaternion
	local self = setmetatable({
		Real = real,
		Dual = dual
	}, DualQuaternion) :: any

	table.freeze(self)

	return self
end

--[=[
	Constructs a DualQuaternion from the components of the given `cframe`.

	This method ortho-normalizes the CFrame value, so there is no need to do this yourself
	before calling the function.

	```lua
	-- Create a DualQuaternion representing the positional & rotational CFrame of a part:
	local dualQuat = DualQuaternion.cframe(somePart.CFrame)
	```
]=]
function DualQuaternion.cframe(cframe: CFrame): DualQuaternion
	local t = Quaternion.new(cframe.X, cframe.Y, cframe.Z, 0.0)
	local rotation = Quaternion.cframe(cframe)
	
	return DualQuaternion.new(rotation, (t * rotation) * 0.5)
end

--[=[
	@method Conjugate
	@within DualQuaternion
	@return DualQuaternion

	Returns the conjugate of the DualQuaternion. This is equal to `DualQuaternion.new(real:Conjugate(), dual:Conjugate())`.

	```lua
	local dualQuatConjugate = dualQuat:Conjugate()
	```
]=]
function DualQuaternion.Conjugate(self: DualQuaternion): DualQuaternion
	return DualQuaternion.new(self.Real:Conjugate(), self.Dual:Conjugate())
end

--[=[
	@method Normalized
	@within DualQuaternion
	@return DualQuaternion

	Returns the normal of the DualQuaternion.

	```lua
	local dualQuatNormal = dualQuat:Normalized()
	```
]=]
function DualQuaternion.Normalized(self: DualQuaternion): DualQuaternion
	local MinV = 1.0 / math.sqrt(self.Real:Dot(self.Real))
	return DualQuaternion.new(self.Real * MinV, self.Dual * MinV)
end

--[=[
	@method Screw
	@within DualQuaternion
	@return DualQuaternion

	Returns the normal of the DualQuaternion.

	```lua
	local theta, axis, distance, moment = dualQuat:Screw()
	```
]=]
function DualQuaternion.Screw(self: DualQuaternion): (number, Vector3, number, Vector3)
	local r, d = self.Real, self.Dual
	
	local function normalizeVector3(v: Vector3 | { X: number, Y: number, Z: number }): Vector3
		local SMALL_NUMBER = 1.e-8
		
		local SquareNum = v.X * v.X + v.Y * v.Y + v.Z * v.Z
		if SquareNum == 1.0 then
			return Vector3.new(v.X, v.Y, v.Z)
		elseif SquareNum < SMALL_NUMBER then
			return Vector3.zero
		end
		
		local Scale = 1.0 / math.sqrt(SquareNum)
		return Vector3.new(v.X * Scale, v.Y * Scale, v.Z * Scale)
	end
	
	local function nan(n: number)
		local SMALL_NUMBER = 1.e-8
		
		if n ~= n or n == 0 then
			return SMALL_NUMBER
		end
		
		return n
	end
	
	local axis = normalizeVector3(r)
	local theta = 2.0 * math.acos(r.W)
	local distance = -2.0 * d.W / nan(math.sin(theta / 2.0))
	local moment = (Vector3.new(d.X, d.Y, d.Z) - ((distance / 2.0) * math.sin(theta / 2.0)) * axis) / math.sin(theta / 2.0)
	
	return theta, axis, distance, moment
end

--[=[
	@method Power
	@within DualQuaternion
	@return DualQuaternion

	Returns an impacted DualQuaternion.

	```lua
	local dualQuatImpacted = dualQuat:Power(n)
	```
]=]
function DualQuaternion.Power(self: DualQuaternion, n: number): DualQuaternion
	local theta, axis, distance, moment = self:Screw()
	
	local halfAngle = n * theta / 2.0
	local halfD = n * distance / 2.0
	
	local rs, rv = math.cos(halfAngle), axis * math.sin(halfAngle)
	local r = Quaternion.new(rv.X, rv.Y, rv.Z, rs)
	
	local ds, dv = -halfD * math.sin(halfAngle), halfD * math.cos(halfAngle) * axis + math.sin(halfAngle) * moment
	local d = Quaternion.new(dv.X, dv.Y, dv.Z, ds)
	
	return DualQuaternion.new(r, d)
end

--[=[
	@method Lerp
	@within DualQuaternion
	@return DualQuaternion

	Calculates a screwed interpolation between the two DualQuaternions. Parameter `t` represents
	the percentage between the two rotations, from a range of `[0, 1]`.

	```lua
	local lerpedDualQuat = dualQuat:Lerp(other, t)
	```
]=]
function DualQuaternion.Lerp(self: DualQuaternion, other: DualQuaternion, t: number): DualQuaternion
	if other.Real:Dot(self.Real) < 0.0 then
		other = DualQuaternion.new(other.Real * -1.0, other.Dual)
	end
	
	return (self * (1 - t) + other * t):Normalized()
end

--[=[
	@method ToCFrame
	@within DualQuaternion
	@return DualQuaternion

	Constructs a CFrame value representing the Quaternions.

	```lua
	local cf = dualQuat:ToCFrame()
	```
]=]
function DualQuaternion.ToCFrame(self: DualQuaternion): CFrame
	local trans = self.Dual * self.Real:Conjugate()
	
	return self.Real:ToCFrame(Vector3.new(trans.X, trans.Y, trans.Z) * 2.0)
end

function DualQuaternion._MulDualQuaternion(self: DualQuaternion, other: DualQuaternion): DualQuaternion
	return DualQuaternion.new(self.Real * other.Real, self.Dual * other.Real + self.Dual * other.Real)
end

function DualQuaternion._MulNumber(self: DualQuaternion, other: number): DualQuaternion
	return DualQuaternion.new(self.Real * other, self.Dual * other)
end

function DualQuaternion._AddDualQuaternion(self: DualQuaternion, other: DualQuaternion): DualQuaternion
	return DualQuaternion.new(self.Real + other.Real, self.Dual + other.Dual)
end

--[=[
	Multiplication metamethod. A Quaternion can be multiplied with another Quaternion,
	a Vector3, or a number.

	```lua
	local quat = quatA * quatB
	local vec = quatA * vecA
	local num = quatA * numA
	```
]=]
function DualQuaternion.__mul(self: DualQuaternion, other: DualQuaternion | number): DualQuaternion
	local t = typeof(other)
	if t == "number" then
		return DualQuaternion._MulNumber(self, other :: any)
	elseif t == "table" and getmetatable(other :: any) == DualQuaternion then
		return DualQuaternion._MulDualQuaternion(self, (other :: any) :: DualQuaternion)
	else
		error(`cannot multiply quaternion with type {t}`, 2)
	end
end

--[=[
	Addition metamethod. A Quaternion can be added with another Quaternion.

	```lua
	local quat = quatA + quatB
	```
]=]
function DualQuaternion.__add(self: DualQuaternion, other: DualQuaternion): DualQuaternion
	local t = typeof(other)
	if t == "table" and getmetatable(other :: any) == DualQuaternion then
		return DualQuaternion._AddDualQuaternion(self, (other :: any) :: DualQuaternion)
	else
		error(`cannot add quaternion with type {t}`, 2)
	end
end

function DualQuaternion.__tostring(self: DualQuaternion): string
	return `Real: {self.Real.X}, {self.Real.Y}, {self.Real.Z}, {self.Real.W}; Dual: {self.Dual.X}, {self.Dual.Y}, {self.Dual.Z}, {self.Dual.W}`
end

--[=[
	@prop identity DualQuaternion
	@readonly
	@within DualQuaternion
]=]

return {
	new = DualQuaternion.new,
	cframe = DualQuaternion.cframe
}
