# Hot reload / LiveHost

The upstream daScript `Module_LiveHost` is built into the executable. `--watch` uses
its persistent store, `@live`, lifecycle annotations, clock and reload/reset requests.
The SDL3/RmlUi frame driver is in `src/live_host.cpp` and `src/live_adapter.inc`.

## Running

```powershell
./build/bin/dasrmlui.exe examples/live_lab.das --watch --styles examples/live_lab_styles.das
```

Both files are regular daScript. First change the title, the notes and the order of the
cards in the UI. An edit to `live_lab.das` rebuilds the components and restores the
values. An edit to `live_lab_styles.das` replaces the styles of the existing DOM. F5
repeats the reload, Shift+F5 or `request_reload(true)` resets the data. `request_exit()`
closes the host.

The host watches the entry files and the loaded dependencies at a 250 ms interval.
Compilation is synchronous: frames are paused while it runs. File contents are
checked, so a write with the same size or time is also detected.
`--frames N --smoke-test` limits the run and hides the window for automated tests.

## Lifecycle

```das
require dasrmlui/live
struct App { title:string="Workspace" }
var app:$UiState<App>?

[export]
def init() {
    ui_live_window("My application",1100,760) // gl3=true — OpenGL 3.3
    app=ui_state("workspace",1,App())
}
[export]
def update() { ui_frame(app) $(var model:App) { workspace(model) } }
// Optional: [export] def shutdown() { ... }
```

The host owns the window, the SDL_Renderer or SDL_GLContext, event processing and
present. `update()` builds the frame; a live application does not need a separate
`main(smoke)`. The regular `main(smoke)` mode continues to work without `--watch`.
`ui_state` can also be created globally: before the simulation of a candidate the host
saves the current values of the previous Context. Between frames the standard LiveHost
policy `collectHeapIfMostlyFree` is used.
UI operations and native registrations must run in `init/update`, not in global
initializers: candidates are simulated in isolation from the running RmlUi.

Replacement sequence:

1. Compilation of the candidate while the old UI is running.
2. `[before_reload]`, snapshots of root/local state; then simulation and a check of the
   entry functions of the candidate. This way global `ui_state` variables get the most
   recent values. An error here keeps the running UI. After successful preparation:
   `shutdown`, `on_unmount`, DOM removal.
3. Shutdown of RmlUi, native elements/decorators/filters and their callbacks **before**
   the old daScript Context is deleted. The SDL window and the SDL renderer/GL context
   are preserved.
4. `[after_reload]`, `init` and the first `update` of the candidate, including local
   migrations.
5. On success the old Context is deleted and `get_reload_generation()` increases.
   If migration/init/the first frame fails, the candidate is deleted, the previous
   program is simulated again and restores the snapshot. On a compilation error there
   is not even a remount.

The first trial `update` still sees the previous generation. `[before_update]` is
called before regular frames. As in LiveHost, `is_reload()` stays true after a reload;
it is not a one-frame flag. On the final `shutdown` it is false. `get_last_error()`
returns the last host error. `request_reset()` corresponds to a full reload.
Arbitrary external effects of the user's `init/update/shutdown` are not rolled back.
An error in a regular `update` terminates the live runner with a non-zero code.

On a code reload a new RmlUi Context is created: native registrations, public
DataModels and additional documents must be created again in `init` from the saved
data. Raw native handles must not be treated as saved state. The renderer mode cannot
be changed within one session. DOM, focus and animations are preserved on a
**style reload**; a code reload performs a remount.

## Root and local state

```das
app=ui_state("workspace",1,App())

[ui_component]
def editor(id:int) {
    state("draft",2,Draft()) $(var draft:Draft) {
        // bind_value(...), handlers, on_mount/on_unmount
    }
}
```

