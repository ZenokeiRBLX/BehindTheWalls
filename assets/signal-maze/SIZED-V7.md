# Signal Maze version 7: wall TVs sized for a 12-15 stud monster

Status: applied in Map Creation (`126262358232325`) on September 26, 2026. The map is `Workspace.SignalMaze` with `BuildVersion` 7. Save the place to keep it.

`sized-tvs.luau` upgrades the version 6 map described in [VARY-V6.md](VARY-V6.md). It refuses to run if `ServerStorage.SignalMaze_V7Backup` already exists; otherwise it first copies the version 6 map into that folder. The recipe uses a fixed seed (`SEED = 20261001`), so each run from the same version 6 map gives the same result.

## History

An earlier version 7 put 3 to 4 times scale TVs on every face, and those were too large. After that run, the whole model was also moved about (4.24, 3.31, -35.24) in Studio, which lifted the floor 3.3 studs above the water. That map is kept, with its `MonsterTV` tags removed, in `ServerStorage.SignalMaze_V7Giant_Shifted`. The live map was then restored from the version 6 backup at its original position, and this recipe was applied.

## What it does

- Removes all version 6 screens and the six `FleshFold` sheets.
- Adds one main TV on each of the 274 wall faces that point into the maze:
  - The width scale is 1.8 to 2.6 times the original, capped at a 12.5-stud housing. The height gets another 1.1 times on top of that.
  - Each housing is roughly 8.3 to 12 studs wide and 7.8 to 11.3 tall.
  - Each screen is roughly 5.8 to 8.3 studs wide and 4.4 to 6.3 tall.
  - Each bottom sits 1.3 to 2.2 studs above the floor.
- Adds a smaller upper TV on 89 faces. Each face had a 35% chance of getting one.
  - The upper TVs are 1 to 1.5 times the original size.
  - Each sits at least 1 stud above the main TV and 2 studs below the ceiling, and stays inside the face.
- Keeps TV depth at 1.3 times the original, so no TV pokes through a wall.
- Checks where the bone-deformed flesh bulges on a 3 x 3 grid across each screen. The screen front is set 0.35 studs past the highest bulge, at 3.4 to 5.44 studs from the wall centreline. Flesh never covers the glass.
- Puts four TVs at 1.8 times scale on the court totem and sets its collision box to 10 x 10.
- Uses SurfaceGui canvases of 320 x 250 and `MaxDistance` 120.

## Monster spawn data

- There are 367 screens: 274 main, 89 upper, and 4 on the totem.
- Every screen model has:
  - the `MonsterTV` tag
  - a `SpawnIndex` attribute (its number in sorted name order)
  - a `TvScale` attribute (its width scale)
  - a `ScreenSize` attribute (the glass width and height, as a Vector2)
- Each glass part has a `MonsterSpawn` attachment 2.5 studs in front of the screen, facing out.
- Only the live TVs carry the tag. The copies in the backup folders have it removed.

## Optimisation

- Up to 70 red screens get a SurfaceLight with no shadows. The map now has 79 lights, down from 95.
- The map now has 1,173 parts.
- TV parts don't collide, respond to touch or raycasts, or cast shadows.

## Verification

- The recipe reported 274 faces, 89 upper TVs, 367 screens, 367 tagged screens, and 79 lights.
- The floor is back at `(147, -1, 54)`.
- Screenshots at player height were reviewed for the entrance hall and the court. Some screens stay black for a few seconds after a change while Studio loads them.
- TVs don't collide. The only collision change is the totem box, which grew from 7.5 to 10 studs.

To go back to version 6, delete `Workspace.SignalMaze` and move `ServerStorage.SignalMaze_V7Backup.SignalMaze` back to `Workspace`.
