# RmlUi coverage in dasrmlui

This matrix was compiled against the sources of RmlUi revision
`821cbd229d804cb1c905b729af86c21133abceee` (CMake version 6.4, unreleased), not only
against the features listed in the latest published documentation.

The first table lists what the project implements. The second lists what exists only as
a general mechanism or as part of the API, without a finished interface or a check of
all scenarios. A function existing in RmlUi itself does not mean it is exported to
daScript.

## What is already present

| Area | Implementation and examples | Coverage boundary |
|---|---|---|
| Components | `[ui_component]`, mount/update/dispatch, binding dependencies, keyed lists, `when`; hybrid by default, `[ui_action]` for helpers | In hybrid, direct scalar bindings are served by the native DataModel; structure/lifecycle stay in dasrmlui. [Contract](hybrid.md) |
| State and composition | `ui_state`, `ui_frame(state)`, readonly `ui_read`, tracked `ui_edit`; local state, mount/unmount, computed, slots, events, signals | The root is a GC-owned copy of the initial value; scoped borrow without escape. Local state lives until unmount; changing the root state resets the tree. [Contract](hybrid.md) |
| Virtualization | `virtual_each`, Catalog, `tests/viewport.das` | Fixed row height, int keys, all keys are checked on update |
| Forms | Text, numeric drafts, checkbox, select, errors, Enter/blur/Escape | Application-level validation; not a general `<form>` wrapper |
| Additional native controls | range, radio, textarea, tabset, progress in `examples/expedition.das` | Smoke test is included in CTest |
| Focus and layout | Tab/Shift+Tab scope, focus restoration, resize, `flow`, flex through properties | Not a manager of windows or of all keyboard shortcuts |
| Native events | `on_event`, `document_events`, capture/target/bubble, target/currentTarget, keys/modifiers, mouse/wheel, copied parameters, synchronous stop flags | The handler receives a snapshot in ui_frame; cancellation is set before dispatch. No browser PointerEvent API; load is not replayed after creation, cleanup is done by on_unmount |
| Document modes | Hidden template loading, hide/show, modal/focus/scroll flags, front/back, position, retained editor; `show_popup` with clamping/Escape/outside dismissal and focus return | One context; a native modal isolates input while it owns focus; front/back within a z-index; a popup does not shrink its size |
| Styles | Scoped `[ui_style]`, arbitrary selectors in `rule`, RCSS through `property` | Most properties are strings; a dedicated typed helper is not required for access |
| Inline rich text | `rich_text`, nested span/strong/emphasis/underline/strike, link, inline PNG/sprite, br; reactive text/href/src, legacy/hybrid and static templates; The Field Notes | [Display and layout are implemented](rich-text.md); a rich text editor is a separate extension |
| Sprites | `spritesheet(source,resolution)`, `sprite`, `sprite_image`, PNG atlas in Expedition and Style Lab | Different atlases can be selected with media/theme rules |
| SVG / Lottie | Official plugins are enabled; `svg_image`, `svg_inline`, `svg_decorator`, `lottie`, `image_color`; components/templates, separate bindings; Vector atelier | Native automatic loop, no pause/seek. The format subset depends on LunaSVG/rlottie; overwriting a resource at its old path is not hot reload |
| Effects | `examples/effects.das`: filters, backdrop blur, shadows, rotate/scale, upstream shader `creation`, text glow/outline/shadow | GL3 smoke test is included in CTest; custom programs are covered separately in Shader Lab |
| Native templates | `[ui_template]` + `[ui_style]`, arbitrary `slot(name)`, automatic title, native handles; Field Office fills three slots with separate components | There is no main slot. Checked: names, instance isolation, updates/state/focus, target change, lifecycle, cache, escaping and restart |
| Localization | `examples/localization.das`: TranslateString, reactive tr, en/de/ru, plural forms, catalog fallback | Checked: UTF-8, the native parser and input/focus preservation; not ICU/RTL |
| Progress along a curve | `examples/progress_lab.das`: S-curve by segment length and radial sprite fill | GL3 smoke test, play/pause/reset and checks of actual properties/geometry |
| Keyframe animations | Scoped `keyframes`/`keyframe`, `motion`/`animate`, repeat/alternate, stop/replay, `animated_when`, grouped completion and transition callback; `examples/animations.das` | Checked: native interpolation without component recomputation, cancel exit/state/focus, unmount, stale events, GC and GL3 smoke |
| Media/themes/DPI/ninepatch | `media`, `theme`, context theme API, `dp`, user scale on top of display scale, atlas resolution, `ninepatch`; `examples/style_lab.das` | Native styles without remount, subscriptions of environment readers, DPI and pixel checks of corners/center on SDL; a physical move between monitors is not tested |
| DSL diagnostics | `ui_stats`, `ui_trace`, AST dump, negative tests | This is not the visual RmlUi Debugger |
| Spatial navigation | Typed `nav`, `nav_up/right/down/left`, `UiNav`, `nav_to`, `nav_id`, `tab_stop`, `document_nav`; native geometry/tree-order/ID and focus-visible | Native auto is limited to the scroll container; focus_scope limits Tab; SDL gamepad glue is separate |
| RmlUi Debugger | Official plugin: lazy init, F8, toolbar, Element Info, Event Log, Outlines, Data Models, hide/shutdown and reactive status; Vector deck and Harbour | One context; public models and the scalar slots of the hybrid `dasrmlui` model are visible, not the whole script structure. Hide also closes the tools and turns off picking/outlines |
| Public DataModel | `ui_data_model`, `ui_data_bind/set`, scalar/struct/array, writable native controls, expressions, callbacks, dirty, Context/Debugger; `native_data` and `data_*` inside `[ui_component]`, Harbour is entirely in daScript; external RML is also supported | Native-owned copies; the native region owns its tree, events are handled deferred through `ui_data_events`. [Contract](data-models.md); synchronous script getters/setters and custom transforms are not exported |
| Custom native elements | `register_native_element`, `native_element` in components/templates; native ElementInstancer, Create/Attribute/Property/Resize/Update/Paint/Destroy, intrinsic, indexed mesh/UV/vertex colors, PNG/RGBA textures and GC-safe registry; Signal foundry and Mesh Lab | Names with a hyphen; no overriding of built-ins, no shader/sampler commands, no baseline/custom hit testing. DOM mutations inside native hooks are forbidden; regular DSL events are available |
| Custom decorators | `register_decorator`, typed number/length/color/string parameters, `custom_decorator` in styles/components/templates; native DecoratorInstancer, separate canvases, Create/Paint/Destroy, mesh/textures and GC; Decorator Studio | RmlUi may recreate a canvas on resize/style/DPI without unmounting the element; the schema is immutable, unregister is forbidden while native definitions/data exist; the custom shader/filter API is separate |
| Custom filters and shaders | `[ui_shader]`/`[ui_filter]` in daScript through dasGlsl, registration and typed RCSS parameters, DSL styles/components/templates, ordered chains, backdrop, native instances/GC; Shader Lab and pixel tests (GLSL and DSL) | GL3 only: fragment functions with a ready-made vertex stage; one pass per filter, no additional samplers, vertex shaders or compute |
| Hot reload | LiveHost, the SDL3/GL3 adapter, root and local state, migrations and a styles entry without remount; Live workbench | [Lifecycle, state keys and migrations](hot-reload.md) |

