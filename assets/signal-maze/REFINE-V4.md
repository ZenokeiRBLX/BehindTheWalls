# Signal Maze version 4: rigged flesh walls

Status: applied in Map Creation (`126262358232325`) on September 26, 2026. The map is `Workspace.SignalMaze` with `BuildVersion` 4. Save the place to keep it.

`refine-studio-map.luau` converts the version 3 map produced by [rebuild-studio-map.luau](rebuild-studio-map.luau). It needs the rigged v2 wall in `ServerStorage.SignalMaze_V3Backup` as its mesh source. It refuses to run if `ServerStorage.SignalMaze_V4Backup` already exists. Before changing anything, it copies the version 3 map, its lighting, and the water colour into that backup. The recipe uses a fixed seed (`SEED = 20260927`), so each run produces the same result.

## What changed from version 3

- All 3,373 sphere `Growth` parts are gone, including the ceiling lumps, column lumps, and totem bulges. The part count dropped from 4,108 to 829.
- Every flesh surface is now a bone-rigged model built the same way as `FleshWall_Rigged9`:
  - a `Model` (`FleshWall_###`, `FleshFold_###`, `FleshColumn_###`, `FleshPillar_###`, `SignalTotem_###`) with `PrimaryPart` set to its `Wall` MeshPart
  - the nine bones as children of that MeshPart, named `Wall_Lower_Left` through `Wall_Upper_Right`
  - an `AnimationController` with an `Animator`, so each model can be posed in the Animation Editor or driven from scripts
  - in total, 259 rigged meshes and 2,331 bones
- The natural shape comes from the bones. Each bone's `CFrame` is posed away from the bind grid with a small random offset and rotation. The two outer bone columns move less, so neighbouring pieces meet without steps at the seams.

  | Piece | Depth offset (studs) | Sideways offset (studs) | Rotation (rad) |
  |---|---|---|---|
  | Walls | up to 2.2 | up to 2 | up to 0.09 |
  | Columns | up to 0.9 | up to 1 | up to 0.05 |
  | Pillars | up to 1.1 | up to 1.2 | up to 0.07 |
  | Folds | up to 0.6 | up to 1 | up to 0.05 |
  | Totem | up to 0.35 | up to 0.3 | up to 0.03 |

- Wall corners, T-junctions, and wall ends each get one rigged column, turned about 45 degrees, with an 8.5-stud collision box. The 38 columns on straight joins were removed. The room pillars and the court totem are each two crossed rigged meshes with their own collision box.
- Six extra `FleshFold` sheets overlap the walls. A fold is placed only where no screen is nearby.
- The 180 wall screens were moved onto the deformed surface. The move uses the mesh's skinning maths (bilinear weights over the 3x3 bone grid), then sinks each screen 0.7 studs. The totem screens moved 1.1 studs outward.
- Lighting is less saturated:
  - Red screen lights changed from `255, 66, 57` to `240, 104, 96`.
  - The room fills are more neutral, at `205, 170, 172`.
  - Ambient is `88, 72, 78`.
  - The haze colour and decay are browner.
  - The colour grade's saturation is `-0.18`.
  - The water colour is `36, 22, 24`.

## Using the bones

A bone's `CFrame` holds the natural rest shape set by the recipe. To animate, change `Transform` on top of it; `CFrame.identity` returns a bone to that rest shape. Example of a temporary bulge:

```luau
workspace.SignalMaze.FleshWalls.FleshWall_001.Wall.Wall_Middle_Center.Transform = CFrame.new(0, 0, 2)
```

Skinned deformation does not move collision or the screens mounted on a wall. Keep animated bulges small, or move the screens with the wall.

## Verification

- The recipe reported no `Growth` parts left.
- In a Studio playtest, pathfinding (agent radius 2, height 5, no jumping) reached all 11 targets from the character's position: every chamber, every hollow, and three far corners.
- The character spawned at full health in the `Running` state. It was being walked through the maze during the check.
- Screenshots at player height were reviewed for the entrance hall and the court after one retune. The retune strengthened the wall bones and sank the screens.
- There are now 259 rigged meshes of about 12,000 triangles each. That is fewer parts than version 3, but more mesh triangles. Test frame rate on low-end devices.

To revert to version 3, delete `Workspace.SignalMaze` and move `ServerStorage.SignalMaze_V4Backup.SignalMaze` back to `Workspace`. Restore `Ambient`, `OutdoorAmbient`, `ExposureCompensation`, and the terrain water colour from the folder's attributes, and swap in its `Lighting` children.
