# Getting Started

![Fluxa](images/FLUXA\_Transparent\_White.png)

### What is Fluxa?

[Fluxa](https://github.com/Brycki404/Fluxa) is a complete runtime substitute for Roblox's built-in `Animator` and `AnimationController`. Instead of relying on the limitations of Roblox's animation system, Fluxa lets you:

* Load `KeyframeSequence` instances directly
* Build procedural animation logic in code
* Create runtime blend trees
* Implement custom state machines
* Apply IK, retargeting, and procedural layers
* Write directly to `Motor6D.Transform`, `AnimationConstraint.Transform`, and `Bone.Transform`
* Build animation systems similar to Unreal Animation Blueprints or Unity Playables

This documentation is designed for developers who want to:

* Use `KeyframeSequence` assets as an authoring source
* Evaluate animation poses in Lua every frame
* Build blend trees, state machines, and runtime animation graphs entirely in code
* Apply final poses directly to `Motor6D.Transform`, `AnimationConstraint.Transform`, and `Bone.Transform`
* Add procedural IK, retargeting, and additive layers without visual editors

### This tool does not alter the process of animating at all.

Fluxa is designed for scripters who want full control over animation behavior at runtime — something Roblox's built-in Animator does not provide.

### Project Status Notice

Fluxa is currently in active development, and the API, structure, and features are subject to change as the library evolves. Full documentation will be added once the API stabilizes. For now, you can explore the included demo place to learn the basics. Additional examples will be added for every feature in future updates.

### Is Fluxa redundant now that Roblox has an Animation Graph Editor?

No — and here's why.

Roblox's new Animation Graph System (currently in beta) is a visual authoring tool. It lets animators build graphs inside an Animation asset, similar to Unity's Animator Controller. But it is not a runtime animation engine.

**Roblox's Animation Graph System:**

* Runs inside the Animator
* Cannot be modified at runtime
* Cannot generate graphs procedurally
* Cannot blend multiple graphs together
* Cannot perform IK or retargeting
* Cannot override Motor6D, Bone, and AnimationConstraint transforms
* Cannot replace the Animator
* Only exposes parameter updates, not graph control

**Fluxa:**

* Runs outside the Animator
* Fully scriptable
* Fully runtime-driven
* Supports procedural animation
* Supports custom IK and retargeting solvers
* Supports custom blend trees
* Supports runtime state machines
* Writes directly to Motor6D.Transform, Bone.Transform, and AnimationConstraint.Transform
* Lets you build animation logic in pure code

In short:

> Roblox's Graph Editor = visual authoring tool for animators

> Fluxa = runtime animation engine for programmers

They solve different problems and complement each other rather than overlap.

If you have questions, join the Discord server: [https://discord.gg/ubBQapeyvX](https://discord.gg/ubBQapeyvX)