Implementation files: [ui.das](../dasrmlui/ui.das),
[macros.das](../dasrmlui/macros.das),
[rml_module.cpp](../src/rml_module.cpp).

## What is not covered yet or is covered partially

| RmlUi feature | Current state in dasrmlui | What is needed |
|---|---|---|
| Multiple contexts/SDL windows | Multiple native documents in one context are supported, including window modes | Separate contexts and rendering into several SDL windows |
| Full drag-and-drop | `draggable(payload)`/`on_drop`, native clone, target highlighting; lifecycle through `on_event`, safe source handle | Autoscroll, more complex payloads and additional application scenarios |
| Additional animation control | Managed CSS keyframes and enter/exit are implemented; one animation per node | Direct `Element::Animate`/`AddAnimationKey`, pause/resume, parallel clips, smooth reversal of exit and automatic retention of removed list entries; `var(...)` inside managed keys is not supported yet |
| Additional media queries | Native `media(...)`, typed conditions, conjunction/not and the theme API are implemented | The remaining native conditions are available as a string; nested queries and CSS Level 4 comparisons are not supported by RmlUi itself |
| RCSS custom properties/`var(...)` | Available as strings through `property`, supported by the local RmlUi | Convenient tokens and a palette switching example; no separate inheritance mechanism has to be written |
| DPI on real hardware | Initial display scale and pixel dimensions, display scale change events that keep the user scale, dp and atlas resolution are implemented | Physical moves between monitors with different DPI; the tests currently change the display ratio programmatically |
| Other tiled/text decorators | The ninepatch helper and example are ready; tiled-box, tiled-horizontal/vertical and the text decorator are available through `property` | Dedicated helpers/examples for these decorators and for font icons |
| Radial/conic gradients, mask-image, 3D perspective | Available through RCSS with a suitable renderer; GL3 implements the required extensions | Examples/checks of masks, gradients, nested clipping and 3D. This status must not be carried over to SDL_Renderer |
| Full form semantics | `<label>` and `<form>` are created through `element(name, tag)`, the label→focus transition is checked in `tests/elements.das`; the native submit dictionary is not bound; password is possible through the input type attribute | Name/value form submission. The current `on_submit` is an Enter handler, not a native form submit |
| Touch and IME | The SDL adapter forwards touch, an IME handler is connected; composition is protected when an input is updated | Real scenarios on devices/IME, application touch callbacks and gestures. Basic event forwarding is already there |
| Font fallback and shaping | `rui_font` and `rui_fallback_font` exist; the Localization example shows Cyrillic with Segoe UI. FreeType is used | Checks of fallback chains/CJK; a separate HarfBuzz integration for complex shaping and an RTL check. Loading a font does not solve this by itself |
| Table layout | `display: table*` is available through `property` | Helpers and a table example with row/col spans |
| Additional DataModel callbacks | Public models, native bindings and deferred event callbacks are implemented | Synchronous user `BindFunc` getters/setters and transform callbacks from daScript |
| File system and resources | FileInterface reads registered text resources from memory and other files from disk; texture loaders read PNG from disk | Archives, invalidation/cache reload, in-memory textures, more formats if needed |
| Update scheduling | Components skip recomputation, but the host keeps calling Update/Render and SDL_Delay | Integration of `Context::GetNextUpdateDelay` with the event queue, animations and signals; check idle CPU |
| CSS Grid | Not available: the RmlUi property index has no grid layout | Nothing to export until RmlUi supports it |

