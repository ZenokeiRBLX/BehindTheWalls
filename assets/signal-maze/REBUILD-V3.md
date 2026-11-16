# Signal Maze version 3 rebuild

Status: applied in Map Creation (`126262358232325`) on September 26, 2026. The map is Studio-owned at `Workspace.SignalMaze` (`BuildVersion` 3). Save the place to keep it.

`rebuild-studio-map.luau` is the edit-mode recipe. It requires the version 2 map and refuses to run if `ServerStorage.SignalMaze_V3Backup` already exists. Before building, it moves the version 2 model into that backup folder. It also stores the previous lighting and terrain-water properties there as attributes, and clones the old `Lighting` children beside them. The layout is seeded (`SEED = 20260926`), so rerunning the recipe on the version 2 map gives the same result.

## Layout

- 13 x 13 cells of 24 studs: 312 x 312 studs around `(147, 0, 54)`, about 1.9 times the floor area of version 2.
- Walls are 32 studs tall (up from 18.5) and meet a dark flesh ceiling. There is no open sky.
- The maze is carved by a seeded depth-first search that treats each chamber as one node. About 55% of dead ends are then opened, plus 7% of the remaining interior walls, so there are loops and multiple routes.
- Open areas:
  - `EntranceHall`: a sealed, 5-cell-long corridor lined with TVs, modelled on the reference photo.
  - `SignalCourt`: a 3 x 3 court around a flesh-and-TV totem.
  - `ReceiverChamber`: a 3 x 2 chamber whose north wall carries large static screens.
  - `WestGallery` and `EastGallery`.
  - Four 2 x 2 hollows.
  - Freestanding flesh pillars stand at chosen vertices inside these rooms.
- The spawn (`MazeEntrance`) is at the south end of the entrance hall, facing north.

## Construction

- `FleshWalls`: the existing flesh wall mesh, with its bones removed. There is one mesh per 1 or 2 cell span, with random flips and a small jitter.
- `FleshGrowths`: spheres with the flesh variant, partly sunk into both faces of each wall to make bulging masses. Interior growths are limited so they cannot push through the far side of the wall.
- `FleshColumns`: a cylinder with lumps at wall corners, T-junctions, and ends. Straight joins only sometimes get one.
- `Collision`: invisible 8-stud-thick boxes, one per straight wall run. The columns and the totem core also collide. Decorative parts do not collide.
- `EmbeddedTVs`: clones of the existing red and static TV models, set partly into the flesh and tilted slightly. They are placed singly, in stacks of two or three, or high and scaled up. There are also large static screens with a dark bezel. Flesh growths overlap the edges of every screen.
- Lights: up to 72 red `SurfaceLight`s on red screens, 14 dim static-screen lights, and a ceiling fill light per room. No light casts shadows.
- Floor: a dark flesh slab, with terrain water from y 0 to 1.3 over the whole footprint (dark red, reflective, small waves).
- Lighting: a new `SignalMaze_Haze` `Atmosphere` and a new `SignalMaze_Depth` depth of field, and retuned `SignalMaze_ScreenBloom` and `SignalMaze_Grade`.

Totals: 4,108 parts, 192 screens, 95 lights, and 68 collision boxes.

`MaterialService.AssistantMaterials` contains a generated `Flesh_Bulbous_V3` variant. It was compared against `Flesh_WetFolds_V2` and not used: it came out matte and pink, with a repeating pore on every lump. The build uses `Flesh_WetFolds_V2`.

## Verification

- In a Studio playtest, the character spawned in the entrance hall with full health, in the `Running` state (standing in the water, not swimming).
- Roblox pathfinding (agent radius 2, height 5, jumping disabled) found a path from the spawn to all eleven targets: every chamber, every hollow, and the three far corners.
- The playtest ended before a scripted walk test finished. Walking was not checked separately.
- Screenshots at player height were reviewed for the entrance hall, the court, and a maze corridor. The red screen lights and the room fill lights were then adjusted, and the recipe records the adjusted values.
- Maze corridors between rooms are deliberately dark. They are lit only by nearby screens, since the game uses a flashlight.

To revert, delete `Workspace.SignalMaze` and move `ServerStorage.SignalMaze_V3Backup.SignalMaze` back to `Workspace`. Restore the lighting properties from the folder's attributes and swap in its `Lighting` children. Clear the water with `Terrain:FillBlock` using `Enum.Material.Air` over the same region.
