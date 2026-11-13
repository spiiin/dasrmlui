# GL3 backend extension

`RmlUi_Renderer_GL3.h/.cpp` are a local copy of the RmlUi GL3 backend at
revision `821cbd229d804cb1c905b729af86c21133abceee` (6.4-dev), under the included
MIT license. The upstream dependency is not modified.

Changes add registered fragment programs, custom shader/filter compiled handles,
and a custom pass in the existing postprocess chain. Most extension code lives in
`custom_effects.inc`; native programs and render-state/layer handling remain intact.
When updating RmlUi, review these hooks against the new backend. The GL loader and
SDL platform backend still come from the configured RmlUi dependency.