`rui_watch` remains a legacy subscription for a limited set of types. The new `on_event`
is registered directly on the element for any native event. `stop` and
`stop_immediate` are applied synchronously from the subscription parameters: RmlUi ties
stopping propagation to cancelling default actions. A deferred setter cannot change a
native dispatch that has already finished; there is no independent PreventDefault here.

## Examples of native features and tests

- `rich_text_lab.das`: The Field Notes, nested font styles and sizes, inline PNG/sprites,
  links with mouse/keyboard, dynamic width and a footnote. `tests/rich_text.das`
  checks native line wrapping, baselines of different fonts and images, superscript,
  inheritance, br/whitespace, reactive text/href/src, hybrid idle and GC.

- `drag_drop.das`: move, reorder that keeps the keyed handle, rejection when the
  container is full, cancel outside and an invalid payload.
- `templates.das`: two instances of a native template, three named slots, selective
  removal of the editor, move/resize, input binding, close/reopen and ui_reset.
- `localization.das`: three languages, plural forms, fallback, native RML translation,
  external set_locale without changing the model, input/focus preservation.
- `progress_lab.das`: 0/50/100%, opacity of different parts of the curve, sprite
  position, size/value of the radial progress, reset and play/pause.
- `expedition.das`: range/radio/tabset/textarea/sprite selection and resize.
- `effects.das`: filter controls, transform/type tabs and reset.
- `animations.das`: floating ship, looping beacon, cancelling the panel exit without
  remount, notifications with deferred removal, launch completion and stop ambient.
