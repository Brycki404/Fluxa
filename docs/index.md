# Fluxa

Fluxa is a code-driven animation system for Roblox that replaces runtime `Animator` and `AnimationController` usage with a modular, deterministic animation pipeline.

This documentation is designed for developers who want to:

- use `KeyframeSequence` assets as authoring source
- evaluate animation poses in Lua every frame
- build blend trees, state machines, and runtime animation graphs entirely in code
- apply final poses directly to `Motor6D.Transform`
- add procedural IK, retargeting, and additive layers without visual editors

---

## Installation

### Wally

Add Fluxa to your `wally.toml` dependencies:

```toml
[dependencies]
fluxa = "brycki404/fluxa@latest"
```

Then run:

```bash
wally install
```

### Rojo

If you want to develop locally, point your `default.project.json` or Rojo project at the `src/` folder.

Example:

```json
{
  "name": "fluxa",
  "tree": {
    "$path": "src"
  }
}
```

### Manual

If you're not using Wally or Rojo, the core modules are under `src/` and can be copied into your place or package structure.

---

## Usage Overview

### Key concepts

- `AnimationAsset` converts `KeyframeSequence` data into fast sampled pose data.
- `Pose` is a dictionary of joint names to `CFrame` transforms.
- `AnimationPlayer` drives an `AnimationAsset` in time with looping, speed, and event support.
- `BlendTree` defines code-driven animation blends.
- `StateMachine` evaluates high-level animation state transitions.
- `AnimationBlueprint` is the runtime coordinator that produces the final pose.
- `UniversalJointWriter` writes the final pose into a character via `Motor6D.Transform` or `Bone.Transform`.

---

## Module API Summary

### AnimationAsset

Create a new asset from a `KeyframeSequence`:

```lua
local animationSequence = ReplicatedStorage.Animations.WalkForward
local asset = AnimationAsset.new(animationSequence)
```

Key methods:

- `asset:Sample(time)` → returns `{ Transforms = { [jointName] = CFrame }, Curves = { [name] = number } }`
- `asset:GetLength()` → animation duration in seconds
- `asset:GetEventsAt(time, window?)` → animation event table

### Pose

Create and manipulate pose objects:

```lua
local poseA = Pose.new(sampleA.Transforms)
local poseB = Pose.new(sampleB.Transforms)
local blended = poseA:Lerp(poseB, 0.5)
```

Available methods:

- `:Clone()`
- `:Lerp(otherPose, alpha)`
- `:Additive(addPose, weight)`
- `:ApplyMask(maskTable)`

### AnimationPlayer

Create a player for an `AnimationAsset`:

```lua
local player = AnimationPlayer.new(asset, {
    Speed = 1,
    Loop = true,
    FadeInTime = 0.2,
    FadeOutTime = 0.2,
})

player:Play()
local sample = player:Update(deltaTime)
```

### BlendTree

Blend trees are just Lua functions that return weights.

Example:

```lua
function LocomotionBlendTree(params)
    return {
        Idle = 1 - params.Speed,
        Walk = params.Speed,
        Run = params.Speed * params.Speed,
    }
end
```

### StateMachine

States are defined with update functions, enter/exit callbacks, and blend tree references.

### AnimationBlueprint

The blueprint owns runtime parameters and evaluates state transitions, blend trees, and final pose generation.

---

## Example: 4-Direction Locomotion Setup

Place your directional `KeyframeSequence` assets in `ReplicatedStorage.Animations` with names like:

- `Idle`
- `WalkForward`
- `WalkRight`
- `WalkBackward`
- `WalkLeft`

Then use the package modules to create a small locomotion driver.

