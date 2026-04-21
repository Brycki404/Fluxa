# BlendTree

Module path: `Fluxa.BlendTree`

`BlendTree` provides helper utilities for constructing weighted blend trees used by `FluxaController`.

In most cases you do not interact with this module directly. Instead you pass blend tree functions to `FluxaController.new` via the `BlendTrees` config key, or register them at runtime with `controller:CreateBlendTree(name, fn)`.

### Blend tree functions

A blend tree function has the signature:

```lua
(controller: ControllerInstance, dt: number) -> { [string]: number }
```

It reads driver values from the controller and returns a table mapping track names to target weights. The weights do not need to sum to `1`; the layer normalizes them after.

### Example: 1D locomotion blend

```lua
local function LocomotionTree(ctrl, dt)
    local speed = ctrl:GetLayerDriver("Base", "Speed") or 0
    local isMoving = speed > 0.5

    return {
        Idle     = isMoving and 0 or 1,
        Walk     = isMoving and math.clamp(1 - (speed - 5) / 10, 0, 1) or 0,
        Run      = isMoving and math.clamp((speed - 5) / 10, 0, 1)      or 0,
    }
end

controller:CreateBlendTree("Locomotion", LocomotionTree)
```

### Example: 2D directional blend

```lua
local function DirectionalTree(ctrl, dt)
    local moveDir = ctrl:GetGlobalDriver("MoveDirection") or Vector2.zero
    local x, y = moveDir.X, moveDir.Y

    return {
        Forward   = math.clamp( y, 0, 1),
        Backward  = math.clamp(-y, 0, 1),
        StrafeLeft  = math.clamp(-x, 0, 1),
        StrafeRight = math.clamp( x, 0, 1),
    }
end
```

For full documentation of the `BlendTree` module API, see the [Fluxa GitBook](https://brycki404.gitbook.io/fluxa/api-reference/blendtree).
