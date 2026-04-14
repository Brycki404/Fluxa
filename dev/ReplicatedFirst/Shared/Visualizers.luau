local DebrisService = game:GetService("Debris")
local module = {}
local elements = {}

function module.Visualize(v3, origin, color, thickness, transparency)
	if not workspace:GetAttribute("DebugMode") then return nil end
	
	local origin = origin or Vector3.new()
	local part = Instance.new("Part")
	part.Name = "Vector"
	part.BrickColor = color or BrickColor.Random() 
	part.Transparency = transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Size = Vector3.new(thickness or 0.2, thickness or 0.2, v3.magnitude)
	part.CFrame = CFrame.new((origin+v3/2), origin+v3)
	part.Locked = true
	part.Parent = workspace.DebugVisuals
	table.insert(elements, part)
	return part
end

function module.VisualizeCF(cf)
	if not workspace:GetAttribute("DebugMode") then return nil end
	
	local x = module.Visualize(cf.p, nil, BrickColor.White(), 0.1, 0.5)
	local y = module.Visualize(cf.lookVector, cf.p, BrickColor.Blue())
	local z = module.Visualize(cf.upVector, cf.p, BrickColor.Green())
	local w = module.Visualize(cf.rightVector, cf.p, BrickColor.Red())

	local model = Instance.new("Model", workspace)
	model.Name = "CFrame"
	x.Parent = model
	x.Name = "Position"
	y.Parent = model
	y.Name = "lookVector"
	z.Parent = model
	z.Name = "upVector"
	w.Parent = model
	w.Name = "rightVector"
	table.insert(elements, model)
	return model
end

function module.VisualizeRay(origin, direction, params, color, visualizerStayTime, hitColor)
	if not workspace:GetAttribute("DebugMode") then return nil end
	
	color = (color == nil) and BrickColor.Green() or color
	hitColor = (hitColor == nil) and BrickColor.Red() or hitColor
	visualizerStayTime = visualizerStayTime == nil and 3 or visualizerStayTime
	
	local ray = module.Visualize(direction, origin, color, 0.05)
	table.insert(elements, ray)
	local result = workspace:Raycast(origin, direction, params or RaycastParams.new())
	local hit = Instance.new("Part", ray)
	hit.Name = "Hit"
	hit.BrickColor = hitColor
	hit.Anchored = true
	hit.CanCollide = false
	hit.CanTouch = false
	hit.CanQuery = false
	hit.Transparency = 0.3
	ray.Transparency = 0.3
	if result then
		hit.CFrame = CFrame.new(result.Position, result.Position + result.Normal)
	end
	
	hit.Size = Vector3.new(0.5, 0.5, 0)
	
	DebrisService:AddItem(ray, visualizerStayTime)
	return ray
end

function module.ShowOrigin()
	if not workspace:GetAttribute("DebugMode") then return nil end
	
	local cf = CFrame.new()
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(1, 1)
	local label = Instance.new("TextLabel", billboard)
	label.Size = UDim2.fromScale(0.5, 0.5)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint", label)
	constraint.MaxTextSize = 100
	constraint.MinTextSize = 100

	module.Visualize(cf.p, nil, BrickColor.White(), 0.1, 0.5)
	local z = module.Visualize(-cf.lookVector, cf.p, BrickColor.Blue())
	local y = module.Visualize(cf.upVector, cf.p, BrickColor.Green())
	local x = module.Visualize(cf.rightVector, cf.p, BrickColor.Red())
	billboard:Clone().Parent = z
	z.BillboardGui.TextLabel.Text = "+Z"
	z.BillboardGui.TextLabel.Position = UDim2.fromScale(0.3, 0.05)
	billboard:Clone().Parent = y
	y.BillboardGui.TextLabel.Text = "+Y"
	y.BillboardGui.TextLabel.Position = UDim2.fromScale(0.5, -0.2)
	billboard:Clone().Parent = x
	x.BillboardGui.TextLabel.Text = "+X"
	x.BillboardGui.TextLabel.Position = UDim2.fromScale(0.6, 0.05)
end

function module.ClearAll()
	for i, element in ipairs(elements) do
		element:Destroy()
		elements[i] = nil
	end
end

return module