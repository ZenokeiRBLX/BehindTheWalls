# Signal Maze version 5: a TV on every wall

Status: applied in Map Creation (`126262358232325`) on September 26, 2026. The map is `Workspace.SignalMaze` with `BuildVersion` 5. Save the place to keep it.

`populate-tvs.luau` upgrades the version 4 map described in [REFINE-V4.md](REFINE-V4.md). It refuses to run if `ServerStorage.SignalMaze_V5Backup` already exists; otherwise it first copies the version 4 map into that folder. The layout is seeded (`SEED = 20260928`), so running the recipe on the same version 4 map places the TVs in the same spots.

## Coverage

- The recipe reads the wall layout from the names of the collision run boxes (`V<line>_<first>_<last>` and `H<line>_<first>_<last>`). It then checks each 24-stud wall face that points into the maze. Outer faces of the boundary walls are skipped.
- 274 wall faces were checked. A face counts as covered when a screen facing the same way is within the face's 24-stud span and within 9 studs in front of the wall.
- 171 faces had no screen, so each got a TV (models `S001_*` to `S171_*`):
  - The TVs are clones of the existing red-silhouette (55%) and static models.
  - Each one is placed within 5 studs of the face centre, 4.2 to 8.5 studs up, and tilted slightly.
  - The skinning maths from version 4 places each TV on the bone-deformed surface, then sinks it 0.7 studs.
- On one face, every spot the recipe tried was behind a `FleshFold`. A second pass placed that TV in front of the fold (`S171_V6_4`).
- There are now 363 screens, and every wall face has at least one.

## Monster spawn points

- Every screen model is tagged `MonsterTV` through CollectionService. This covers all 363: the regular TVs, the large static panels, and the totem TVs.
- Each screen model has a numeric `SpawnIndex` attribute.
- The screen part (`BroadcastGlass`, or `StaticScreen` on the panels) holds an Attachment named `MonsterSpawn`. It sits 2.5 studs in front of the glass and faces out of the screen, parallel to the floor.
- `workspace.SignalMaze` has a `MonsterTag` attribute naming the tag.

A spawner can pick a tagged model and use the `WorldCFrame` of its `MonsterSpawn` attachment. When the map moves into the game place, check that `CollectionService` tags came across with the model.

## Optimisation

- No lights were added. The map still has 95 non-shadow lights. The new screens glow from their SurfaceGui brightness only.
- Every screen's SurfaceGui now has `MaxDistance` 110 (down from 170). Beyond that distance the haze already hides the screens.
- The fixed TV canvases dropped from 512 x 400 to 256 x 200. The large static panels are capped at 20 pixels per stud (down from 40). The images stretch to fill, so they look the same, and SurfaceGui texture memory drops to about a quarter.
- Every TV MeshPart uses `CollisionFidelity.Box`. Every screen part has `CanCollide`, `CanTouch`, `CanQuery`, and `CastShadow` turned off.
- Totals: 1,169 parts and 363 screens. `Workspace.StreamingEnabled` is on in Map Creation.

## Verification

- A second pass checked every face again and found none without a screen.
- 363 models carry the `MonsterTV` tag.
- Screenshots were reviewed at player height in the entrance hall, in a maze corridor, and at the TV in front of the fold.
- Right after the collision-fidelity change, the Studio viewport briefly showed the TV housings missing and some screens black. Both came back once Studio finished reloading the meshes and screen images.
- The TVs are non-colliding, so the version 4 pathfinding results still hold.

To revert to version 4, delete `Workspace.SignalMaze` and move `ServerStorage.SignalMaze_V5Backup.SignalMaze` back to `Workspace`.
