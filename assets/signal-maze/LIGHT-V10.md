# Signal Maze version 10: screen-lit lighting

Status: applied in Map Creation (`126262358232325`) on November 16, 2026. The map is `Workspace.SignalMaze` with `BuildVersion` 10. Save the place to keep it.

This pass relights the version 9 map ([REMESH-V9.md](REMESH-V9.md)) so the TVs are the only real light: light pools around each screen and the corridors between them fall into darkness. Version 9's lighting was flat because nine ceiling fill lights lit every room evenly and put white glints on the water. This pass changes lights and lighting values only. No geometry, texture, or screen image changes.

`light-v10.luau` is the recipe. It returns a function, so load it as a temporary ModuleScript and call it in edit mode. Every run sets absolute values from its constants, so it can be rerun while tuning.

## What it does

- **Room fills off.** The nine ceiling `PointLight`s are disabled, not deleted.
- **Every screen lights the flesh around it.**
  - All 363 screens now have a `SurfaceLight`, up from 114.
  - Red screens get `255, 108, 86` at brightness 0.55 to 0.8.
  - Static screens get a cold `170, 182, 210` at 0.55 to 0.8.
  - Brightness scales with the square root of the screen's size, and range is 9 studs plus 2.2 per stud of screen width, kept to 14 to 30 studs for red screens and 12 to 24 for static.
  - The angle is 120 degrees.
  - The mix of warm red pools and cold grey pools is deliberate.
- **Flesh casts shadows.** `CastShadow` is turned on for the 251 tagged flesh meshes, so the lumps shadow each other under screen light. Lights are created with shadows off; the controller turns them on near the player (below).
- **Darker exposure.**
  - Ambient `38, 24, 26`, outdoor ambient `12, 7, 8`, exposure 0.1.
  - Environment diffuse 0.05 and specular 0.35, so the hidden sky barely lights the interior.
  - Shadow softness 0.35.
- **Murky red haze.**
  - `ClockTime` is 17.9 instead of 14. The midday sky made the far haze bluish; the evening sun scatters red.
  - Atmosphere density 0.42, colour `96, 58, 56`, decay `44, 20, 20`, haze 1.4.
- **Grade.**
  - Contrast 0.2, saturation -0.24, brightness -0.02, tint `255, 236, 232`.
  - Bloom 0.9 at threshold 0.92, so only the screens bloom.
  - Depth of field far blur 0.18.
- **Water.** Colour `24, 8, 10`, reflectance 0.45, transparency 0.1, wave size 0.03, wave speed 1.4. With the fills off, the water reflects the screens as red streaks instead of white glints.
- **Ceiling** colour `40, 26, 28`.
- **Particles.** The `MoodFX` ground mist and dust motes are now lit only by nearby light (`LightInfluence` 1, `LightEmission` 0). They show up in screen light and vanish in the dark, like real haze.

## Shadows at runtime

Shadow-casting lights are expensive, so `SignalMazeController` turns `Shadows` on for only the 6 screen lights nearest the camera, within 70 studs. It re-checks every 0.3 seconds and turns shadows off on lights that drop out of that set. The tuning is in `Config.SignalMaze.Shadows`. Because the screen flicker also drives the light brightness, the shadows flicker with the screens.

## Verification

- The final run reported:
  - 199 red and 164 static screen lights
  - 363 enabled lights
  - 9 fills disabled
  - 251 shadow-casting flesh meshes
  - 254 emitters retuned
- In a first-person playtest, 6 lights had shadows on at the entrance hall spawn.
- Screenshots were reviewed in edit mode at the entrance hall, a junction, and the court, and in first person at the entrance hall and a junction.
- Frame rate with 363 lights and 6 shadowed lights was not measured with the Studio window focused. Test on a low-end device before shipping. If it is too slow, lower `Shadows.Count` first, then light fewer screens.

## Moving this to the game place

Copy the `LIGHTING`, `HAZE`, `BLOOM`, `GRADE`, `DEPTH`, and `WATER` values. The game place is also lit by the player's flashlight, which matters more now that the corridors are dark.

## Reverting

The first run saved `ServerStorage.SignalMaze_V10Backup`:

- the old `Lighting` children
- the old `Lighting` and water values as attributes
- the ceiling colour
- a `Lights` attribute: a JSON list of every light's parent path and settings

To go back to version 9:

1. Swap the backup's `Lighting` children back into `Lighting`.
2. Restore `Lighting`, `Terrain`, and the ceiling colour from the attributes.
3. Re-enable the room fills.
4. Delete every screen `SurfaceLight`, then recreate the ones in the `Lights` list from their saved settings.
5. Set `BuildVersion` back to 9.
