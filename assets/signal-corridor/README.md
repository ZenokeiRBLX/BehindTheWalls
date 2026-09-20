# Short signal corridor prototype

A separate 30-stud horror corridor inspired by the supplied reference: six organic wall modules, 19 tilted CRT televisions, red screen lighting, glossy dark floor patches, and an enclosed ceiling. The geometry uses anchored Roblox parts with overlapping organic folds. It is a first modeling pass, not a generated sculpted mesh or a finished PBR material.

## Open and test

Open `build/SignalCorridorTest.rbxlx` in Roblox Studio and press Play. The test place has its own entrance spawn, first-person camera setting, subdued lighting, bloom, and distance fog. Walk toward negative Z. The main game's cutscene and spawn systems are not included in this standalone test.

To bring just the model into your map, use Studio's **Insert from File** on `build/SignalCorridor_Prototype.rbxmx`. Its root is `SignalCorridor_Prototype`. Move it as one model. `LeftWall_01` through `RightWall_03` are reusable ten-stud modules. Hide or remove `Architecture.RemovableCeiling` to work from above. Local red lights are included; the test place's global lighting is separate from the model export.

The main `default.project.json` is unchanged. This prototype does not automatically sync into either live place. Generated Roblox files are ignored by Git; the JSON model and generator are the editable sources.

## Materials and screens

`OrganicGrowth` contains the skin folds and dark nodules. These use built-in SmoothPlastic, varied burgundy colors, and restrained reflectance. There is no custom MaterialService asset yet. Once Studio is connected, these parts can be assigned a generated skin MaterialVariant with its matching base material. A material adds surface detail; the folds still need geometry to create their silhouette.

The TVs reuse the existing project CRT atlas documented in `assets/signal-maze/README.md`: `rbxassetid://125278888728934`. The atlas is static, with additional scanline overlays; there is no animated flicker or audio. Asset visibility and upload permissions need checking in Studio. The original full-size image remains in `assets/signal-maze/crt-atlas.png`.

## Rebuild from the repository root

```powershell
python tools/build_signal_corridor.py
New-Item -ItemType Directory -Force build | Out-Null
& "$env:USERPROFILE\.rokit\tool-storage\rojo-rbx\rojo\7.7.0\rojo.exe" build signal-corridor.project.json -o build/SignalCorridorTest.rbxlx
& "$env:USERPROFILE\.rokit\tool-storage\rojo-rbx\rojo\7.7.0\rojo.exe" build signal-corridor-model.project.json -o build/SignalCorridor_Prototype.rbxmx
```

Serialization follows the [Rojo property format](https://rojo.space/docs/v7/properties/).

## Verification status

Both exports build successfully with pinned Rojo 7.7.0. All 579 BaseParts are anchored, the model has 19 screen SurfaceGuis, and it contains no scripts. The central walking lane has been checked geometrically. The main project sourcemap also builds.

The Studio MCP server responded, but reported zero connected Studio instances during creation. Visual inspection, asset loading, MaterialService generation, and a Studio playtest are still pending. No changes were made to an existing Studio place.
