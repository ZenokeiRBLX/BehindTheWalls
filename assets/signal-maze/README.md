# Signal maze mock map

Built in the open **Map Creation** Roblox Studio place (`126262358232325`). The map is Studio-owned at `Workspace.TheSignalMaze`; save that place to retain the geometry and lighting. These files are reference assets, not a Rojo map export.

- Footprint: 768 x 768 studs on the existing 800 x 800 baseplate.
- Layout: 24 x 24 cells, branching corridors, loops, three landmark chambers, an entrance and an exit.
- Uses the existing `Flesh` material, flesh wall geometry and vintage TV mesh.
- All 576 cells and the exit passed a 4 x 5 stud player clearance check. Spawn and forward movement were verified in a first-person Studio playtest.
- Original TV, wall and rig models are in `ServerStorage.SignalMaze_OriginalAssets`, alongside the original lighting instances.
- `Architecture.RemovableCeiling` can be temporarily hidden for overhead editing.
- TV broadcasts are static graphics. No runtime scripts were added.

`crt-atlas.png` is the generated source texture. Its uploaded Roblox image is `rbxassetid://125278888728934`; the uploaded atlas uses two 512 x 512 regions, with the red broadcast at offset (512, 0).

`entrance-preview.jpg` shows the final entrance. `layout-preview.jpg` shows the maze with the roof temporarily hidden. `playtest-preview.jpg` records the movement test before the final floor and housing color adjustments.

The place remains on `LightingStyle.Soft`: Studio denied changing that property through MCP. Select `Lighting > LightingStyle > Realistic` manually for stronger specular lighting.
