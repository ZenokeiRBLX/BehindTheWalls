# Signal Maze expansion

Status: applied and verified in Map Creation on September 21, 2026. The map is Studio-owned at `Workspace.SignalMaze`; save the place to retain the edits.

`expand-studio-map.luau` records the upgrade of the compact version of `Workspace.SignalMaze` in Map Creation (`126262358232325`). It has already been applied. The recipe requires build version 1 and refuses to run if its backup already exists.

- Doubles the horizontal dimensions, giving approximately 224 x 224 studs and four times the floor area.
- Keeps wall height, wall thickness, TV sizes, and the existing 153 wall bones.
- Shortens the entrance, chamber spines, receiver partition, and northern turn to create broader connected spaces.
- Adds eight TVs and five low-intensity room lights without shadows. Verified totals: 114 parts, 36 TVs, 153 bones, and 18 lights. Every part is anchored, and there are no shadow-casting lights or runtime scripts in the map.
- Raises ambient light and exposure slightly and extends the fog distance for the larger layout.
- Preserves the compact map and lighting in `ServerStorage.SignalMaze_ExpansionBackup` before applying edits.

The live collision layout passed a two-stud sampling check with 1.8-stud horizontal agent clearance: all seven chamber and route targets were reachable, with 9,354 connected walkable samples and zero isolated samples. During a Studio playtest, Roblox pathfinding succeeded from the entrance to all seven destinations using a two-stud agent radius, five-stud height, and jumping disabled. The player spawned at the entrance with full health. This verifies spawn and navigable paths; it is not a manual walk-through or performance benchmark.

Player-height screenshots were reviewed in Studio, and the entrance received an additional soft fill light after the first visibility check. The Rojo sourcemap check passed; this construction recipe is not mounted as a runtime script. Studio was returned to Edit mode after verification.
