# FluxaBindingCatalog

Module path: `Fluxa.FluxaBindingCatalog`

`FluxaBindingCatalog` is a data container for modular animation bindings. It stores:

> Note: Binding resolution is independent of playback. All playback and stepping is managed globally by `FluxaService` on the client.

* binding sources
* fallback chains
* initial track bindings
* named sets like `Unarmed`, `Rifle`, or `Aiming`
* optional named layers for additive override stacking

## Constructor

#### `FluxaBindingCatalog.new(definition)`

Creates a catalog instance from a definition table.

Definition fields:

* `Version`
* `Sources`
* `Fallbacks`
* `InitialTrackBindings`
* `Sets`
* `Layers`

## Methods

#### `catalog:GetSource(bindingId)`

Returns the raw source for a binding id.

#### `catalog:GetFallbackBinding(bindingId)`

Returns the fallback binding id for a binding, if one exists.

#### `catalog:GetInitialTrackBinding(trackName)`

Returns the starting binding id for a track name.

#### `catalog:GetInitialTrackBindings()`

Returns a cloned map of the initial track bindings.

#### `catalog:GetSet(setName)`

Returns the raw override map for a named set.

#### `catalog:GetSetBindings(setName, includeInitialBindings?)`

Returns a merged map of track bindings for the set. By default this overlays the set onto the initial bindings.

#### `catalog:GetLayer(layerName)`

Returns a raw named layer override map.

#### `catalog:ResolveBindings(layerNames, includeInitialBindings?)`

Resolves a final `trackName -> bindingId` map by layering multiple named overrides in order.

Later layers win over earlier layers.

#### `catalog:HasBinding(bindingId)`

Returns whether the catalog defines the binding id.