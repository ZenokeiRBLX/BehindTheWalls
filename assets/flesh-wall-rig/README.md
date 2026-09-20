# Wet flesh wall with nine deformation bones

Created and verified in the connected **Map Creation** place (`126262358232325`). The new wall is `Workspace.FleshWall_Rigged9`, beside the original `Workspace.btool`. The original wall and its `Flesh` material were preserved. Save the Studio place to retain the new scene instances.

The user began editing the live wall during the final checks and requested that those changes be left alone. The live scene may therefore differ from the complete published model and local export. No restoration was applied to the user's edited scene. Version 2 of the published model includes the AnimationController and Animator.

The old mesh denied EditableMesh access. With the user's approval, this is a rebuilt rounded wall with matching dimensions, gentle surface undulation, and a new nine-bone skin, rather than a modification of the inaccessible mesh.

## Uploaded assets

- Complete rigged model: `134860508339581`.
- Weighted mesh: `112866954522273`.
- Color: `114798040361975`.
- Normal: `136727296834708`.
- Roughness: `114387089191722`.

The mesh, roughness image, and complete model were explicitly uploaded to the place's owner, group `32989368`. Color and normal images were uploaded through Studio MCP's image-upload tool. All three images loaded successfully in Studio.

## Deform it

Expand `FleshWall_Rigged9 > Wall`. The nine sibling Bones are named `Wall_Lower_Left` through `Wall_Upper_Right`, arranged in three rows and three columns. Each bone controls a weighted region of the mesh. The center control is `Wall_Middle_Center`.

Use the model's AnimationController in Animation Editor, or change a Bone's **Transform** to pose the skin. Keep **CFrame** as the rest/bind position. For example, this temporary Studio Command Bar pose pushes the center outward four studs:

```luau
workspace.FleshWall_Rigged9.Wall.Wall_Middle_Center.Transform = CFrame.new(0, 0, 4)
```

Reset that control with `CFrame.identity`. The delivered wall is in its rest pose; there is no automatic breathing script. Skinned visual deformation does not reshape the wall's physics collision. Use separate simple collision geometry if animation needs to open a passage.

## Reuse the material

`MaterialService.Flesh_WetFolds_V2` is the reusable material. Set another part's **Material** to `SmoothPlastic` and **MaterialVariant** to `Flesh_WetFolds_V2`. Its repeat size is 12 studs.

The rigged wall uses a **SurfaceAppearance** with the same maps and tiled UVs so the texture travels with the deforming skin. It uses broad burgundy/rose folds instead of the original densely wrinkled pattern. Roughness is a uniform `48/255` for a slick surface; metalness is zero. The generated normal map is an approximation, not a bake from a sculpt.

Color and normal images were created with the built-in image generation tool. The service reached its usage limit on the roughness request, so the roughness asset is a constant data map made in Studio. Prompts are in `texture-prompts.md`.

## Source and export

- `build-wall.luau` is the reproducible asset-building command, not a runtime game script. It expects the original `Workspace.btool` as a dimension/placement reference and refuses to overwrite an existing `FleshWall_Rigged9`. Running it uploads a new mesh asset.
- `apply-material.luau` creates the reusable material and assigns the uploaded maps to the new rig. Neither file is mounted into the game by Rojo.
- `src/prototypes/FleshWall_Rigged9.model.json` references the uploaded mesh and reconstructs its nine Bone instances and SurfaceAppearance.
- `build/FleshWall_Rigged9.rbxmx` is the importable model export. The MaterialService variant is separate; the model's SurfaceAppearance works without it.

Rebuild the model export from the repository root:

```powershell
& "$env:USERPROFILE\.rokit\tool-storage\rojo-rbx\rojo\7.7.0\rojo.exe" build flesh-wall-rig.project.json -o build/FleshWall_Rigged9.rbxmx
```

## Verification

The published mesh was reopened and checked: nine bones, 12,032 triangles, and 36,096 exported vertices after attribute splitting (6,018 source positions). Every bone influences vertices. The maximum error in the sum of a vertex's weights is below `0.00000006`.

`rest-preview.jpg` and `deformation-preview.jpg` show the same camera before and after translating the center bone and translating/rotating the upper-right bone. The wall visibly bends and bulges. Those transforms were reset before publishing the complete model. All three texture fetch statuses were `Success`.

Roblox's [EditableMesh reference](https://create.roblox.com/docs/reference/engine/classes/EditableMesh) describes bone and weight data. The [AssetService reference](https://create.roblox.com/docs/reference/engine/classes/AssetService) covers the upload and mesh creation APIs used here.
