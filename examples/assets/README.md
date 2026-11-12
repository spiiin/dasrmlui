# Expedition atlas

`expedition_atlas.png` — ранее сгенерированный встроенным ImageGen атлас
с прозрачностью, 1254 × 1254 RGBA. Четыре клетки по 627 × 627: scout, rover,
probe, cargo. Используется без изменения изображения через native RmlUi
`@spritesheet`; координаты находятся в `examples/showcase_style.das`.

Запрошенный размер был 1024 × 1024; фактический размер результата — 1254 × 1254,
поэтому sampling использует реальные размеры. API key и внешние загрузки не нужны.

Исходный prompt:

> Use case: stylized-concept. Asset type: production sprite atlas for a desktop RmlUi space-expedition demo. Create ONE square 1024 by 1024 PNG sprite sheet with genuinely transparent background. Precisely four isolated detailed miniature sci-fi exploration vehicles in a regular 2x2 grid, equal 512 by 512 cells, no borders or visible grid. Top-left cell: sleek ivory and cyan scout spacecraft with small wings. Top-right cell: squat amber six-wheel lunar rover. Bottom-left cell: teal scientific probe with dish antenna and folded solar panels. Bottom-right cell: ivory and coral cargo lander with four legs. Consistent premium painted 3D game-icon look, isometric three-quarter view, soft upper-left lighting, crisp silhouettes, tactile ceramic and brushed metal, restrained bright accents. Each complete object fits within central 380 by 380 pixels of its cell with generous transparent margins so cells can be sampled independently as sprites; center points exactly (256,256), (768,256), (256,768), (768,768). No text, labels, shadows outside each cell, stars, scenery, backdrop, watermark, frames or extra objects. Intended to stay readable at 80px.

Effects также использует shader `creation` из подключённого upstream RmlUi GL3
renderer, автор оригинального эффекта — Danilo Guanabara. Исходник и условия
использования остаются в зависимости RmlUi; shader не генерировался ImageGen.

`style_atlas.png` — собственная геометрическая рамка для Style Lab, 192 × 96 RGBA,
две области 96 × 96 (Night/Paper). Atlas имеет resolution 2x; внутренние области
48 × 48 начинаются с отступа 24 px. Угловые вставки используются также для пиксельной
проверки ninepatch. Файл создан детерминированно через System.Drawing скриптом
`tools/make_style_atlas.ps1`; сторонних изображений и ImageGen здесь нет.

`native_mesh_atlas.png` — собственный детерминированный атлас 64 × 32 RGBA:
два значка по 32 × 32 для Mesh Lab и пиксельных тестов UV. Создаётся через
`tools/make_native_mesh_atlas.ps1` (System.Drawing); внешних изображений нет.
