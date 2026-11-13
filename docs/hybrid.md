# UI state: native DataModel and daScript components

`[ui_component]` uses the hybrid runtime by default. The root model is owned by
`ui_state`, and a frame runs through `ui_frame(state)`. Events inside components
track writes automatically; for changes from a timer, a loader or other external
code, use `ui_edit`.

## Minimal application

```dascript
options gen2
options persistent_heap
options gc
require examples/demo_host

struct Model { title:string = "Ready"; count:int }

[ui_action]
def rename(var model:Model; value:string) {
    model.title = value
}

[ui_component]
def screen(var model:Model) {
    column("screen") {
        text("title", model.title)
        text_input("edit") {
            bind_value(model.title) $(value:string) { model.title = value }
        }
        button("add", "Count: {model.count}") {
            on_click() { model.count += 1 }
        }
    }
}

[export]
def main(smoke:bool):int {
    var initial = Model()
    var state = ui_state(initial)
    return run_demo("State example", "logs/state-example.png", smoke, $() {
        ui_frame(state) $(model:Model) { screen(model) }
    }) $(frame:int) {
        if (frame == 0) {
            ui_edit(state) $(var model:Model) { rename(model, "Updated externally") }
        }
    }
}
```

`run_demo` calls the render callback; the callback itself opens `ui_frame(state)`.
In a regular SDL loop the same call is placed after native event processing.
The frame block parameter is written as `model:Model`: the macro provides the scoped
mutable borrow that components with `var model` and their handlers need.

Reading outside a frame does not open write access:

```dascript
ui_read(state) $(model:Model) {
    print("Count: {model.count}\n")
}
```

An external change does not need a separate `[ui_action]` if the write is located
directly in `ui_edit`:

```dascript
ui_edit(state) $(var model:Model) {
    model.count += 1
    model.title = "Background task completed"
}
```

`on_click` handlers, setters, events and other supported component callbacks are
already tracked. In Catalog the working changes happen in them, so an additional
`ui_edit` around each event is not required. In Progress Lab, playback changes the
model from tick, so tick uses `ui_edit`. The smoke code of the examples also uses
`ui_edit` to access the model under test.

## Tracking helpers

Direct writes in `ui_edit` and in handlers are tracked per field. For an unknown
mutating helper the runtime applies conservative invalidation: correctness is
preserved, but more bindings may be updated. `[ui_action]` on a helper makes it
possible to track its writes more precisely. Also annotate the mutating helpers it
calls: there is no interprocedural analysis of arbitrary code.

