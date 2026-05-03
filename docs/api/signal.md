# Signal

Module path: `Fluxa.Signal`

Yield-safe signal implementation with behavior close to `RBXScriptSignal`.

## Constructor

#### `Signal.new()`

Creates a new signal instance.

Returns: `SignalType`

```lua
local signal = Fluxa.Signal.new()
```

## Methods

#### `signal:Connect(fn)`

Connects a handler function.

| Parameter | Type | Description |
|-----------|------|-------------|
| `fn` | `(...any) -> ()` | Callback fired when the signal is fired |

Returns: `ConnectionType`

```lua
local connection = signal:Connect(function(a, b)
	print(a, b)
end)
```

#### `signal:Fire(...)`

Fires the signal and schedules connected handlers with the provided arguments.

| Parameter | Type | Description |
|-----------|------|-------------|
| `...` | `any` | Arguments forwarded to handlers |

Handlers are spawned on cached runner coroutines and may yield safely.

#### `signal:DisconnectAll()`

Disconnects all handlers from this signal.

#### `signal:Wait()`

Yields until the next `Fire(...)`, then returns fired arguments.

```lua
local player, state = signal:Wait()
```

#### `signal:Once(fn)`

Connects a one-shot handler that disconnects itself after the first fire.

| Parameter | Type | Description |
|-----------|------|-------------|
| `fn` | `(...any) -> ()` | One-time callback |

Returns: `ConnectionType`

## Connection

Returned by `Connect(...)` and `Once(...)`.

#### `connection:Disconnect()`

Disconnects that specific handler.