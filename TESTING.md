# Testing Setup

## Using Rojo to Test in Studio

1. **Start Rojo:**
   ```bash
   rojo serve
   ```

2. **In Roblox Studio:**
   - Install the Rojo plugin if not already installed
   - Create a new empty place or open an existing one
   - Click "Rojo" → "Connect" in the plugin toolbar
   - Choose "default" configuration

3. **Place Structure:**
   - `ReplicatedStorage.AnimationSystem` — All animation system modules
   - `StarterPlayer.StarterPlayerScripts.TestScript` — Client test script

## File Locations

- Animation modules: `src/shared/AnimationSystem/`
- Client test script: `src/client/init.client.luau`
- Server scripts: `src/server/` (deployed to ServerScriptService)

## Test Script

The client test script loads automatically on player spawn. Controls:
- **E** — Walk Forward
- **Q** — Walk Backward
- **D** — Walk Right
- **A** — Walk Left

Place your KeyframeSequences in ReplicatedStorage.Animations for the test script to find them.
