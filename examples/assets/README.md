# Example assets

`expedition_atlas.png` is an atlas with transparency, 1254 × 1254 RGBA, produced by an
AI image generator. Four cells of 627 × 627: scout, rover, probe, cargo. The image is
used unmodified through the native RmlUi `@spritesheet`; the coordinates are in
`examples/showcase_style.das`.

The prompt asked for 1024 × 1024; the result is 1254 × 1254, so sampling uses the real
dimensions. The prompt:

> Use case: stylized-concept. Asset type: production sprite atlas for a desktop RmlUi space-expedition demo. Create ONE square 1024 by 1024 PNG sprite sheet with genuinely transparent background. Precisely four isolated detailed miniature sci-fi exploration vehicles in a regular 2x2 grid, equal 512 by 512 cells, no borders or visible grid. Top-left cell: sleek ivory and cyan scout spacecraft with small wings. Top-right cell: squat amber six-wheel lunar rover. Bottom-left cell: teal scientific probe with dish antenna and folded solar panels. Bottom-right cell: ivory and coral cargo lander with four legs. Consistent premium painted 3D game-icon look, isometric three-quarter view, soft upper-left lighting, crisp silhouettes, tactile ceramic and brushed metal, restrained bright accents. Each complete object fits within central 380 by 380 pixels of its cell with generous transparent margins so cells can be sampled independently as sprites; center points exactly (256,256), (768,256), (256,768), (768,768). No text, labels, shadows outside each cell, stars, scenery, backdrop, watermark, frames or extra objects. Intended to stay readable at 80px.

Effects also uses the `creation` shader of the RmlUi GL3 renderer; the author of the
original effect is Danilo Guanabara. The shader source is part of the renderer copy in
`src/gl3/RmlUi_Renderer_GL3.cpp`, under the license in `src/gl3/LICENSE.txt`; it is not
a generated asset.

`style_atlas.png` is the project's own geometric frame for Style Lab, 192 × 96 RGBA,
two regions of 96 × 96 (Night/Paper). The atlas has a 2x resolution; the inner regions
of 48 × 48 start at an offset of 24 px. The corner insets are also used for the
ninepatch pixel check. The file is created deterministically through System.Drawing by
the script `tools/make_style_atlas.ps1`; it contains no third-party or generated images.

`native_mesh_atlas.png` is the project's own deterministic atlas, 64 × 32 RGBA:
two icons of 32 × 32 for Mesh Lab and the UV pixel tests. It is created with
`tools/make_native_mesh_atlas.ps1` (System.Drawing); there are no external images.
