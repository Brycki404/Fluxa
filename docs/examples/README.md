# Examples

The included examples escalate from raw API usage to controller workflows and modular binding-set swapping.

| Example | What it demonstrates |
|---------|---------------------|
| [Example 1](example-1.md) | Raw API: 2D directional blend, no framework |
| [Example 2](example-2.md) | Manual state machine: locomotion, momentum, phase sync, turn lean |
| [Example 3](example-3.md) | Full FluxaController: layers, blend trees, one-shots, replication |
| [Example 4](example-4.md) | Binding catalogs and runtime track swapping with FluxaBindingSetManager |

## Running examples in the dev place

Set the `StarterPlayerScripts/Client.ex` attribute to:

* `1` for Example 1
* `2` for Example 2
* `3` for Example 3
* `4` for Example 4

### Setup notes for Example 4

Example 4 is not wired by default and expects additional animations referenced by its binding catalog.

1. Create `ReplicatedStorage/Example4Animations_R15`.
2. Add the animations used by the Example 4 binding sets (for example idle/walk/run and rifle variants).
3. Set `StarterPlayerScripts/Client.ex` to `4`.
4. Run the dev place.