```lua
local X_WEIGHT: number = 0.35
local Z_WEIGHT: number = 0.65

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationAsset = require(ReplicatedStorage.Packages.fluxa.AnimationAsset)
local AnimationPlayer = require(ReplicatedStorage.Packages.fluxa.AnimationPlayer)
local Pose = require(ReplicatedStorage.Packages.fluxa.Pose)
local UniversalJointWriter = require(ReplicatedStorage.Packages.fluxa.UniversalJointWriter)

local animAssets = {
    Idle = AnimationAsset.new(ReplicatedStorage.Animations.Idle);
    Forward = AnimationAsset.new(ReplicatedStorage.Animations.WalkForward);
    Right = AnimationAsset.new(ReplicatedStorage.Animations.WalkRight);
    Backward = AnimationAsset.new(ReplicatedStorage.Animations.WalkBackward);
    Left = AnimationAsset.new(ReplicatedStorage.Animations.WalkLeft);
}

local animPlayers = {
    Idle = AnimationPlayer.new(animAssets.Idle);
    Forward = AnimationPlayer.new(animAssets.Forward);
    Right = AnimationPlayer.new(animAssets.Right);
    Backward = AnimationPlayer.new(animAssets.Backward);
    Left = AnimationPlayer.new(animAssets.Left);
}

local jointMap, retarget = UniversalJointWriter.BuildJointMap(character)

-- Start with Idle
if animPlayers.Idle then
	animPlayers.Idle:Play()
end

local RunService = game:GetService("RunService")
local blendedPose = Pose.new({})

RunService.RenderStepped:Connect(function(deltaTime)
	local raw = humanoid.MoveDirection
	local rootCF = humanoidRootPart.CFrame
	local right = rootCF.RightVector
	local forward = rootCF.LookVector

	-- flatten to XZ
	right = Vector3.new(right.X, 0, right.Z).Unit
	forward = Vector3.new(forward.X, 0, forward.Z).Unit

	local moveX = raw:Dot(right)
	local moveZ = raw:Dot(forward)

	-- 2D blend vector
	local dir = Vector2.zero
	local blendVec = Vector2.new(moveX, moveZ)
	local mag = math.min(1, blendVec.Magnitude)
	local idleWeight = 1 - mag
	local movePortion = 0+mag -- total weight avilable for F/B/L/R

	if mag > 0 then
		dir = blendVec / mag
	end

	local weightedX = dir.X * X_WEIGHT
	local weightedZ = dir.Y * Z_WEIGHT

	local _angle = math.atan2(weightedX, weightedZ)
	local forwardRaw = math.max(0, weightedZ)
	local backRaw    = math.max(0, -weightedZ)
	local rightRaw   = math.max(0, weightedX)
	local leftRaw    = math.max(0, -weightedX)

	local dirSum = forwardRaw + backRaw + rightRaw + leftRaw
	local forwardWeight, backWeight, rightWeight, leftWeight = 0, 0, 0, 0
	if dirSum > 0 then
		forwardWeight = movePortion * (forwardRaw / dirSum)
		backWeight    = movePortion * (backRaw    / dirSum)
		rightWeight   = movePortion * (rightRaw   / dirSum)
		leftWeight    = movePortion * (leftRaw    / dirSum)
	end

	local blendWeights = {
		["Idle"] = idleWeight;
		["Forward"] = forwardWeight;
		["Right"] = rightWeight;
		["Backward"] = backWeight;
		["Left"] = leftWeight;
	}

	-- Determine direction based on input
	local directionNames = { "Idle", "Forward", "Right", "Backward", "Left" }
	for _i: number, directionName: string in ipairs(directionNames) do
		if blendWeights[directionName] == 0 then
			if animPlayers[directionName] and animPlayers[directionName].Playing then
				animPlayers[directionName]:Stop()
			end
		elseif animPlayers[directionName] and not animPlayers[directionName].Playing then
			animPlayers[directionName]:Play()
		end
	end

	local blended: { [string]: CFrame } = {}
	local hasBase: { [string]: boolean } = {}

	for directionName, weight in pairs(blendWeights) do
		if weight > 0 then
			local aplr = animPlayers[directionName]
			if aplr and aplr.Playing then
				local sample = aplr:Update(deltaTime)

				for joint, cf in pairs(sample.Transforms) do
					if not hasBase[joint] then
						-- first pose becomes the base
						blended[joint] = cf
						hasBase[joint] = true
					else
						-- lerp from current blended to this sample by weight
						blended[joint] = blended[joint]:Lerp(cf, weight)
					end
				end
			end
		end
	end

	blendedPose = Pose.new(blended)
	UniversalJointWriter.ApplyPose(jointMap, retarget, blendedPose.Data)
end)

```

---

## GitHub Pages Setup

This repository uses the `docs/` folder for GitHub Pages content. To publish:

1. Push this repo to GitHub.
2. In GitHub repo settings, enable Pages.
3. Set the source to `docs/`.
4. Your documentation will be available at:

```
https://<username>.github.io/Fluxa/
```

---

## Notes

Fluxa is actively developed, so the public API may change. The docs here are intended to capture the current runtime system and provide a starting point for developers.