A global variable that a component reads directly is tracked like the model; see
[Global data and opaque getters](#global-data-and-opaque-getters). Data that is read
through a function call is not visible to the annotation: report its changes with
`ui_changed`, with `ui_signal` / `ui_touch` / `ui_watch`, or keep an explicit revision
in the model. Catalog uses a revision for the global assets array, Component Lab uses a
signal for the lifecycle log.

## What is generated and executed

The assignment `model.title = value` conceptually expands to:

```dascript
rt_ui_write(model.title) $(var target:string&) { target = value }
```

The helper gets the lvalue reference once, performs the write and notifies the bridge.
Supported: `=`, `:=`, `<-`, the compound `+=`, `-=`, `*=`, `/=`, `%=`, `|=`,
`&=`, `^=`, shift/logical compound assignments, the statement increments `++`/`--`,
and the statement calls `push`, `push_clone`, `emplace`, `insert`,
`erase`, `clear`, `resize`, `pop`, `sort`, `reverse`. For unknown mutating helpers
conservative invalidation applies; `[ui_action]` refines the tracked writes.

The direct field/index/variable bindings `text`, `bind_value`, `bind_checked`,
`attribute("name", field)`, `property("name", field)`, `class_if("name", field)`
register a native variable and view. Scalar types: string, int, float, bool, double.
Complex expressions, typed style helpers, `when`, computed and other operations
are still executed by the DSL runtime. Their dependencies are registered as reasons
for a structural pass; while the model is unchanged there is no per-frame snapshot of
the whole model. Regular `if`/`while` in a component also register the dependencies
of their conditions. Conditions on temporary local values conservatively keep the
repeated pass. A legacy component inside a hybrid tree also enables this fallback.
Regular helper functions that create UI, and a list over a local or computed array,
also enable the conservative pass. A binding to an element by index
(`text("title", model.rows[model.picked].title)`) is bound to the element selected
in that pass; a write to whatever the index reads triggers a pass and a new selection.

### Call arguments are dependencies

Before calling a component, the caller subscribes to whatever the arguments are
computed from. A value passed by value (`lane(board, 2, "Review")`,
`metric("Open", "{length(items)}")`) is a copy inside the component: it changes only
together with the caller, so a binding to it does not hold a pass on every frame.
A write to its source (`model.caption`, from which the argument is computed) triggers
one structural pass. An argument of a reference type (a list row, a model structure)
remains the same storage: the fields the component is bound to directly are still
updated without a pass.

The same rule applies to computed arguments of primitives: the part name
(`box(wide ? "wide" : "narrow")`), the document in `document_content`, `draggable`,
`animate`, `select_options`. Primitives with their own binding (`progress_bar`,
`sprite_image`, `tab_label`, `svg_image`, `lottie`, `nav*`, `custom_decorator`,
`custom_shader`, `custom_filter`, `pseudo_if`) and the containers `native_element`,
`flow` work on the fast path like `text` and `property`.

A regular function called from a component does not enable the conservative pass if
its body shows that the result is determined by the arguments and by the global
variables it reads itself: it calls `use_style`, `property`, `attribute`, typed
properties and functions of the same kind, and branches on them. The global variables
it reads are tracked at the call site. A function that creates elements or takes a
block remains opaque.

A block argument — a slot (`slot(content)`) or a component event
(`emit(removed, id)`) — is code of the calling component, and everything it reads is
already registered there. A component with such an argument does not hold a pass if
it is called from a hybrid component; called from opaque code, it does. Arguments of
type function and lambda are still opaque.

After an event one structural pass runs, not two: the second is needed only if the
first itself requested an update (for example, a write in `on_mount`).

A block parameter that the runtime itself keeps fresh also counts as a copy: an
`each_keyed` element over a list of scalars (`model.ids |> each_keyed(...) $(id:int)` —
the list watches the element) and a `computed` value (it changes only inside a pass).

The conservative pass on every frame remains for a local variable
(`let total = …; badge(total)`, `text("t", total)`) and for a list over a local
array. A component called not from another hybrid component (from the `ui_frame` body,
from an opaque function) does not treat its by-value arguments as covered.
The called component, the transparent function and the global variable must be
declared above the place where they are used.

### Global data and opaque getters

A global variable that a component reads directly — in a binding, a condition, an
argument, as an `each_keyed` collection — becomes, for the duration of the pass, the
same kind of tracked storage as the model:

```dascript
var crew : array<Member>

[ui_action]
def rename(index:int; name:string) { crew[index].name = name }   // reports the write itself

[ui_component]
def roster(model:Model) {
    crew |> each_keyed($(member:Member) => member.id) $(member:Member) {
        text("name", member.name)                                  // updates without a pass
    }
}
```

A write to such a variable from a handler of a hybrid component or from an
`[ui_action]` reports itself automatically. A write from any other code is not
detected: after it, call `ui_changed(crew)` or `ui_changed(crew[0].name)`. A binding
expression that reads a global variable is re-evaluated on every pass.

An opaque getter — an expression that reads neither component data nor global
variables directly (`text("clock") { return clock_text() }`, the argument
`badge(now_text())`, the condition `if (is_ready())`) — is evaluated on every pass,
but does not request a pass itself. A change in what it reads is reported with
`ui_changed(value)`, or with `ui_touch(signal)` together with `ui_watch(signal)` in
the component.

The native part uses the real **Rml::DataModel / DataViews**, `BindFunc`,
`DirtyVariable` and the standard value/checked/attribute/style/class views. For text
there is a small `DataView` adapter that updates the existing text node without
re-parsing RML and without losing the text cache on a keyed reorder.
Each binding has its own native variable. So a write to one row does not mark the
whole `rows` array dirty.

The model is registered in the Context under the reserved name `dasrmlui` and is
updated through `rui_hybrid_flush` before the final Context::Update. The stock Debugger
shows its scalar slots (`v0`, `v1`, …), not the full script structure. For external
RML there is a [public DataModel API](data-models.md) with named fields. Internal
headers of the pinned RmlUi version are used (`DataModel.h`, `DataView.h`); upstream
is not modified. When RmlUi is updated, the compatibility of this adapter must be
checked.

## Memory, lifetime and structure

- Native stores **copies of scalar values**, including its own strings. Field addresses
  are subscription keys; Update/Render never dereference stored script memory.
  The native model does not hold a script lambda, a borrowed block or the model object.
- On a structural pass the addresses of the fields of the passed model, of its arrays
  and of the local state/computed storages are recorded.
  Temporary local/computed values outside this set require the component to be
  executed again; they do not get a dangerous long-lived address subscription.
- After a change to a collection, a key or a structural dependency, a regular pass
  over components and `each_keyed` runs, then the address subscriptions are rebuilt.
  A change of the key itself recreates the corresponding component; a reorder of
  existing keys preserves the DOM and the local state.
- A node, a component, a binding and a handler are named by a 64-bit number: the number
  of the place they are nested in, mixed with their own call site, key or ordinal
  number. A dependency snapshot is also a number. The structural pass itself therefore
  leaves almost nothing in the script heap; temporary strings come from computed
  bindings when their value changes. Two different places get the same number with a
  probability of the order of 2^-64 per pair.
- The script heap is persistent. The application loop calls `ui_collect_garbage(8)`
  between frames: a collection runs when the heap has grown by the given number of
  megabytes since the last collection; the second argument forces a collection. In idle
  on the fast path there are no passes and the heap does not grow.
- `ui_find` and `request_focus` with an element key find the node by the keys of the
  enclosing lists. Four levels of nested `each_keyed` are stored; for deeper nodes the
  outermost key is not taken into account.
- Native variables of released bindings are reused: capacity is bounded by the maximum
  number of bindings that existed at the same time. `ui_reset` and shutdown destroy the
  model completely. On unmount, handlers see a DOM that is still alive.
- On the render pass, hybrid `each_keyed` reads the source array without a clone. Do
  not change the structure of this array from render/on_mount during the traversal —
  the regular daScript array lock applies. Event dispatch keeps the snapshot path.
- Input is dispatched by our handlers; a tracked setter updates the model, and the
  native view displays the accepted result. A rejected value is restored from the
  model. `change` events that arise when a native view is applied programmatically are
  not returned to the setter as new user commands (including checkbox).

## Ownership, borrowing and errors

- `ui_state(initial)` is created once for the lifetime of the screen, before the frame
  loop. It deep-copies initial into a GC-managed object. It is a regular variable,
  without `inscope`. Later writes to the original initial do not change the UI state.
- The root must be a structure that owns its data. Borrowed pointers, lambdas and
  borrowed blocks are not allowed in the root. Initialize arrays and nested structures
  before `ui_state`, or change them later inside `ui_edit`.
- `ui_read` gives readonly access. `ui_edit` and `ui_frame` provide a borrow limited to
  the lifetime of the block; do not store references/pointers to the model and its
  fields, and do not capture them in escaping callbacks. Store the state for the next
  access.
- `ui_edit` is not a transaction with rollback. If the block is interrupted by an error
  after some of the writes, the changes already made remain and are published by the
  runtime.
- `ui_frame` inside `ui_edit` is forbidden. Finish the edit, run the frame, then open
  the next read/edit scope if needed. The additional smoke frames of Templates and
  Event Studio are arranged this way.
- When a different state is passed to `ui_frame`, the old tree is reset. This is a
  change of the screen owner, not a way to preserve the local state of the old tree.
  `ui_reset()` clears the tree before shutdown; nested frame calls are forbidden.

The frame body describes the UI and can be skipped in idle. Do not change the model in
a regular component body or getter: use a handler or an external `ui_edit`.
The runtime takes into account size, locale/style/debugger revisions, events and
explicit signals. Virtualization, presence animations and focus requests keep the
regular pass.

Hybrid mode does not mean that every binding is served by a native DataView.
Structural dependencies, complex expressions and opaque external reads keep the
fallback. During such passes, dependency snapshots, traversals and temporary
allocations may be used. Optimizing point writes does not remove the cost of an
arbitrary tree rebuild.

## Explicit legacy mode

The old value-comparison mechanism needs both explicit markers:

```dascript
[ui_component(legacy=true)]
def legacy_screen(var model:Model) {
    text("title", model.title)
}

// model here is a regular long-lived structure, without ui_state.
ui_legacy_frame() { legacy_screen(model) }
```

Do not mix frame modes for one mounted tree. There is no public `ui_hybrid_frame`.
`rt_hybrid_frame` is an internal low-level entry used by a few tests, not an
application API.

## Checks and measurements

The managed state contract is checked in `tests/state_api.das`; the low-level properties
of the bridge and of lifetime are checked in `tests/hybrid.das` and
`tests/hybrid_lifecycle.das`; what keeps the fast path is checked in
`tests/hybrid_arguments.das`, `tests/hybrid_globals.das` and `tests/hybrid_removal.das`.
The examples use this API; their smoke runs are
`ctest --test-dir build -R '^demo_'`. Inventory is run separately:
`./build/bin/dasrmlui.exe examples/inventory.das --smoke-test`.

The [benchmark](../benchmarks/README.md) compares the DSL, native C++ data-for and the
hybrid runtime. The `mutation` phase, which includes the model change and the
notifications, must be considered together with `bindings`.
