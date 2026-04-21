# Installation

#### Wally

Add Fluxa to your `wally.toml` dependencies:

```toml
[dependencies]
fluxa = "brycki404/fluxa@3.0.0"
```

Then run:

```
wally install
```

#### Rojo

If you want to develop locally, point your `default.project.json` or Rojo project at the `src/` folder.

```json
{
  "name": "fluxa",
  "tree": {
    "$path": "src"
  }
}
```

#### Manual

If you're not using Wally or Rojo, the core modules are under `src/` and can be copied into your place or package structure.

For Studio users, you can get the latest `src/` here:
* (fluxa-dev uncopylocked) [https://www.roblox.com/games/107928648886650/Fluxa-Dev](https://www.roblox.com/games/107928648886650/Fluxa-Dev)
