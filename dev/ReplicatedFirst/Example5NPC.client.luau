--!strict
-- Example5NPC.client.luau
-- Client-side visual NPC that follows an invisible server NPC for IK and animation testing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- CONFIG: Name of the invisible server NPC to follow
local SERVER_NPC_NAME = "ServerNPC"
-- CONFIG: Name for the client visual NPC
local CLIENT_NPC_NAME = "ClientVisualNPC"

-- Utility: Clone a template NPC from ReplicatedStorage or Workspace
local function getTemplateNPC()
	local template = ReplicatedStorage:FindFirstChild(SERVER_NPC_NAME) or Workspace:FindFirstChild(SERVER_NPC_NAME)
	if not template then
		error("No template NPC found in ReplicatedStorage or Workspace!")
	end
	return template:Clone()
end

-- Utility: Create or get the client visual NPC
local function getOrCreateClientNPC()
	local npc = Workspace:FindFirstChild(CLIENT_NPC_NAME)
	if npc then return npc end
	local clone = getTemplateNPC()
	clone.Name = CLIENT_NPC_NAME
	clone.Parent = workspace.CurrentCamera
	clone:SetAttribute("ClientVisual", true)
	-- -- Make sure it's visible and collidable for the client
	-- for _, part in ipairs(clone:GetDescendants()) do
	-- 	if part:IsA("BasePart") then
	-- 		part.Transparency = 0
	-- 		part.CanCollide = true
	-- 	end
	-- end
	return clone
end

-- Main follow loop
local function followServerNPC()
	local serverNPC = Workspace:FindFirstChild(SERVER_NPC_NAME)
	if not serverNPC then return end
	local clientNPC = getOrCreateClientNPC()
	local serverRoot = serverNPC:FindFirstChild("HumanoidRootPart")
	local clientRoot = clientNPC:FindFirstChild("HumanoidRootPart")
    local clientHumanoid = clientNPC:FindFirstChildOfClass("Humanoid")
	if not (serverRoot and clientRoot and clientHumanoid) then return end

    local animator = clientHumanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = clientHumanoid
    end

	RunService.RenderStepped:Connect(function()
		if not (serverRoot.Parent and clientRoot.Parent) then return end
		-- Copy CFrame and velocity for smooth following
		clientRoot.CFrame = serverRoot.CFrame
		clientRoot.AssemblyLinearVelocity = serverRoot.AssemblyLinearVelocity
		-- Optionally, copy animation state or other attributes here

        -- Update LookTarget every frame
        local radius = 32
        local head = clientNPC:FindFirstChild("Head")
        local root = clientNPC:FindFirstChild("HumanoidRootPart") or clientNPC.PrimaryPart
        if not head or not root then return end
        local closest, closestDist = nil, radius
		for _, other in ipairs(workspace:GetDescendants()) do
			if other:IsA("Humanoid") and other ~= clientHumanoid and other.Health > 0 then
				local otherRoot = other.Parent and other.Parent:FindFirstChild("HumanoidRootPart")
				if otherRoot and otherRoot ~= serverRoot then
					local dist = (head.Position - otherRoot.Position).Magnitude
					-- Angle check: only consider targets in front of the NPC (e.g., within 90 degrees)
					local toOther = (otherRoot.Position - head.Position).Unit
					local forward = head.CFrame.LookVector.Unit
					local dot = forward:Dot(toOther)
					local angle = math.acos(math.clamp(dot, -1, 1))
					local maxAngle = math.rad(90) -- 90 degrees in front
					if dist < closestDist and angle <= maxAngle then
						closest = otherRoot
						closestDist = dist
					end
				end
			end
		end
        local ikControl = clientHumanoid:FindFirstChildOfClass("IKControl")
        if ikControl then
            if closest then
                local att = closest:FindFirstChild("RootAttachment") or closest:FindFirstChild("RootRigAttachment")
                if att then
                    ikControl.Target = att
                    ikControl.Enabled = true
                else
                    ikControl.Enabled = false
                end
            else
                ikControl.Enabled = false
            end
        end
	end)
end

-- Hide the server NPC for the local client
local function hideServerNPC()
	local serverNPC = Workspace:FindFirstChild(SERVER_NPC_NAME)
	if not serverNPC then return end
	for _, part in ipairs(serverNPC:GetDescendants()) do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = 1
			part.CanCollide = false
		end
	end
end

task.wait(6)

hideServerNPC()
followServerNPC()

-- Now you can add IKControls or other client-only logic to the client NPC!