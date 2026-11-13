# Public DataModel: daScript components and external RML

`require dasrmlui/ui` exports the API of the models registered in the current
`Rml::Context`. A model can be connected to a `[ui_component]` through `native_data`
or to existing `.rml`/`.rcss` with native `data-*`.
Components with regular `bind_value`/`text(model.field)` continue to use `ui_state`,
`ui_edit` and `ui_frame`; you do not need to create this model manually or poll its
events.

## Inside ui_component, without external RML

```dascript
[ui_style]
def dispatch_style() {
    rule(part("form")) { width(px(420)); padding(px(24)) }
    rule(with_class(part("cargo_row"), "priority")) { background(rgb(250,230,190)) }
}

[ui_component]
def dispatch_panel(model:UiDataModel) {
    use_style(@@dispatch_style)
    native_data("form", model) {
        column("fields") {
            text_input("captain") { data_value("voyage.captain") }
            checkbox("ready") { data_checked("voyage.ready") }
            button("depart", "Clear for departure") {
                data_disabled("!voyage.ready")
                data_event("click", "depart(voyage.captain)")
            }
            text("status") { data_text("status") }
            data_if("notice", "voyage.ready") { text("notice_text", "Ready") }
            data_for("cargo_row", "item", "cargo") {
                data_class("priority", "item.priority")
                text("name") { data_text("item.name") }
            }
        }
    }
}
```

The model is declared with the same `ui_data_model`/`ui_data_bind` as for external RML.
Its handle can be stored in the `ui_state` structure and passed to the component inside
`ui_frame`. `ui_data_events(model)` is processed by the application before the frame;
`data_event` registers a native expression, and the callback name is declared
beforehand through `ui_data_on`. Replacing the handle through `ui_edit` reconnects
the scope.

| Construct | Native binding |
|---|---|
| `data_text(expression)` | RmlUi text interpolation |
| `data_value(path)`, `data_checked(path)` | Two-way value of input/select/textarea and checkbox |
| `data_disabled(expression)` | The disabled attribute |
| `data_attribute(name, expression)` | Element attribute |
| `data_style(name, expression)` | Inline RCSS property |
| `data_class(name, expression)` | Scoped state class, compatible with `with_class` |
| `data_event(kind, expression)` | Native event expression: a callback or an assignment |
| `data_if(name, expression) { ... }` | Native conditional scope |
| `data_for(name, alias, array_path) { ... }` | Native repetition; nesting is allowed |

Inside the scope, `column`, `row`, `box`, `element`, `text`, `button`,
`text_input`, `checkbox`, `select_input`, `text_area`, `attribute` and the regular
typed property helpers are available. `element` lets you describe additional native
tags, for example `option`, `img` or `label`. Text and attribute values are escaped;
`text("name", "...")` remains literal text, including double curly braces.

The macro moves the description into a static function without captures. It serializes
the internal RML **only on mount or when the model is replaced**. There is no file on
disk and no separate annotation. The body is a static schema: names, captions,
properties and expression strings must be constants. Mutable values are read through
`data_*`. Arbitrary script calls, `when`, `each_keyed`, component callbacks and nested
`native_data` inside the schema are rejected at compile time. They can be used
**outside** the scope. Native expressions are parsed by RmlUi during mount, not by the
daScript compiler.
The host also must not inherit `data-model` from an external RML ancestor:
nesting independent native scopes in such a scope is rejected at mount.

The runtime takes into account only the host of the scope. Inside it there is a
separate native model root; its descendants do not take part in reconciliation.
A change of a native field does not cause the component to be recomputed. Reordering
the host through `each_keyed` preserves native input handles, focus/selection and list
aliases. `data_for` places the row bindings deeper than the structural view, so that
shrinking the array removes the row before its former index is evaluated. This is a
native list, not our `each_keyed`.

The names of child elements become scoped classes and part markers, not DOM IDs.
They can be repeated in rows and in different component instances. For access:

```dascript
let scope = ui_find("form")
let captain = ui_data_find(scope, "captain")
let second_row = ui_data_find(scope, "cargo_row", 1)
```

`ui_data_find` excludes hidden `data-for` templates, but can return a hidden
`data_if` element. It returns 0 when the part/occurrence is absent. Directly assigning
`id`, `class`, `style`, `data-model` and the part marker through
`attribute`/`data_attribute` is forbidden: identity is set by the builder, styles by
properties and scoped classes.
Unmount destroys the native subtree and keeps the public model. Closing the model
detaches the bindings; the existing scope remains safe to visit again. A new mount
requires a live model.

## Creation and binding

After `rui_init` or `rui_init_gl`, before loading RML:

```dascript
struct Person { name:string; ready:bool }

let model = ui_data_model("dispatch")
ui_data_bind(model, "person", Person(name="Ada", ready=false), true)
ui_data_bind(model, "status", "Waiting")
ui_data_on(model, "confirm")
let document = ui_load_rml("dispatch.rml")
```

Contents of `dispatch.rml`:

```html
<rml>
  <head><link type="text/rcss" href="dispatch.rcss"/></head>
  <body data-model="dispatch">
    <input data-value="person.name"/>
    <input type="checkbox" data-checked="person.ready"/>
    <p>{{status}}</p>
    <button data-attr-disabled="!person.ready"
            data-event-click="confirm(person.name)">Confirm</button>
  </body>
</rml>
```

