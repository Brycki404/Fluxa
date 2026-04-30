# FluxaBindingSetManager

Module path: `Fluxa.FluxaBindingSetManager`

`FluxaBindingSetManager` is the high-level helper that connects binding catalogs, asset loading, and controllers.

> Note: Binding set application is independent of playback. All playback and stepping is managed globally by `FluxaService` on the client.

It is responsible for:

* source registration
* loading/caching assets through `FluxaAssetManager`
* resolving binding ids, including fallbacks
* attaching a binding resolver to a `FluxaController`
* applying named sets to track names
* maintaining layered override stacks and unwinding them cleanly

## Constructor

#### `FluxaBindingSetManager.new(options)`

Required options:

* `Catalog`

Optional options:

* `AssetManager`
* `SourceContainer`
* `SourceLookup`

## Methods

#### `manager:RegisterSource(name, source)`

Registers one named source instance or id.

#### `manager:RegisterSourcesFromContainer(container)`

Registers all `Animation` and `KeyframeSequence` children from a container.

#### `manager:GetOrLoad(bindingId)`

Resolves a binding id into a cached or newly loaded asset. Returns `asset, resolvedBindingId`.

If the primary binding cannot load, the manager attempts the catalog fallback chain.

#### `manager:AttachController(controller)`

Attaches a `SetTrackBindingResolver` callback to a controller so replicated binding ids can be resolved locally.

#### `manager:LoadTrack(controller, trackName, trackConfig)`

Loads one track on a controller using `trackConfig.BindingId`.

If the track already exists, the manager swaps it through `controller:SetTrackAsset(...)` and honors `trackConfig.PreservePhaseOnSwap`.

#### `manager:LoadTracks(controller, trackConfigs)`

Loads many tracks from a `trackName -> trackConfig` map.

#### `manager:ApplySet(controller, setName, trackConfigs?)`

Applies a named set to the controller by loading all resolved track bindings for that set.

This is the main helper for weapon sets, stance sets, and other modular swaps.

#### `manager:SetBindingLayer(layerName, bindings, controller?, trackConfigs?)`

Adds or replaces a runtime binding override layer.

If a controller is supplied, the manager immediately reapplies the resolved bindings so the layer takes effect.

#### `manager:SetCatalogLayer(layerName, catalogLayerName, controller?, trackConfigs?)`

Adds a runtime layer from a catalog-defined set or layer name.

#### `manager:RemoveBindingLayer(layerName, controller?, trackConfigs?)`

Removes a runtime binding layer.

If a controller is supplied, the manager automatically reapplies the remaining stack so the previous bindings unwind cleanly.

#### `manager:GetResolvedBindings()`

Returns the currently resolved `trackName -> bindingId` map after applying active layers in order.

#### `manager:ApplyActiveLayers(controller, trackConfigs?)`

Applies the current layered override stack to a controller.