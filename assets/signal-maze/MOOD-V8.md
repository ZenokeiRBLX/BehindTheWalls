# Signal Maze version 8: mood pass

Status: applied in Map Creation (`126262358232325`) on November 16, 2026. The map is `Workspace.SignalMaze` with `BuildVersion` 8. Save the place to keep it.

This pass changes how the version 7 map ([SIZED-V7.md](SIZED-V7.md)) looks, aiming at a reference image: a wet flesh corridor lined with buried CRTs, red screens, a lit red-grey haze down the corridor, ground mist on dark water, and floating dust. It does not move any geometry, screen, collision box, or spawn point.

`mood-pass.luau` is the recipe. On the first run it copies the version 7 map into `ServerStorage.SignalMaze_V8Backup`, with the `MonsterTV` tags removed from the copy. It also stores the old Lighting children and, as folder attributes, the old Lighting, water, flesh tiling, and ceiling values. Every later run sets absolute values from its constants, so it can be re-run safely while tuning. The randomness is seeded (`SEED = 20261116`).

## What it does

- **Ceiling:** turned back on (`Transparency` 0, `CastShadow` on) and darkened to `52, 34, 36`. It had been hidden for layout editing. The lighting below depends on the ceiling being visible.
- **Haze:** `ClockTime` 14 and `Brightness` 1, so the `Atmosphere` has daylight to scatter and the far corridor fades into red-grey mist instead of black. The ceiling blocks the sun, so the maze interior is still lit only by its own lights.
  - Haze settings: density 0.5, colour `160, 112, 112`, decay `96, 58, 60`.
- **Exposure and colour grade:**
  - Ambient `70, 52, 56` and exposure 0.4.
  - The colour grade lifts the shadows slightly, desaturates by 0.15, and tints warm (`255, 228, 218`) to cancel the blue the daytime sky adds.
  - Bloom is 1.1 with threshold 0.8, so the screens glow.
- **Flesh:**
  - `Flesh_WetFolds_V2` now tiles every 14 studs instead of 8.66, so the folds read as large wet lumps.
  - Wall colour is `215, 160, 162` with up to 8% random darkening.
  - This changes the material variant itself, so anything else in the place using it changes too.
- **TV housings:** each `Housing` gets a `SurfaceAppearance` named `Grime` that reuses the mesh texture with a dark tint (`80, 64, 62`, up to 30% darker). A MeshPart's `Color` does not tint its `TextureID`, which is why the housings stayed light grey before.
- **Screens:** red screens are at `SurfaceGui.Brightness` 2.4. Static screens are a neutral grey (`214, 210, 208`) at brightness 0.9 instead of teal.
- **Lights:** all screen lights are rebuilt.
  - 96 red screens get a `SurfaceLight` (`255, 96, 80`, brightness 0.9 to 1.3, range 22 to 28). The lit screens are at least 15 studs apart.
  - 18 static screens get a dim cool light (`180, 186, 200`).
  - The nine room fills are a warm white (`240, 196, 190`) at brightness 0.8, or 0.4 in the entrance hall. They put the white wet highlights on the flesh and the water.
  - No light casts shadows. The map has 123 lights, up from 79.
- **Water:** colour `64, 20, 22`, reflectance 0.7, transparency 0.2, waves 0.07.
- **`MoodFX`:** a new model of invisible, non-colliding, non-queryable parts.
  - **Ground mist:** one `Mist_<row>_<column>` per cell (169 in total), each with a `GroundMist` emitter. These are slow, low smoke particles just above the water, half lit by nearby lights so they pick up red near screens without vanishing in dark corridors.
  - **Dust:** one `Motes_<row>_<column>` per checkerboard cell (85 in total), each with a `Motes` emitter of tiny glowing specks.
  - Both use Roblox's built-in smoke texture (`rbxasset://textures/particles/smoke_main.dds`), so no asset upload is needed.

## Totals

- 1,416 parts, up from 1,173. The extra 254 parts are the `MoodFX` volumes.
- 123 lights and 254 particle emitters.
- 367 screens, all still tagged `MonsterTV`, with their `SpawnIndex` attributes and `MonsterSpawn` attachments unchanged.

## Verification

- The final run reported:
  - 96 red and 18 static screen lights
  - 9 room fills
  - 363 housings with `Grime`
  - 254 emitters
  - 367 tagged screens
- Screenshots at player height were reviewed in the entrance hall, a maze corridor, a crossing, the court, and close up on a red screen.
- The mist takes about 15 seconds to build up after the recipe runs, because it recreates the emitters.
- In edit mode with three Studio windows open, the frame time averaged about 20 ms with 731 draw calls. Test on a low-end device before shipping; the particles and the extra 44 lights are the new cost.

## Moving this to the game place

`Lighting`, `MaterialService`, and the terrain water belong to the place, not to the map model. When `SignalMaze` moves into the game place, copy the `LIGHTING`, `HAZE`, `BLOOM`, `GRADE`, `DEPTH`, `WATER`, and `FLESH_TILE` values from the recipe as well. The haze only works with a daytime `ClockTime` and a ceiling that blocks the sun.

## Reverting

To go back to version 7:

1. Delete `Workspace.SignalMaze` and move `ServerStorage.SignalMaze_V8Backup.SignalMaze` back to `Workspace`.
2. Re-add the `MonsterTV` tag to each model in `EmbeddedTVs`.
3. Swap the backup's `Lighting` children back into `Lighting`.
4. Restore `Lighting` and `Terrain` from the folder's attributes.
5. Restore `Flesh_WetFolds_V2.StudsPerTile` from `FleshStudsPerTile`.
6. Restore the ceiling's `Transparency` and `CastShadow` from `CeilingTransparency` and `CeilingCastShadow`.
