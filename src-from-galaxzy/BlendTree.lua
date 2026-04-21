--!strict
-- BlendTree: code-driven blend tree helpers for 1D, 2D and custom blend weights.

local BlendTree = {}

function BlendTree.Simple1D(params: { Value: number }, nodes: { [string]: (number) -> number })
	local weights: { [string]: number } = {}
	for name, fn in pairs(nodes) do
		weights[name] = fn(params.Value)
	end
	return weights
end

function BlendTree.Simple2D(params: { X: number, Y: number }, nodes: { [string]: (number, number) -> number })
	local weights: { [string]: number } = {}
	for name, fn in pairs(nodes) do
		weights[name] = fn(params.X, params.Y)
	end
	return weights
end

return BlendTree