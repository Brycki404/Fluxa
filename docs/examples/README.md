# Examples

The included examples escalate from raw API usage to controller workflows and modular binding-set swapping.

| Example | What it demonstrates |
|---------|---------------------|
| [Example 1](example-1.md) | Raw API: 2D directional blend, no framework |
| [Example 2](example-2.md) | Manual state machine: locomotion, momentum, phase sync, turn lean |
| [Example 3](example-3.md) | Full FluxaController: layers, blend trees, one-shots, replication |
| [Example 4](example-4.md) | Binding catalogs and runtime track swapping with FluxaBindingSetManager |

To run an example in the dev place, set the `StarterPlayerScripts/Client.ex` attribute to `1`, `2`, or `3`.

Example 4 is intentionally not wired into the dev place by default. It expects a dedicated `ReplicatedStorage.Example4Animations_R15` folder that includes the extra bindings referenced by its catalog.
