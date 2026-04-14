--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local exs = ReplicatedStorage:WaitForChild("Examples")
local ex1 = require(exs:WaitForChild("Example1"))
local ex2 = require(exs:WaitForChild("Example2"))
local ex3 = require(exs:WaitForChild("Example3"))

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local EXAMPLE_ATTRIBUTE = "ex"
local defaultExample: number = 3
local thisExample: number = defaultExample

local function characterRemoving(_character: Model)
	local lastExample: number = 0 + thisExample
	if lastExample == 1 then
		ex1:Destroy()
	elseif lastExample == 2 then
		ex2:Destroy()
	elseif lastExample == 3 then
		ex3:Destroy()
	end
end

local function characterAdded(character: Model)
	local humanoid: Humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.AutoRotate = false

	local value = script:GetAttribute(EXAMPLE_ATTRIBUTE)
	if type(value) == "number" then
		thisExample = value
	else
		thisExample = defaultExample
	end
	if thisExample == 1 then
		ex1:Start(script)
	elseif thisExample == 2 then
		ex2:Start(script)
	elseif thisExample == 3 then
		ex3:Start(script)
	end
end

local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
characterAdded(character)
LocalPlayer.CharacterAdded:Connect(characterAdded)
LocalPlayer.CharacterRemoving:Connect(characterRemoving)