- `style_lab.das`: two themes, dp scale, media layout, one atlas for frames of different
  sizes, text preservation. A separate ninepatch pixel test runs on SDL.
- `event_studio.das`: keyboard/context menu, popup, modal and a hideable local
  editor. `events.das` and `documents.das` check event phases/parameters,
  cancellation, subscriptions/GC, focus, layers, modal, popup and dropping stale commands.
- `navigation_lab.das`: native nav, ID transitions, scroll, popup and the stock Debugger.
  `navigation.das` and `debugger.das` check modes, focus, picking, styles,
  lifecycle/GC, restart and the absence of extra updates; there is a negative ID test.

- `vector_lab.das`: SVG file/inline/crop/decorator and native Lottie, changing the
  source, color and size, and remount. Runtime and pixel tests check independent
  bindings, native factories, templates, DPI, lifecycle, loading and animation frames
  over time.

- `native_lab.das`: custom waveform elements from daScript, update/paint independent of
  components, attributes, events, keyed identity, resize, Hold and GC. Runtime tests
  check captured values, callbacks, templates, unregistration, shutdown and errors.

There are also Mesh Lab, Decorator Studio and Shader Lab: arbitrary geometry and
textures, scripted decorators, custom GLSL programs and filters.
All of them are registered in CTest. Effects, Progress Lab, Animations, Style Lab,
Vector Lab, Native Lab, Mesh Lab, Decorator Studio and Shader Lab have the `opengl` label
and need a real OpenGL 3.3 context; the rest use the SDL dummy driver for smoke tests.

## Library extensions

Possible extensions of dasrmlui on top of RmlUi. They are not implemented and are not
part of the missing native API support.

| Extension | Purpose |
|---|---|
| Tree widget | Tree component with node expansion, selection and keyboard navigation |
| Table widget | Table component with sorting, row selection and cell editing; native RCSS table layout is tracked separately in the RmlUi coverage |
| Docking | Panel docking, splitters and saving the workspace layout |
| Variable-height virtualization | Measuring rows of different heights, computing the visible range and keeping the scroll position |

## Renderer and verification

`rui_init` uses a local SDL_Renderer bridge: geometry, PNG, text and a
rectangular scissor. It does not implement transforms, clip masks, layers, filters or
shader hooks. `rui_init_gl` uses a pinned copy of the upstream GL3 renderer in
`src/gl3/` with custom programs and passes in the native filter pipeline;
SDL3 still creates the window/context and delivers input.

