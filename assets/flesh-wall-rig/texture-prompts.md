# Texture generation prompts

Tool: built-in image generation. The user's horror-corridor image was the style reference; no TV imagery was included in the wall maps.

## Color

Create a production game texture based on the flesh wall surface in the attached horror corridor reference. The reference image is style guidance only: do not include televisions, silhouettes, architecture, perspective, floor, fog, text, or lighting fixtures. Output one square 2048x2048 seamless tileable base-color/albedo texture, filling the entire canvas. Material: fictional organic fleshy growth, broad irregular smooth swollen burgundy and muted rose membranes, thick folded strands with rounded ridges, a few dark wine-red creases and small recessed pores, subtle mottled capillary coloration. Match the reference's large slippery bulbous folds, not tiny repeating brain wrinkles or stone scales. Low-frequency forms dominate; varied folds, no regular rows or grid. Red-pink living organic surface with deep maroon crevices, no recognizable body parts, no injuries, no blood splashes, no exposed organs. Diffuse neutral even illumination for an albedo map: no baked glossy white glints, no cast shadows, no directional light; gloss will be supplied by a separate roughness map. Visually continuous across all four tile edges. Save this as a usable texture asset, not a texture preview on a wall.

## Normal

Convert the attached flesh albedo texture into its matching game-ready tangent-space NORMAL MAP, output only one square normal-map image, same framing and pixel-aligned features. Preserve exact position, scale and shape of every large fleshy fold and pore; no redesign. Purple-blue normal map with neutral flat areas RGB 128,128,255, red channel X+, green channel Y+ OpenGL convention, blue positive Z. The pale swollen folds are rounded raised forms; dark maroon channels and pores are recessed. Broad smooth gradients across folds and fine subtle pore detail. No albedo red color, no grayscale, no white glints, no labels or border. Seamless tileable across both axes. This will be used as Roblox MaterialVariant.NormalMap.

## Roughness request (service limit; no generated output)

Convert the attached flesh color texture into a matching PBR ROUGHNESS MAP for a wet horror-game organic wall. Output one square GRAYSCALE-only data texture, preserving exact positions and scale of every fold and pore, same framing, no artistic redesign. Black means smooth reflective, white means rough. Overall dark grayscale values 35-75 out of 255, glossy moist smooth raised folds around 45-65, slick liquid-lined crevices around 25-45, a few fine drier pore details around 85. Low-contrast subtle surface variation; no directional lighting or shading, no albedo colors, no text, no borders. Seamless tile across both axes. It must not look like a photograph: it is a mostly dark gray technical roughness map registered to the input image.

The successful color and normal outputs are 1254 x 1254. The roughness replacement is a 32 x 32 uniform RGB(48,48,48) data texture created with EditableImage.