In the application loop, after SDL events are passed to `rui_event`:

```dascript
ui_data_events(model) $(event:UiDataEvent) {
    if (event.name == "confirm") {
        ui_data_set(model, "status", "Confirmed by {event.arguments[0].text}")
    }
}
rui_update()
rui_render()
```

`ui_load_rml` uses native `Context::LoadDocument`, keeps the source URL for
relative resources and returns a regular document handle. For strings,
`rui_document` remains. The document supports `close_document`, `show_document`, the
other document operations and the stock native RmlUi views/controllers.

## Values and ownership

`ui_data_bind(model, name, value, writable=false)` deep-copies the value into the
native storage of the bridge. Strings, bool, integers, float/double, enum
(as an integer), structures and arrays of these types are supported. `uint64` is
limited to the int64 range; NaN and infinite float values are rejected. Pointers and
closures are not supported. The daScript GC does not affect the existence of bound
values.

`writable=true` allows native input controllers and RML expressions to change
values. The source daScript structure is not changed by this. To read a native
value use `ui_data_text`, `ui_data_int`, `ui_data_number`, `ui_data_bool`;
for the array length use `ui_data_size`.

```dascript
ui_data_set(model, "person.name", "Grace")
let name = ui_data_text(model, "person.name")
ui_data_set(model, "cargo[0].crates", 12)
ui_data_set(model, "cargo", new_manifest)
```

`ui_data_set` is also available for readonly bindings: the writable flag restricts
native controllers, not the application. A write checks the type before the
replacement and automatically marks the root variable dirty. The nested write
`cargo[0].crates` marks `cargo`. Native `Context::Update` updates the views. Unlike our
`each_keyed`, native `data-for` uses RmlUi's own algorithm.

The structure schema and the value type are preserved after binding. The element type
of an empty array is determined by the first non-empty value and is preserved after
clearing.
`ui_data_dirty(model, "cargo")`, `ui_data_dirty_all` and `ui_data_is_dirty` are
available for explicit invalidation/diagnostics; with a regular `ui_data_set` no extra
dirty is needed. Dirty accepts only the name of a root variable.

## Events

`ui_data_on(model, "confirm")` registers a native `BindEventCallback`. A call from
RML expressions puts the event into the queue of the model; daScript processing is
deferred until `ui_data_events`. Names are registered before the document is loaded.

`UiDataEvent` contains `name` (the callback name), `kind` (for example, `click`),
`target` (an observer handle of the element) and `arguments`. For scalar arguments the
projections `.text`, `.integer`, `.number`, `.boolean` are available, with RmlUi
Variant conversions.
Arguments are copied at the moment of the event; by the time of processing the target
may have been removed, so check `rui_alive(event.target)` before operating on it.

The block and its captures are used only during the `ui_data_events` call and are not
stored in C++. The queue as it was at the start of the call is processed: events
created by the handler remain until the next call. A recursive drain of the same model
is forbidden. On an exception the current event counts as processed and the rest are
kept; the next drain is allowed. A handler may close its own model.
This deferred API is not intended for synchronous cancellation of a native event.

## Context, Debugger and lifetime

- `ui_data_exists(name)` and `ui_data_model_count()` look at the models of the current
  Context.
- `ui_data_debugger()` opens the stock Debugger directly on the Data Models panel;
  a repeated call leaves it open. Structures and arrays are reflected by the native API.
- The hybrid model of the components is also registered in the Context under the
  reserved name `dasrmlui`. The Debugger shows its scalar slots `v0`, `v1`, …, not the
  whole daScript structure. Arbitrary script variables do not get there.
- `ui_data_close(model)` removes the model, the queues and unfinished writes, first
  detaching the native views/controllers. Live documents remain; to connect a new
  model with the same name, the document should be loaded again.
- `ui_data_alive(model)` checks the handle. A repeated close returns false;
  write/read operations with a stale handle raise a script exception.
- `ui_reset` removes the hybrid model and keeps the external ones. `rui_shutdown`
  removes all models before the Context is destroyed. A handle is not reused on restart.

The bridge serves one Context. The API is not a full copy of the C++ constructor:
user-defined synchronous `BindFunc` getters/setters and transform callbacks from
daScript are not exported yet. The built-in RmlUi transforms are available in RML.

## Example and checks

**Harbour / Cargo manifest**: `[ui_component]` + `native_data` and `[ui_style]`,
a cargo array, forms with a nested structure, native expressions, list replacement,
callbacks and an inspector button. The whole example is in `.das`, without external
RML/RCSS.

```powershell
./build/bin/dasrmlui.exe examples/data_models.das
ctest --test-dir build -R '^(native_data.*|data_models|demo_data_models|data_model_type_error)$' --output-on-failure
```

The tests check native bindings and forms, atomic rejection of a write of the wrong
type, arrays after clearing, callbacks/exceptions/GC, model isolation, reflection in
the real Debugger panel, hybrid Context integration, remove and shutdown/restart.
`native_data_dsl` additionally checks scoped styles, escaping, nested lists, the
absence of component updates on a native write, neighboring managed elements,
reordering of keyed scopes with input/focus/selection preserved, model replacement and
unmount/remount. Negative tests check the boundaries of ownership and captures.
The runtime package runs Harbour from the installed folder.
