# Signal Maze version 6: mixed TV sizes and extra TVs

Status: applied in Map Creation (`126262358232325`) on September 26, 2026. The map is `Workspace.SignalMaze` with `BuildVersion` 6. Save the place to keep it.

`vary-tvs.luau` upgrades the version 5 map described in [POPULATE-V5.md](POPULATE-V5.md). It refuses to run if `ServerStorage.SignalMaze_V6Backup` already exists; otherwise it first copies the version 5 map into that folder. It is seeded (`SEED = 20260929`), so rerunning it on the same version 5 map gives the same result.

## Sizes

Every wall TV except the totem TVs picked a target scale:

| Band | Share of picks | Scale |
|---|---|---|
| Small | 28% | 0.55 to 0.8 |
| Normal | 44% | 0.85 to 1.15 |
| Big | 28% | 1.3 to 2.0 |

Each TV is scaled with `Model:ScaleTo` about its screen front. The screen face stays where it was, so a bigger TV sinks deeper into the flesh instead of sticking out further.

A target is accepted only when the scaled TV passes all of these checks:

- It clears the water by 1.5 studs. If it doesn't, the TV is raised.
- It stays 1.5 studs below the ceiling.
- It stays within 10.5 studs of its wall face's centre, so it does not reach into a corner column.
- It does not overlap any screen facing the same way. Overlap is tested as circles in the wall plane with a 0.3-stud gap, and it includes the static panels and the totem.

If the target fails, the scale steps down 0.1 at a time. A TV that fits at no smaller size keeps its old size. Results:

- 100 TVs grew and 157 shrank. The shrink count includes TVs that landed just under their old size.
- 73 TVs kept their size.
- Final spread across the 420 wall TVs: 124 below 0.82, 229 between 0.82 and 1.2, and 67 above 1.2. The smallest is 0.55 and the largest is 1.99.
- Each TV now has a `TvScale` attribute.

## More TVs

- Each inward wall face had a 33% chance of an extra attempt (94 faces).
- An attempt tries up to ten candidates:
  - a random size from the table above
  - red or static
  - within 8 studs of the face centre
  - at a random height: 60% low (3 to 9 studs), 25% mid (9 to 16), and 15% high (16 to 26)
- A candidate is placed only if it fits the size rules above and is not behind a `FleshFold`. It sits on the bone-deformed surface, sunk 0.7 studs like the version 5 TVs.
- 90 extra TVs were placed (`X001_*` to `X090_*`).

## Monster spawn and optimisation

- There are now 453 screens. Every one is tagged `MonsterTV` and has a `SpawnIndex` attribute. Each has a `MonsterSpawn` attachment 2.5 studs in front of the screen, reset after scaling.
- No lights were added; there are still 95. The 110-stud screen draw distance, the 256 x 200 canvases, and the non-colliding, non-queryable, shadowless parts from version 5 apply to every screen.
- Totals: 1,351 parts.

## Verification

- The script reported 453 tagged screens and 95 lights.
- Scale buckets were read back from the live models.
- Screenshots were reviewed at player height for the entrance hall, the court, and a maze corridor. Screens can appear black or missing for a few seconds after a change while Studio reloads them.
- TVs do not collide, so the version 4 pathfinding results still hold.

To revert to version 5, delete `Workspace.SignalMaze` and move `ServerStorage.SignalMaze_V6Backup.SignalMaze` back to `Workspace`.
