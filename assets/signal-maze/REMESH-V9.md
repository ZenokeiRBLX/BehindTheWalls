# Signal Maze version 9: remesh, seamless flesh, animated screens

Status: applied in Map Creation (`126262358232325`) on November 16, 2026. The map is `Workspace.SignalMaze` with `BuildVersion` 9. Save the place to keep it.

This pass builds on the version 8 map ([MOOD-V8.md](MOOD-V8.md)) and aims at the same reference image. It replaces the wall and column meshes, the flesh surface, the screen images, and the lighting values. It does not move any wall, column, TV, collision box, or spawn point.

## Files

- `v9-textures.py` writes the images in `v9/`. Run it with Python (it needs numpy and Pillow).
- `v9-meshes.luau` builds the six flesh meshes with `EditableMesh` and either previews them in `ServerStorage` or uploads them.
- `remesh-v9.luau` applies everything to the map. It is safe to run again: every run sets absolute values from its constants.

Both `.luau` files return a function, so load them as temporary ModuleScripts and call them from edit mode. Neither is mounted by Rojo.

## Flesh surface

The flesh uses the original `flesh-wall-rig` colour and normal images, with three changes:

- **Seam repair.** The originals did not quite tile: the difference across the image edge was about twice the difference between neighbouring pixels (1.81 for colour, 2.19 for the normal map). The script covers the edge with patches from the middle of the same image, blended in frequency bands so no cut line shows. After repair the edge difference is the same as anywhere else (0.95 and 1.01).
- **Roughness.** The original roughness was one flat value. The new map is glossier in the creases (0.05) than on the ridges (0.17), so the surface reads as wet.
- **Colour.** Slightly darker and deeper red, to sit closer to the reference.

A first attempt at a fully procedural flesh texture (rounded cells with veins) was rejected in review and is not used.

## Meshes

The old wall mesh was a flat rounded slab, so all the shape came from the normal map. The new meshes carry the shape in geometry: large soft swellings that merge into each other, stretched vertically so they read as sagging, with a few pits.

| Mesh | Size | Triangles | Asset ids (A, B) |
|---|---|---|---|
| Wall, one cell | 27 x 34 x 6 | 8,900 | `98683797457305`, `105590144937639` |
| Wall, two cells | 51 x 34 x 6 | 16,532 | `114534510554734`, `124352560621984` |
| Column | 10.5 x 34 x 8.5 | 5,088 | `84485778794624`, `94700111830946` |

- Every mesh has the same nine `Wall_*` bones as the old one, at the same rest positions, so the existing per-wall bone poses still apply.
- The highest point of each face sits at the old surface height, and the lowest is 1.25 studs from the wall centre. The TVs therefore stay in front of the flesh without being moved.
- Each wall or column picks variant A or B from the seeded generator (`SEED = 20261117`). Each part keeps its old `Size` and `CFrame`.
- The surface is a `SurfaceAppearance` named `FleshSkin`, mapped through the mesh's own UVs at 14 studs per tile. The UVs are bent slightly so the repeat does not line up in a grid. Columns wrap a whole number of tiles, so they have no vertical seam.
- The ceiling and floor are plain parts, so they use a new material variant, `Flesh_WetFolds_V9`, with the same images and the `Organic` pattern.
- The 251 flesh meshes total about 2.0 million triangles, down from about 3.0 million.

Flesh collars around each TV were tried and removed: some sat badly on TVs that stand proud of the wall. The recipe deletes any `FleshCollar` it finds.

## Screens

- Static screens use a 4 x 4 atlas of 256-pixel noise frames (`79102717337929`).
- Red screens use a 2 x 2 atlas of 512-pixel frames (`132076644354660`): the original silhouette on a brighter orange-red field, with grain, scanlines, and a tear line that differs per frame.
- Each `Signal` SurfaceGui gets two new children:
  - `CrtGlass`, an overlay with scanlines, darkened corners, and a faint glare (`127074494669484`).
  - `RollBar`, a soft dark band that the controller scrolls down the screen.
- SurfaceGui brightness is 2.2 for red screens and 1.2 for static.

## Lighting

- Ambient `104, 82, 86`, exposure 0.55, environment specular 0.8.
- Haze density 0.46, colour `150, 112, 114`, decay `78, 48, 52`.
- Colour grade: contrast 0.14, saturation -0.26, tint `255, 236, 230`.
- Bloom 1.0 at threshold 0.85.
- Red screen lights are `255, 150, 128` at brightness 0.6 to 0.9. The lighter colour keeps the flesh from going flat red and lets the highlights stay pale.
- Room fills are `236, 204, 204` at 0.7, or 0.5 in the entrance hall.
- Water: colour `40, 12, 14`, reflectance 0.6, wave size 0.045.

## Animation

Edit mode shows a still frame. At runtime `src/game/client/Controllers/SignalMazeController.luau` animates the map, tuned by `Config.SignalMaze`:

- Flesh meshes carry the `SignalMazeFlesh` tag. Within 110 studs of the camera their bones breathe, pulse in a two-beat rhythm, and drift slowly.
- Screens carry the existing `MonsterTV` tag. Within 120 studs they step through their atlas frames (static at 14 frames a second, red at 7), scroll the roll bar, and flicker, with occasional short dips in brightness.

The controller runs in the game place and in Map Creation. When the map moves to the game place, check that both tags came across with the model.

## Verification

- The final run reported 91 one-cell walls, 36 two-cell walls, 124 columns, 199 red and 164 static screens, 251 flesh tags, and 367 `MonsterTV` tags. The map has 1,416 parts, the same as version 8.
- In a Map Creation playtest, 405 bones near the camera were away from rest, the nearest bone moved between -0.19 and +0.26 studs over three seconds, the nearest static screen changed frame nine times in three seconds, and the nearest red screen's brightness varied between 1.81 and 2.17.
- Screenshots were reviewed in edit mode in the entrance hall, the court, and a junction, and in first person during a playtest.
- The Studio window was not focused during the playtest, so it ran at about 15 to 19 frames a second. Frame rate with the window focused, and on a low-end device, was not measured.

## Leftover assets

Earlier attempts in this pass uploaded images and meshes that nothing uses now: the procedural flesh images, two collar meshes, and the first set of six wall and column meshes. They are in the group's inventory under names starting `SignalMazeV9`.

## Moving this to the game place

`Lighting`, `MaterialService`, and the terrain water belong to the place, not the map model. Copy the `LIGHTING`, `HAZE`, `BLOOM`, `GRADE`, and `WATER` values from the recipe, and create the `Flesh_WetFolds_V9` variant there.

## Reverting

The first run copied the version 8 map into `ServerStorage.SignalMaze_V9Backup`, with the `MonsterTV` tags removed from the copy, the old `Lighting` children beside it, and the old `Lighting` and water values as folder attributes.

1. Delete `Workspace.SignalMaze` and move `ServerStorage.SignalMaze_V9Backup.SignalMaze` back to `Workspace`.
2. Re-add the `MonsterTV` tag to each model in `EmbeddedTVs`.
3. Swap the backup's `Lighting` children back into `Lighting`.
4. Restore `Lighting` and `Terrain` from the folder's attributes.
