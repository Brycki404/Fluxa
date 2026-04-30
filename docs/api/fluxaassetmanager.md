# FluxaAssetManager

Module path: `Fluxa.FluxaAssetManager`

`FluxaAssetManager` loads and caches `AnimationAsset` instances by name. It accepts raw `AnimationId` values, `Animation` instances, or `KeyframeSequence` instances and converts them into Fluxa-ready assets.

Internally, the manager normalizes all supported authoring inputs into `AnimationAsset` instances. Consumers reading from the manager only ever receive parsed `AnimationAsset` values. Playback and stepping of assets is managed globally by `FluxaService` on the client.

## Supported sources

* `number` animation id
* `string` animation id, including `rbxassetid://12345`
* `Animation` instance
* `KeyframeSequence` instance
* existing `AnimationAsset` instance

## Constructor

#### `FluxaAssetManager.new()`

Creates a new asset manager instance.

## Methods

#### `manager:Load(name, source, options?)`

Loads one asset and stores it under `name`.

Options:

* `DestroySourceInstance` - destroys the source instance after load when true
* `Overwrite` - allows replacing an existing cached asset when true

#### `manager:LoadMany(entries, options?)`

Loads many assets from either:

* a map of `name -> source`
* an array of `{ Name = string, Source = any, Options = ... }`

#### `manager:LoadFromContainer(container, options?)`

Loads all `Animation` and `KeyframeSequence` children from a container.

#### `manager:Get(name)`

Returns a cached asset, or `nil`.

#### `manager:GetAll()`

Returns a cloned map of all cached assets.

#### `manager:Has(name)`

Returns whether an asset is cached.

#### `manager:Unload(name)`

Removes a cached asset reference.

#### `manager:Clear()`

Clears the entire cache.