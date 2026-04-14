local module = {}

function lerp(start: T, finish: T, percent: number): T
	assert(typeof(start) == typeof(finish), "start and finish must be the same type")
	assert(typeof(start) == "CFrame" or typeof(start) == "Vector3" or typeof(start) == "Vector2" or typeof(start) == "number", "start must be a CFrame, Vector3, Vector2, or number")
	return (1 - percent) * start + percent * finish
end

-- Very snappy: 20-30
-- Normal smoothing: 10
-- Slow easing: 3-5
-- Very floaty: 1
function exp_decay_alpha(smoothing: number, dt: number): number
	if smoothing <= 0 then
		smoothing = 0.001
	end
	return 1 - math.exp(-smoothing * dt)
end

function exp_decay_lerp(start: T, finish: T, smoothing: number, dt: number): T
	local alpha = exp_decay_alpha(smoothing, dt)
	local result = lerp(start, finish, alpha)
	return result
end

module.lerp = lerp
module.exp_decay_alpha = exp_decay_alpha
module.exp_decay_lerp = exp_decay_lerp

return module