# dasrmlui

A DSL for [RmlUi](https://github.com/mikke89/RmlUi) written in **ordinary daScript
syntax**. `[ui_component]` describes a tree and its behavior, `[ui_style]` describes
scoped RCSS rules, `[ui_template]` describes the frames of native documents. An
application needs no separate `.rml` or `.rcss` files.

The window, the SDL renderer, the event loop, the model, the components, the styles and
the DSL runtime are written in daScript. C++ is used for the host, the RmlUi bindings
and the RenderInterface. The project uses the real `sdl3` module and `dassdl3/*` from
dasSDL3; it does not replace them with an SDL API of its own.

## Getting started

Tested profile: Windows x64, MSVC, Release and RelWithDebInfo, with a locally built
dasSDL3. Other configurations and the portable package are covered in
[Dependencies and build](#dependencies-and-build).

```powershell
./tools/build.ps1
./build/bin/dasrmlui.exe examples/inventory.das
```

The demo edits item names, adds and removes items, reorders the list and shows
conditional details of the selected item. An empty name is rejected by the setter.

```powershell
ctest --test-dir build --output-on-failure
./build/bin/dasrmlui.exe examples/inventory.das --smoke-test
```

A smoke run draws a few frames in a hidden window and saves `logs/inventory.png`. The
build script creates the `logs` folder. Most tests run with the SDL dummy video driver;
the examples that need filters, shaders or meshes use a real OpenGL context, and the
pixel tests for ninepatch, SVG/Lottie and native elements use a real SDL renderer.

## Application examples

```powershell
./build/bin/dasrmlui.exe examples/dashboard.das
./build/bin/dasrmlui.exe examples/settings.das
./build/bin/dasrmlui.exe examples/kanban.das
./build/bin/dasrmlui.exe examples/catalog.das
./build/bin/dasrmlui.exe examples/component_lab.das
```

- **Dashboard:** summary metrics, search and filters, a keyed task list, editing the
  selected task in an inspector, changing status and priority.
- **Settings:** tabs, a draft and a saved state, email validation, conditional advanced
  fields, accent and density choice with a live preview.
- **Kanban:** three columns, moving cards with buttons, creating, editing, priority and
  deletion through an inspector.
- **Catalog:** a library of 5,000 objects, a virtual list, cached search, an adaptive
  details panel, an editor with a local draft, focus, numeric fields, a checkbox and a
  select.
- **Component lab / Quote builder:** service cards with local state per key, reordering,
  removal and re-creation, `computed`, a content slot, component events and an
  `on_mount`/`on_unmount` log.

Each example has its own theme. The shared styles and components are in
`examples/advanced_style.das` and `examples/workbench_style.das`; the SDL loop is in
`examples/demo_host.das`. The visual reference was the
[official RmlUi gallery](https://github.com/mikke89/RmlUi#gallery); no images from the
gallery are included.

The data lives in memory: the examples do not use the network and do not save settings
to disk. Every example accepts `--smoke-test`: a few frames with real UI events checked
against the application state, and screenshots in `logs/`. Clicks go through SDL, RmlUi
hit testing and the same queue as user input. For a visual check run a smoke test without
`SDL_VIDEODRIVER=dummy`: the software renderer of the dummy driver does not support the
premultiplied blending in use. The main scripts set `options stack = 65536` for the
nested blocks of the interpreter.

The full description of the API and its limits: [state, computed, forms, virtualization,
focus and adaptive layout](docs/dsl.md).

## Examples of native RmlUi features

Run from the project root, after `./tools/build.ps1`:

```powershell
./build/bin/dasrmlui.exe examples/expedition.das
./build/bin/dasrmlui.exe examples/effects.das
./build/bin/dasrmlui.exe examples/drag_drop.das
./build/bin/dasrmlui.exe examples/templates.das
./build/bin/dasrmlui.exe examples/localization.das
./build/bin/dasrmlui.exe examples/progress_lab.das
./build/bin/dasrmlui.exe examples/animations.das
./build/bin/dasrmlui.exe examples/style_lab.das
./build/bin/dasrmlui.exe examples/event_studio.das
./build/bin/dasrmlui.exe examples/navigation_lab.das
./build/bin/dasrmlui.exe examples/vector_lab.das
./build/bin/dasrmlui.exe examples/native_lab.das
./build/bin/dasrmlui.exe examples/mesh_lab.das
./build/bin/dasrmlui.exe examples/decorator_lab.das
./build/bin/dasrmlui.exe examples/shader_lab.das
./build/bin/dasrmlui.exe examples/rich_text_lab.das
./build/bin/dasrmlui.exe examples/data_models.das
```

| Example | What it shows |
|---|---|
| Expedition | PNG sprite sheet, range, radio, textarea, native tabset, a fuel indicator |
| Effects | Filters, a stack of shadows, backdrop blur, transform, a shader, glow/outline/shadow on text |
| Drag & drop / Field logistics | Native drag clone, moving between containers, insertion before a card, a capacity limit, canceling a drop outside |
| Window template / Field office | Two documents with a shared frame, three arbitrary `slot(name)` places for actions, notes and status; independent components, conditional unmount of the editor, native move/resize and close/reopen |
| Localization / Explorer passport | English/Deutsch/Russian, `TranslateString`, a reactive `tr`, parameters, plural forms, fallback to English; the draft and the input handle are kept |
| Progress Lab / Follow the signal | Filling an S-curve by accumulated segment length, a moving sprite, a native radial `fill-image`, play/pause, a slider and reset |
| Animations / Orbital | Scoped keyframes, looping motion, stop/replay, a sliding panel that keeps local state when closing is canceled, notifications with exit/unmount, completion of a launch |
| Style Lab / The relay station | Media queries, Night/Paper themes, 100/150% scale, `dp`, an adaptive notes panel, ninepatch frames of different sizes from a 2x atlas; input is kept |
| Event Studio / Signal desk | Full event snapshots, Ctrl+S, keyboard/context menu, popup dismissal, a native modal, hide/show of an editor with a local draft, move/resize and a log |
| Navigation Lab / Vector deck | Native nav Auto/TreeOrder, explicit ID transitions, disabled, scroll and popup; the stock Debugger on F8, Element Info, Event Log, Outlines and Data Models |
| Vector Lab / Vector atelier | SVG from a file and inline, crop, an SVG decorator, Lottie JSON; changing source, color and size, remount, and animation without component updates |
| Native Lab / Signal foundry | Three oscillograms as real custom elements: registration from daScript, own geometry, native update/paint, events, keyed reorder, remount, resize, Hold and GC |
| Mesh Lab / Bend the surface | Arbitrary indexed meshes, a UV ribbon, a ring progress, vertex colors, a PNG atlas and an RGBA texture from daScript, tint/alpha, caching and release of resources |
| Decorator Studio / Edges, made in script | One custom decorator on ordinary cards, buttons and an input: RCSS parameters, a shaped frame, a PNG stamp, progress, hover, resize and GC |
| Shader Lab / Light studies | `[ui_shader]`/`[ui_filter]` in daScript through dasGlsl: a procedural surface, a chromatic filter and a glass backdrop; typed uniforms, GPU time, a slider, color change, remount and GC |
| Rich Text Lab / The Field Notes | Formatted inline fragments, nested styles, links, PNG images and sprites, dynamic wrapping |
| Data Models / Harbour | `[ui_component]` with `native_data` and `[ui_style]`, no external RML/RCSS; a public Context model, native forms, lists and expressions, callbacks and the stock Data Models panel |

All of them are part of CTest. The GL examples need OpenGL 3.3 and the Windows video
driver; the SDL dummy driver is not enough. Localization uses the installed
`C:/Windows/Fonts/segoeui.ttf` for Cyrillic; the font is not copied and not distributed
with the project.

```powershell
# All tests, including the OpenGL and SDL pixel checks:
ctest --test-dir build --output-on-failure
# Only the examples of native features:
ctest --test-dir build -R 'demo_(expedition|effects|drag_drop|templates|localization|progress_lab|animations|style_lab|event_studio|navigation_lab|vector_lab|native_lab|mesh_lab|decorator_lab|shader_lab|rich_text_lab|data_models)$' --output-on-failure
# Without a graphics context:
ctest --test-dir build -LE graphics --output-on-failure
```

In every example the UI, the styles and the behavior are in `.das` files. A native
window template is generated from `[ui_template]` and passed through an in-memory
FileInterface; no hand-written RML string and no external `.rml` are needed. See
[native documents and templates](docs/dsl.md#native-documents-and-templates). The atlas
image is a [separate PNG resource](examples/assets/expedition_atlas.png); where the
assets come from is recorded in [examples/assets/README.md](examples/assets/README.md).

## Components and bindings

The complete example is in `examples/inventory_ui.das`:

```das
[ui_component]
def inventory_panel(var model : InventoryUi) {
    use_style(@@inventory_style)

    column("panel") {
        when(empty(model.items)) {
            text("empty", "No items")
        }

        model.items |> each_keyed($(item : Item) => item.id) $(item : Item) {
            row("item") {
                text_input("title") {
                    bind_value(item.title) $(value : string) {
                        rename_item(model, item.id, value)
                    }
                }
                stock_badge(item.count)
            }
        }
    }
}
```

- `column`, `row`, `box`, `text`, `text_input`, `button` create the standard elements.
  `element("name", "img")` creates an element with any other RmlUi tag.
- `class_if("selected", condition)` and `pseudo_if(...)` switch a class or a
  pseudo-class by a condition. Unlike an inline property, a class change runs a
  `transition`.
- Nested `[ui_component]` functions are ordinary function calls. daScript checks the
  parameters.
- `when` creates and removes a subtree. When it appears again it is a new instance.
- `each_keyed` takes an array and **`int` keys that are unique within one list**.
  Reordering keeps the element handles; removing a key and adding it again creates new
  handles. Duplicates are reported.
- `bind_value` synchronizes text through the RmlUi `change` event. The getter is called
  during an update, the setter when the event is delivered. The setter may reject or
  normalize the input; the next pass puts the model value back into the field.
- `disabled() { return condition; }` updates the attribute, the pseudo-class and the
  availability of a button. Disabled elements receive no clicks, including clicks
  already queued when an earlier command disabled them.
- `on_click` receives an event from the queue. Neither the block nor the address of an
  array element is kept after the function returns.
- `ui_frame(state) $(model:Model) { ... }` delivers events, synchronizes the DOM and
  runs the RmlUi update.
- `ui_reset()` removes the created elements and clears the runtime before
  `rui_shutdown()`.

Do not change the model in the ordinary body of a component or in a getter: the body
can run several times per frame. Make changes in handlers, or through `ui_edit(state)`
before the frame. Ordinary loops that run one UI site repeatedly are not supported: use
`each_keyed`. For dynamic structure use `when`.

## The root model and external changes

`[ui_component]` uses hybrid bindings by default. Create the state once, after the
initial model is filled, and use it in every frame:

```dascript
var initial <- initial_inventory()
var state = ui_state(initial)

// In the application loop, after the SDL events:
ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }

// When external code changes the data:
ui_edit(state) $(var model:InventoryUi) {
    model.selected_id = -1
}

ui_read(state) $(model:InventoryUi) {
    print("Items: {length(model.items)}\n")
}
```

`ui_state` makes a deep copy of the initial value and is managed by the GC; no `inscope`
is needed. Changing the source variable after the copy does not change the UI. The root
is a structure without borrowed pointers or lambdas. References to the model taken in a
read, edit or frame block must not leave its scope. `ui_read` is read-only; the frame
macro allows a mutable borrow for the handlers of a component.

Writes made in `on_click`, in setters and in other component events are tracked
automatically. For direct external writes `ui_edit` is enough. An unknown mutating
helper causes a conservative invalidation, and `[ui_action]` narrows it down to the
actual writes.

An error inside `ui_edit` does not roll back the writes already made; the changes are
published. A frame cannot be started inside an edit. Passing a different state to
`ui_frame` resets the old tree. Plain dependency comparison without a native DataModel
is enabled explicitly with `[ui_component(legacy=true)]` and `ui_legacy_frame()`. See
[the full contract and a complete main](docs/hybrid.md).

## Styles

```das
[ui_style]
def inventory_style() {
    rule(root()) {
        padding(px(24.0))
        background(rgb(19, 25, 38))
    }
    rule(part("title")) {
        width(px(300.0))
        color(rgb(235, 240, 249))
    }
    part("action") |> hover() |> rule() {
        background(rgb(65, 117, 183))
    }
}
```

`UiLength` and `UiColor` are different types: `width(rgb(...))` does not compile. Typed
helpers exist for sizes, spacing, borders, positioning and flex properties:
`border(px(1), rgb(54,116,84))`, `border_radius(px(6))`, `margin_x(dp(8))`,
`position("absolute")`, `left(px(40))`. The full list is in
[docs/dsl.md](docs/dsl.md#typed-properties). For other RCSS properties there is
`property("transform", "rotate(4deg)")`.

`root`, `part`, `hover` and `disabled_state` generate selectors with the prefix of the
style sheet. `with_class(selector, name)` and `with_pseudo(selector, name)` add a class
from `class_if` or a pseudo-class such as `focus`. A nested component gets its own style
scope. To reuse a style explicitly, call the same `use_style(@@style_function)`.

`[ui_style]` requires a function without parameters and caches the result of its first
call. Such functions describe static rules and must not read mutable state. Dynamic
properties are set inside a component, for example `width() { return pct(...); }`.
`property` and the other setters apply to the current **container**. To style a text
leaf use `part(...)` or an explicit `box` around the text.

## How a component is expanded

For every `[ui_component] def panel(...)` the macro creates three separate functions,
`panel__mount`, `panel__update` and `panel__dispatch`, with the same arguments. The
original name becomes a wrapper that checks the dependencies and chooses the phase.

- `mount` creates the DOM and sets the initial values.
- `update` runs only when the inputs change or after an explicit invalidation. Static
  text nodes are kept without assigning the text again; properties with constant
  arguments are applied once. If `when` or `each_keyed` adds a subtree during an update,
  it receives both the static text and the initial properties.
- `dispatch` evaluates no text getters and no properties. The runtime visits only the
  components on the way to the receiver of the event. After a setter the component is
  updated even if the model did not change: this restores rejected input.

Identity takes into account the source file, the function, the call site, the enclosing
place and the list key. A skipped component keeps its DOM nodes, their order and its
child instances. Removing a subtree releases the component cache and the subscriptions;
when it appears again a new `mount` runs. There are no DOM wrappers for `each_keyed`
and `when`.

### Dependencies and cost

By default the macros track writes to the model. Direct scalar bindings use the native
DataModel: for them an idle frame and a point update need no per-frame comparison of the
whole root model. Structural changes run a pass over the components and keyed lists.
Bindings that did not change keep their values. What keeps a screen on the fast path,
and what does not, is described in [docs/hybrid.md](docs/hybrid.md).

For complex expressions and for legacy components the path that compares dependencies
remains. The macro extracts the reads of parameters and local values: `model.profile.name`
depends on that field, not on the whole `model.profile`. Scalars, enumerations, vectors,
structures, tuples and arrays are supported. A setter and the body of `when` are not part
of the dependencies of a value or a condition.

```das
[ui_component]
def profile(var model:Profile) {
    text("name") { return format_name(model.name) }
    text("email") { return model.email }
    box("preview") { width() { return px(model.preview_width) } }
}
```

A change of `email` calls neither `format_name` nor the width getter. In the generated
`profile__mount` and `profile__update` such an operation gets a guard of roughly this
shape (identifiers shortened):

```das
rt_binding("name-binding", $() { rt_dependency(model.name) }, false, false) {
    text("name-site", "name") { return format_name(model.name) }
}
```

The source field is checked, not the result of `format_name`: with an unchanged
dependency the call itself is skipped. A call of a helper with a whole structure depends
on the whole structure passed. Indexing is tracked conservatively by the source array and
the outer index, so that a check never performs a potentially unsafe read of an element.
Access to `item.title` inside `each_keyed` is tracked separately for every key.

`when` caches only the evaluation of its condition. While it stays `true` its child
bindings keep being checked, so a text change inside is not lost. Reordering a keyed list
keeps the snapshots of the bindings. When a subtree is removed its snapshots are cleared,
and adding the key again runs the bindings anew. `bind_value` is additionally updated
after a `change` of its own input, even if the setter rejected the value; neighboring
fields are not recomputed.

Arbitrary code before the UI calls and the argument expressions of child components run
as ordinary daScript code. Put expensive computations inside a getter or into a separate
component with narrow inputs. A getter that reads nothing the component owns is
evaluated on every pass.

For state the macro cannot see, pass compact inputs and use invalidation tokens:

```das
var inventory_changed = ui_signal()
var external_title = "Inventory"

[ui_component]
def external_heading() {
    ui_watch(inventory_changed)
    text("heading") { return external_title }
}

// In a handler or before ui_frame:
// external_title = "Updated inventory"
// inventory_changed |> ui_touch()
```

The macro moves `ui_watch` to the phase that registers dependencies. Its argument must
be available on entry to the function: a global variable or a parameter, not a local
variable inside `each_keyed`. `ui_touch` marks the subscriber **and all of its parents**,
so a sleeping parent does not block the update of a child. The explicit signal
invalidates every binding of the subscriber itself; in the parents it causes a visit and
keeps the caches of their independent bindings. Subscriptions are removed on unmount.

A global variable that a component reads directly is tracked like the model. State hidden
inside helper functions is not: report its changes with `ui_changed` or with a token and
`ui_touch`. Pointers, native handles, tables and closures are not supported as snapshots
in arguments; pass values or a version number.

`ui_stats()` returns the counters `mounts/updates/skips/dispatches` and
`binding_mounts/binding_updates/binding_skips`; `ui_clear_stats()` resets them. Skipping
a whole parent counts as one `skip`.

The native listener copies events into a queue. Every command is delivered separately,
then the DOM is synchronized before the next command; events of removed elements are
dropped. All user blocks are called synchronously, and no reference to the stack or to an
array element is kept.

### Block syntax and pipes

A block without parameters is written without `$`: `on_click() { ... }`,
`text("name") { return value; }`. `when(condition)` takes an ordinary `bool`, and
`bind_value(value) $(new_value:string) { ... }` takes the current value and a setter. The
forms with getter blocks are kept too. A block with parameters needs `$`. Inside macros
`$e/$v/$i` are AST substitutions and cannot be removed either.

`items |> push <| Item(...)` adds a value to an array;
`part("action") |> hover() |> rule() { ... }` builds a selector and then a rule. All of
this is parsed by the standard daScript parser.

For a long-running script loop use `options persistent_heap`, `options gc` and a
collection between frames; `ui_collect_garbage(8)` collects when the heap has grown by
the given number of megabytes, as in `examples/demo_host.das`.

## Coverage and limitations

The detailed [RmlUi coverage matrix](docs/rmlui-coverage.md) separates finished features
from partial bindings, missing helpers and unfinished examples.

- One UI context per process. Several RmlUi documents inside a window are supported;
  several independent SDL windows or contexts are not.
- `rui_init` uses SDL_Renderer: text, PNG textures, geometry and a rectangular scissor.
  For transforms, clip masks, layers, filters and shader decorators there is a separate
  `rui_init_gl` with the upstream GL3 renderer; the window, the context and the input
  stay in dasSDL3. `examples/effects.das` uses it.
- Moving a row restores the focus and the selection of a text input. The stock SDL IME
  adapter is connected; during composition an external assignment and a move of the
  focused row are postponed. Real input through particular IMEs has not been tested.
- Keys are `int`. `virtual_each` supports rows of a fixed height; variable height is not
  implemented. The cost is described in `docs/dsl.md`.
- There are helpers for select, range, radio, textarea, tabset, progress and sprite
  sheets; `examples/expedition.das` shows the other native controls.
- Media and theme rules, `dp`, DPI and ninepatch are described in `docs/dsl.md`. Moving
  a window between monitors with different DPI has not been tested.
- Hot reload on LiveHost keeps root and local state, supports migrations and a separate
  styles entry without a remount: [how to run it and the API](docs/hot-reload.md).
- There is no AOT profile and no complex text shaping. This is not a claim of complete
  RmlUi coverage; the limits are listed in the coverage matrix.
- Only the Windows/MSVC interpreter has been tested. CMake is not tied to MSVC or to
  Release, but other operating systems and toolchains have not been tried: they need
  dasSDL3 built with the same toolchain.
- The default font is LatoLatin from the RmlUi samples (`rui_default_font`). Load your
  own font, for example one with Cyrillic, with `rui_font` and name its family in
  `set_base_text("Segoe UI")`: it becomes the base font of every document.

## Dependencies and build

The project reads existing sources and libraries and changes nothing in the neighboring
checkouts. The locations are CMake cache variables:

| Variable | Default |
|---|---|
| `DASSDL3_DIR` | `../dasSDL3`, beside this checkout |
| `DASSDL3_BUILD` | `${DASSDL3_DIR}/build/ninja` |
| `RMLUI_DIR` | `../RmlUi`, beside this checkout |

```powershell
cmake -S . -B build -G Ninja -DDASSDL3_DIR=D:/work/dasSDL3 -DRMLUI_DIR=D:/work/RmlUi
```

The build uses the static libraries of daScript, SDL3 and FreeType from dasSDL3. CMake
reads the paths of SDL and FreeType from its cache and takes the system libraries of
SDL3 from its CMake package. No separate copy of daScript or SDL is linked into the
executable. This logic is in `cmake/dependencies.cmake`.

Tested revisions:

| Dependency | Revision |
|---|---|
| dasSDL3 | `a13e01f1f8a42683d212d4498137d37732529478` |
| daScript, as bundled in dasSDL3 | `ebac0ffe46ab30de6c9536f4b0af7a33ede45902` |
| RmlUi | `821cbd229d804cb1c905b729af86c21133abceee` |

SVG and Lottie use the official RmlUi plugins with pinned LunaSVG and rlottie. The first
build downloads them through Git: [versions, licenses and an offline build](docs/vector-dependencies.md).

### Configurations

A configuration must link against the given dasSDL3 build. A debug build changes the C
runtime and the daScript build id, so the rule is:

| dasSDL3 build | Allowed dasrmlui configurations |
|---|---|
| Release, RelWithDebInfo, MinSizeRel | Release, RelWithDebInfo, MinSizeRel |
| Debug | Debug |

CMake rejects an incompatible configuration at configure time with an explanation. If
`CMAKE_BUILD_TYPE` is not set, the first allowed one is taken. With multi-configuration
generators (Visual Studio) only the allowed ones are listed.

```powershell
./tools/build.ps1 -Configuration RelWithDebInfo -BuildDir build-relwithdebinfo
```

`tools/build.ps1` builds with the Visual Studio that configured the build directory
earlier. For a new directory it takes `-VisualStudio <path>`, then the `DASRMLUI_VS`
environment variable, then the latest installation with the C++ tools. It must be the
toolchain dasSDL3 was built with. Extra configure arguments go through `-CMakeArgs`:

```powershell
./tools/build.ps1 -CMakeArgs '-DDASSDL3_DIR=D:/work/dasSDL3','-DRMLUI_DIR=D:/work/RmlUi'
```

Library names follow the rules of the toolchain, and MSVC flags and Windows system
libraries are added only where they are needed. This has been checked only with MSVC and
Ninja (Release and RelWithDebInfo) and by configuring for Visual Studio 2022.

### Where the executable looks for scripts and the font

The host looks for the folders `daScript`, `dassdl3`, `dasrmlui`, `examples` and for the
file `assets/LatoLatin-Regular.ttf` in this order:

1. in the folder named by the `DASRMLUI_HOME` environment variable;
2. beside the executable and one level up (in a package the executable is in `bin/`);
3. in the tree it was built from, only if the build was made with
   `DASRMLUI_DEV_PATHS=ON` (the default).

`dasrmlui --roots` prints what was taken from where. Without the first three folders the
host exits with code 5 and a message; `examples` and the font are optional.

### Portable package

```powershell
cmake -S . -B build-package -G Ninja -DCMAKE_BUILD_TYPE=Release -DDASRMLUI_DEV_PATHS=OFF
cmake --build build-package
cmake --install build-package --component runtime --prefix dist
./dist/bin/dasrmlui.exe examples/dashboard.das
```

`dist` receives the executable, `daslib`, the das modules of dasSDL3 and dasrmlui, the
examples, the LatoLatin font with its license, and a `licenses` folder with the licenses
of dasrmlui, daScript and the RmlUi GL3 backend. The folder can be moved: with
`DASRMLUI_DEV_PATHS=OFF` no path to the build tree remains in the binary. The examples
address their resources relative to the current folder, so run them from the root of the
package. The `runtime_package` test builds such a package and runs an example from it.

What the package does not do: the licenses of the other linked libraries (SDL3,
FreeType, LunaSVG, rlottie) are not copied into it, and the binary keeps the names of
daScript source files from its debug messages.

## Tests

`ctest --test-dir build -N` lists every test. The tests run real RmlUi DOM and input.

- **Runtime and bindings.** `runtime.das`: identity and order after reordering, nested
  components, focus and selection, input through `ProcessTextInput`, two-way
  synchronization, a rejected value, conditional subtrees, removal and reuse of a key,
  the order of commands, stale events, work after GC. `incremental.das`: 120 frames
  without running bodies or getters, selective updates of child components, waking
  parents through dependencies, removal of subscriptions, a second mount, GC and reset.
  `bindings.das`: independence of neighboring and nested fields, properties, cached
  conditions with updates of their children, one-way and two-way values, disabled
  buttons and events to disabled targets, reordering, removal and return of keys.
- **Hybrid path.** `hybrid.das`, `hybrid_lifecycle.das`, `hybrid_arguments.das`,
  `hybrid_removal.das`, `hybrid_globals.das`, `state_api.das`: native views, tracked
  writes, idle frames without a pass, arguments passed by value, slots, lists of scalars,
  indexed bindings, tracked globals, removal of bound rows and one pass per event.
- **Generated code and diagnostics.** Separate tests check the three generated functions,
  the failure on duplicate keys and a type error in a style. Negative tests check both the
  exit code and the diagnostic.
- **Lifecycle and composition.** `lifecycle.das`: keys, the last state in cleanup, the
  order of removal, GC and a second reset. `composition.das`: computed, slots, events and
  dependency names in a trace. `viewport.das`: 10,000 rows with a bounded DOM,
  scroll/shrink/resize and keyboard focus. `forms.das`: drafts, ranges, overflow,
  validation, Enter/blur/Escape, a checkbox by mouse and a select by keyboard.
- **Templates and documents.** `templates.das`: generation of a native template, caching
  of several instances, scoped styles, escaping of text and attributes, dynamic content,
  GC and a second initialization of the context. `template_slots.das`: several arbitrary
  slots, independence of instances, kept state and focus, selective updates, a change of
  target, conditional unmount and a second reset. Negative tests cover dynamic constructs
  in a template, repeated or empty names, a missing target, filling an ordinary node and
  children inside a slot declaration. `documents.das`: hidden loading, focus modes,
  front/back, modal isolation, postponed input, a popup over a modal, Escape and outside
  dismissal, resize and a retained draft.
- **Events, navigation and the Debugger.** `events.das`: capture/target/bubble, mouse and
  keyboard parameters, synchronous stop of propagation and the native default action, GC,
  changes of subscriptions and stale queues. `navigation.das`: the stock `nav` modes,
  transitions by document-local ID, hidden and disabled targets, scroll, text input, a Tab
  scope and a popup. `debugger.das`: F8, native picking without calling an application
  callback, removal of the selected element, isolation of styles, focus, disabling and
  restart of the plugin.
- **Style environment.** `style_environment.das`: native media and theme rules and `dp`
  without a remount, automatic subscription of the components that read the environment,
  DPI and a kept user scale. `ninepatch_pixels` compares the corners and the center of
  actually drawn frames at different sizes, DPI and themes.
- **Vector and native rendering.** Runtime tests of SVG and Lottie check the native
  factories, a change of source, independent bindings, templates, DPI and lifecycle; the
  pixel test checks crop, the decorator, tint/opacity and the actual motion and looping
  of Lottie with frozen bindings. Tests of native elements cover keys, captured values, GC
  inside a callback, templates, errors and re-entry, unregistering, shutdown/restart and
  the end of the script Context; a separate pixel test covers geometry, clipping, opacity,
  DPI and resize. `native_mesh_pixels` checks SDL and GL3 pixels, blending order, atlas
  UV, tint/alpha, GC, stale handles and cleanup after a Paint error. `decorator_pixels`
  and `decorator_host_lifetime` cover custom decorators; `gpu_effect_pixels` and
  `gpu_backend` cover GL3 shaders and filters and the explicit refusal on the SDL
  renderer.
- **Examples.** Every example runs as a smoke test that delivers clicks and input through
  the RmlUi queue and checks the application state. The screenshots help a visual check;
  they are not pixel-golden tests, and the shader animation depends on time.

The geometric assets are reproducible: `./tools/make_style_atlas.ps1`,
`./tools/make_native_mesh_atlas.ps1` and `python tools/make_vector_assets.py`.

## More documentation

- [The DSL reference](docs/dsl.md): components, state, forms, lists, events, documents
  and templates, styles, navigation, the Debugger, SVG and Lottie, native elements,
  meshes, decorators, shaders and filters.
- [Hybrid bindings](docs/hybrid.md): what is tracked, what keeps the fast path, the
  contract for globals and opaque getters.
- [Public DataModel API](docs/data-models.md): `ui_data_model`, `ui_data_bind/set`,
  native forms, `ui_data_on/events`, `ui_load_rml`, and `native_data` inside a component.
- [Rich text](docs/rich-text.md): formatted inline fragments, links, images and sprites.
- [Hot reload](docs/hot-reload.md): lifecycle, state keys and migrations.
- [Benchmark](benchmarks/README.md): the DSL against native data binding;
  `./tools/benchmark.ps1` runs it. Bindings, Update, Render, GPU wait, GC and allocations
  are measured separately.

## Files

- `dasrmlui/macros.das`: the AST annotations of components, styles and templates.
- `dasrmlui/ui.das`: the runtime and the typed style API in daScript.
- `dasrmlui/shaders.das`, `shader_macros.das`, `glsl_ui_builtins.das`: the dasGlsl
  adapter, the shader and filter annotations and sampling of the source layer.
- `dasrmlui/data_models.das`, `live.das`, `live_state.das`: the public DataModel API and
  hot reload.
- `src/rml_module.cpp`: SDL_Renderer, safe handles and the RmlUi bindings.
- `src/hybrid.inc`: the native half of hybrid bindings.
- `src/native_elements.inc`: custom Element/Instancer, callbacks and the cache of native
  geometry.
- `src/native_decorators.inc`: Decorator/Instancer, the scheme of RCSS parameters and the
  canvas data of every use.
- `src/gpu_effects.inc`: native Filter/Decorator instancers and registration of GPU
  effects.
- `src/gl3/`: a pinned copy of the RmlUi GL3 backend with support for user programs.
- `src/host.cpp`, `src/live_host.cpp`: loading of modules and running
  `[export] main(smoke:bool):int`.
- `examples/inventory_ui.das`: an application model, components and styles.
- `examples/inventory.das`: a window and an application loop on dasSDL3.
- `tests/`: integration and negative tests.

### Live workbench and hot reload

```powershell
./build/bin/dasrmlui.exe examples/live_lab.das --watch --styles examples/live_lab_styles.das
```

Edit both `.das` files while the application runs. F5 reloads the code and keeps the
state, Shift+F5 resets it. A change of the separate styles entry keeps the DOM and the
focus. See [lifecycle, state keys and migrations](docs/hot-reload.md).

## License

dasrmlui is distributed under the [MIT license](LICENSE). `src/gl3/` is a modified copy
of the RmlUi GL3 backend and keeps [its own MIT license](src/gl3/LICENSE.txt). The
libraries linked into the executable (daScript, SDL3, RmlUi, FreeType, LunaSVG and
rlottie) keep their own licenses.
