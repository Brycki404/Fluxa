--NOTE: ATTRIBUTES CANNOT HAVE SPACES (' ') IN THEIR NAMES
--IF TABLE: GET MADE INTO FOLDERS
--ELSE: GET MADE INTO ATTRIBUTE... unless specified somewhere to make a custom exception
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local table = require(ReplicatedFirst.Shared.Table)
local TableUtil = require(ReplicatedFirst.Shared.TableUtil)
local Backpacks = require(ReplicatedFirst.Shared.Backpacks)

local templates = {}

templates.Vector2 = {	
	X = 0;
	Y = 0;
}

templates.Vector3 = {
	X = 0;
	Y = 0;
	Z = 0;
}

--identity cframe
templates.CFrame = {
	X = 0;
	Y = 0;
	Z = 0;
	R00 = 1; R01 = 0; R02 = 0;
	R10 = 0; R11 = 1; R12 = 0;
	R20 = 0; R21 = 0; R22 = 1;
}

-- Hexadecimal FF represents the maximum value for an 8-bit binary number.
-- 0xFF = 255
-- 0x00 = 0
-- meaning 0-255 for each channel in RGB, so 24-bits total or 3 bytes
templates.Color3_Hexadecimal = {	
	R = 0;
	G = 0;
	B = 0;
}

templates.GamepassDataTemplate = {	
	IsActive = true;
	GiftedByUserId = 0;
}


return templates