The full run is `ctest --test-dir build -j 4 --output-on-failure`; it includes
`runtime_package` and the benchmark smoke test. Component examples
use `ui_state`/`ui_frame`; Harbour attaches the public model inside a component.
Every example is registered as a `demo_*` test.
`data_models`, `demo_data_models` and `data_model_type_error` check external RML,
native views/controllers, structs/arrays, errors/GC/the callback queue,
Context/Debugger and shutdown/restart. The runtime package runs Harbour entirely from
`.das`, without external RML/RCSS.
`native_data_dsl` checks the native region in hybrid/legacy components, the absence of
recomputation on native writes, scoped styles, escaping, nested lists,
keyed reorder that keeps handles/focus/selection, model change, GC and lifecycle.
Four negative tests check captures, region boundaries and managed operations.
The run includes the OpenGL examples, pixel tests,
template generation/slots, animations, media/theme/DPI, events/document modes,
Debugger/spatial navigation, SVG/Lottie, native custom elements, regressions and
negative DSL checks.
The native-element tests are `native_elements`, `native_safety`, `demo_native_lab`,
`native_host_lifetime` and `native_pixels`.
They cover captured values/GC, native callbacks, keyed identity, templates,
errors and reentry, unregister, shutdown/restart, late cleanup after main,
geometry, clipping, opacity, resize and DPI.
`demo_mesh_lab` and `native_mesh_pixels` check indexed geometry, UV, PNG/RGBA,
vertex colors, premultiplied alpha, tint, batch order, the cache after a handle is
released, array copying/GC, stale/foreign handles, remount/shutdown and cleanup after
a Paint error. Pixels are checked on SDL and GL3.
`demo_decorator_lab`, `decorator_pixels` and `decorator_host_lifetime` check decorator
registration and parameters, styles/hover/templates, separate canvases, paint-area,
texture, opacity/DPI/resize, GC inside Paint/Destroy (including local data of the
calling code), caching, errors, unregister and late host teardown.
`gpu_backend`, `demo_shader_lab` and `gpu_effect_pixels` check GLSL registration,
compilation/schema errors, typed uniforms, cascade/templates and granular bindings,
filter chain order, backdrop, a native filter after a custom one, straight/premultiplied
alpha, overflow, transform/clipping, DPI, GPU time with an idle component, GC and
shutdown/restart with live instances.
Shader Lab uses `[ui_shader]`/`[ui_filter]` and dasGlsl without GLSL strings.
`shader_dsl_compiler` and eight negative tests check generation, the typed schema,
helpers/structs/loops, input/result types, mutable/default parameters, CPU capture
and source sampling restrictions. `gpu_effect_pixels` repeats the fixture with GLSL
and with the DSL.
The runtime package contains dasGlsl and is checked by running the SDL Dashboard and
the GL3 Shader Lab.
The SVG/Lottie pixel test on SDL checks
transparent margins/crop, the decorator, tint/opacity, inline replacement, DPI, resize,
source change and the actual positions of the animated shape after 0/0.5/1/2 seconds.
The runtime tests also check in-memory and corrupted resources, load errors
followed by recovery, and re-registration of the plugins after shutdown.
Ninepatch is checked separately by the pixels of the four corners and the center on SDL
at different sizes, at 1x/2x and on a theme change. This is not a check of every row of
the matrix and not a full pixel-golden comparison of all screens.

## Sources

- [Native elements](https://mikke89.github.io/RmlUiDoc/pages/rml/element_index.html)
- [RCSS property index](https://mikke89.github.io/RmlUiDoc/pages/rcss/property_index.html)
- [Media queries and themes](https://mikke89.github.io/RmlUiDoc/pages/rcss/media_queries.html)
- [Decorators and renderer requirements](https://mikke89.github.io/RmlUiDoc/pages/rcss/decorators.html)
- [Ninepatch](https://mikke89.github.io/RmlUiDoc/pages/rcss/decorators/ninepatch.html)
- [Documents and modal state](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/documents.html)
- [User interface, drag and navigation](https://mikke89.github.io/RmlUiDoc/pages/rcss/user_interface.html)
- [Built-in Debugger](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/debugger.html)
- [SVG plugin](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/svg.html)
- [Lottie plugin](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/lottie.html)
- [Custom elements](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/custom_elements.html)
- [C++ API and plugins](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual.html)
- [Native data binding](https://mikke89.github.io/RmlUiDoc/pages/data_bindings.html)

`Context.h`, `Element.h`, `ElementDocument.h`, `Factory.cpp`,
`ElementFormControlInput.cpp`, the SDL/GL3 backends and the set of Samples of that
revision were also checked.
