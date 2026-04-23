# Example 4

Example 4 demonstrates Fluxa's modular binding workflow.

It builds on the controller-centric Example 3 architecture, but moves content selection out of `FluxaController` and into reusable binding modules:

* `FluxaBindingCatalog`
* `FluxaBindingSetManager`
* `FluxaAssetManager`

## What it demonstrates

1. Stable track names in blend trees.
2. Runtime track swapping underneath those names.
3. Shared binding ids replicated across clients.
4. Deterministic client-side resolution from binding id to `AnimationAsset`.
5. Explicit phase policy on swap.
6. Layered override stacks such as weapon or status layers.

## Why it is separate from Example 3

Example 4 expects additional content, such as alternate weapon-specific bindings like `RifleWalk` and `RifleAttack`.

Because the dev place does not currently ship those animations, Example 4 is not wired into the default demo selector.

## Required assets

Create a `ReplicatedStorage.Example4Animations_R15` folder containing the bindings referenced by `Example4BindingCatalog`.

At minimum, the sample catalog expects names like:

* `Idle`
* `Walk`
* `Run`
* `SlowWalk`
* `Jump`
* `Fall`
* `Land`
* `Climb`
* `Attack`
* `RifleIdle`
* `RifleWalk`
* `RifleRun`
* `RifleSlowWalk`
* `RifleAttack`

## Runtime flow

1. `FluxaBindingCatalog` declares binding ids, sources, fallbacks, and named sets.
2. `FluxaBindingSetManager` resolves and caches those bindings using `FluxaAssetManager`.
3. `FluxaController` keeps blend trees fixed to track names like `Walk` and `Attack`.
4. When the local example toggles sets, it swaps track bindings and replicates only the resulting binding ids plus normal controller state.

## Swap policy

Example 4 configures locomotion tracks like `Walk`, `Run`, and `SlowWalk` with `PreservePhaseOnSwap = true` so foot phase stays coherent when the weapon layer comes and goes.

One-shot style tracks such as `Attack` are configured with `PreservePhaseOnSwap = false` so swaps reset cleanly.

## Layered overrides

Example 4 demonstrates the intended scalable pattern:

* base track bindings come from the catalog's initial bindings
* `EquippedWeapon` is applied as a higher-priority runtime layer
* removing that layer automatically unwinds back to the base bindings

The same pattern can be extended with additional layers such as `StatusEffect:Wounded` or `Mount:Horse`, with later layers winning when they touch the same track name.

## Practical takeaway

Example 4 is the recommended shape for large games that need stance sets, weapon sets, style sets, or other content swaps without touching the animation graph.