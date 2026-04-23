--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local exs = ReplicatedStorage:WaitForChild("Examples")
local ex1 = require(exs:WaitForChild("Example1"))
local ex2 = require(exs:WaitForChild("Example2"))
local ex3 = require(exs:WaitForChild("Example3"))
local ex5 = require(exs:WaitForChild("Example5"))

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local EXAMPLE_ATTRIBUTE = "ex"
local defaultExample: number = 3
local thisExample: number = defaultExample
local currentExampleModule = nil

local function getSelectedExampleId(): number
	local value = script:GetAttribute(EXAMPLE_ATTRIBUTE)
	if type(value) == "number" then
		return value
	end
	return defaultExample
end

local function getExampleModule(exampleId: number)
	if exampleId == 1 then
		return ex1
	elseif exampleId == 2 then
		return ex2
	elseif exampleId == 3 then
		return ex3
	elseif exampleId == 5 then
		return ex5
	end
	return nil
end

local function destroyCurrentExample()
	if currentExampleModule ~= nil then
		currentExampleModule:Destroy()
		currentExampleModule = nil
	end
end

local function characterRemoving(_character: Model)
	local lastExample: number = 0 + thisExample
	local lastModule = getExampleModule(lastExample)
	if lastModule ~= nil and lastModule.OwnsCharacterLifecycle ~= true then
		lastModule:Destroy()
		if currentExampleModule == lastModule then
			currentExampleModule = nil
		end
	end
end

local function characterAdded(character: Model)
	local selectedExampleId = getSelectedExampleId()
	local selectedModule = getExampleModule(selectedExampleId)
	thisExample = selectedExampleId
	if selectedModule == nil then
		return
	end

	if selectedModule.OwnsCharacterLifecycle == true then
		if currentExampleModule ~= selectedModule then
			destroyCurrentExample()
			currentExampleModule = selectedModule
			selectedModule:Start(script)
		end
		return
	end

	local humanoid: Humanoid = character:WaitForChild("Humanoid") :: Humanoid
	destroyCurrentExample()
	currentExampleModule = selectedModule
	if selectedExampleId == 1 then
		ex1:Start(script)
	elseif selectedExampleId == 2 then
		humanoid.AutoRotate = false
		ex2:Start(script)
	elseif selectedExampleId == 3 then
		humanoid.AutoRotate = false
		ex3:Start(script)
	elseif selectedExampleId == 5 then
		humanoid.AutoRotate = false
		ex5:Start(script)
	end
end

local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
characterAdded(character)
LocalPlayer.CharacterAdded:Connect(characterAdded)
LocalPlayer.CharacterRemoving:Connect(characterRemoving)
script:GetAttributeChangedSignal(EXAMPLE_ATTRIBUTE):Connect(function()
	local selectedExampleId = getSelectedExampleId()
	if selectedExampleId == thisExample then
		return
	end
	destroyCurrentExample()
	thisExample = selectedExampleId
	local currentCharacter = LocalPlayer.Character
	if currentCharacter ~= nil then
		characterAdded(currentCharacter)
	end
end)