Short forms: `ui_state("workspace",App())` and `state("draft",Draft())`, version 1.
The existing `ui_state(App())` and `state(Draft())` are also preserved in live mode:
the root gets a key from the source call site, the local state from the declaration
site in the component. For code that is being edited, explicit names are recommended:
moving the root lines or inserting an unnamed state changes the automatic key. Two
roots alive at the same time with the same key are rejected. Explicit local names must
be unique within a component. For a scalar local value the block takes a reference,
for example `$(var count:int&)`.

The full local key includes the identity of the component: its function and
signature, the place it is nested in and the `each_keyed` key. Inserting another named
local state does not shift an existing one. Renaming the component, changing its
signature or changing the identity of its parent changes the key and creates a new
state.
A regular unmount deletes the saved local value; an item that was removed and added
again does not get the old draft. `computed` is not saved: it is a derived cache.
`on_mount` runs again after the restore: it can overwrite the data, so initial values
should be set in the initializer, not unconditionally in the hook.
The snapshot is taken **before** `on_unmount`; changes made in teardown are not
included in it.

Values are serialized only on reload. In idle and on a regular `ui_edit` there are no
snapshots. The store contains JSON, with no references to the old VM heap. Structures,
arrays, tables, tuples, scalar/vector/enum and fixed arrays are supported. Tables are
encoded as an array of pairs, which preserves the key type; uint64 does not go through
float. Variants keep the type and a checked tag; changing their schema requires a
version and a migration. Pointers and callbacks are not carried over. The application
can additionally use the upstream `var @live value=...` for independent global data.

## Evolution and migrations

With the same version, fields are matched by name: reordering/removal is safe, and
new fields keep the initializer of the new model. An incompatible change of type or
meaning requires a version increase. For example, renaming `text` to `note`:

```das
struct Draft { note:string=""; clicks:int }

def ui_migrate(saved:JsonValue const?; old_version:int; var value:Draft):bool {
    if (old_version!=1) { return false }
    value.note=saved?["text"] ?? value.note
    value.clicks=saved?["clicks"] ?? 0
    return true
}
// state("draft",2,Draft()) ...
```

The same overload applies to root and local state of the corresponding type. `value`
already contains the new defaults; `saved` is the data of the old version. `false` or
an exception rejects the candidate. If there is no suitable overload, a version
mismatch is also rejected. For an intentional reset, perform a full reload. Snapshots
exist only in the current process: this is not saving to disk and not a user file
format.

## Styles without remount

The component uses `use_live_style("studio")`. An independent styles file:

```das
require dasrmlui/ui
[ui_style(name="studio")]
def theme() {
    rule(part("card")) { background(rgb(237,224,239)); padding(px(20)) }
}
[export]
def live_styles():string { return ui_style_sheet() { theme() } }
```

`--styles` compiles this entry separately and gets RCSS through the same DSL.
The named scope provides identical selectors without importing the styles file
into the component script. The rules are added after the regular component styles and
are kept across subsequent ui_frame calls. The update also applies to additional DSL
documents. Compilation errors, runtime errors and RCSS warnings keep the
previous stylesheet. The styles entry itself cannot access native RmlUi:
registrations of custom decorators/shaders must be done in the main `init`.

A change to a dependency shared by both entries triggers a code reload. `[ui_style]`
is not recognized automatically among arbitrary changes to a shared component file:
the path without remount needs a separate `--styles` entry. Textures, SVG,
Lottie and external resources are not included in this watcher.

## Checks

```powershell
ctest --test-dir build -R 'live_|demo_live' --output-on-failure
```

`live_reload`: root/local/keyed state, @live, full reset, GC, native teardown and SDL
window identity. `live_state_codec`: containers, types and field evolution.
`live_watch`: real file changes, DOM/focus, RCSS/compilation rejection, rollback of a
local migration, then successful root/local migrations with insertion of a new state.
`live_gl`: GL3 reload. `demo_live_lab`: smoke of the full example. `live_errors`:
diagnostics and non-zero exit on shutdown/native paint errors. Mutable fixtures are
written only under `build/`.
