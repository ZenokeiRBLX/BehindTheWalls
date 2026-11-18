# Signal Maze version 11: entry shaft

Status: applied in Map Creation (`126262358232325`) on November 18, 2026. `Workspace.SignalMaze` now has `BuildVersion` 11. Save the place to keep it.

This pass gives the maze a hole that players drop in through. In the game place, the sewer hole leads here: the player's fall continues down this shaft and out of the ceiling into the entrance corridor. Version 10 lighting ([LIGHT-V10.md](LIGHT-V10.md)) is unchanged.

`entry-shaft-v11.luau` is the recipe. It returns a function, so load it as a temporary ModuleScript and call it in edit mode. It can be rerun: it rebuilds `EntryShaft` each time and only splits the ceiling once.

## What it adds

- **Ceiling opening.** The single `Ceiling` slab in `Ceiling_RemoveForLayoutView` becomes four slabs (`Ceiling_West`, `Ceiling_East`, `Ceiling_North`, `Ceiling_South`) around a 12 by 12 stud opening centred 2 studs in front of `MazeEntrance`, at `(147, 200)`. The nine disabled `RoomFill_*` attachments move to whichever slab is under them, at the same world positions.
- **`EntryShaft` model**, everything anchored and non-colliding:
  - `Lining`: three rows of four flesh wall panels (the 27 stud meshes, bone-rigged and tagged `SignalMazeFlesh`, so they breathe like the maze walls). The panels form a square tube about 15 studs wide, from the ceiling up to y 134, with each row turned and flipped differently.
  - `Rim`: four flesh column meshes laid along the edges of the opening, hanging slightly below the ceiling so the hole reads as a fleshy orifice from the corridor.
  - `Cap`: a flesh slab closing the top of the tube.
  - `Screens`: three TVs copied from the maze (red, static, red), set into the tube walls facing inward at 22, 52 and 80 studs above the ceiling. They keep the `MonsterTV` tag, so the controller animates them.
  - `Glow`: three dim red `PointLight`s inside the tube.
  - `LevelEntry`: an invisible marker on the floor under the opening, facing the way `MazeEntrance` faces (into the maze). `MapSystem` publishes its bottom as the landing point.
  - `ShaftTop`: an invisible marker 14 studs below the cap where the falling player waits while the level card shows.
- The first run saves the original ceiling to `ServerStorage.SignalMaze_V11Backup`.

## Moving the map to the game place

The game place keeps a copy at `ServerStorage.Maps.SignalMaze`, loaded at runtime by `MapSystem`. The terrain water that floods the maze floor is a `TerrainRegion` child of that copy named `Terrain`, made with `Terrain:CopyRegion` over cells (-10, -3, -33) to (76, 0, 59), with a `Corner` attribute of `(-40, -12, -132)` (the region's minimum corner in studs). The game place `MaterialService` also needs `Flesh_WetFolds_V9`. When the map changes here, replace the copy and its `Terrain` child the same way.

## Reverting

Delete `EntryShaft`, delete the four `Ceiling_*` slabs, move `SignalMaze_V11Backup.Ceiling` back into `Ceiling_RemoveForLayoutView`, and set `BuildVersion` back to 10.
