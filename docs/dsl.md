# Components, state, forms and large lists

All constructs below use daScript syntax and the AST annotations from
`dasrmlui/macros.das`. No separate parser, `.rml` or `.rcss` file is needed.
Working applications: `examples/catalog.das` and `examples/component_lab.das`.

By default `[ui_component]` uses the hybrid runtime with a native DataModel for direct
scalar bindings. Structure, complex expressions and external dependencies keep the
fallback. The root model is created once with `ui_state(initial)`:

```dascript
var initial = Model()
var state = ui_state(initial)
ui_frame(state) $(model:Model) { screen(model) }
ui_edit(state) $(var model:Model) { model.title = "New title" }
ui_read(state) $(model:Model) { print("{model.title}\n") }
```

Here Model is an application struct with a title field, and screen is its component.
`ui_state` is a GC-owned deep copy of initial; after it is created, changes to initial
do not affect the UI. Do not create the state every frame and do not use `inscope`.
The root must not contain borrowed pointers or lambdas. The model borrow is valid only
inside a read/edit/frame block; references must not leave its scope.
`ui_read` is read-only; `ui_frame` allows a mutable borrow for handlers through the macro.

Component events track writes automatically. Direct writes from outside go through
`ui_edit`; unknown mutating helpers invalidate conservatively, and `[ui_action]` gives
exact tracking of their writes. Catalog works through events; Progress Lab uses edit in
its tick. An error in edit does not roll back partial changes; a frame inside edit is
not allowed. Passing a different state to frame resets the old tree.

For plain dependency comparison without a native DataModel, use
`[ui_component(legacy=true)]` and `ui_legacy_frame()` explicitly. [Full main example, lifetime and limitations](hybrid.md).

## Media queries, themes, DPI and ninepatch

The `examples/style_lab.das` example shows two themes, 100/150% scale, native
responsive layout and stretchable frames from one atlas. All switches keep handles and
entered text.

```das
[ui_style]
def app_style() {
    spritesheet("examples/assets/style_atlas.png", 2.) {
        sprite("frame", 0, 0, 96, 96)
        sprite("frame_inner", 24, 24, 48, 48)
    }
    rule(part("panel")) { padding(dp(24)); ninepatch("frame", "frame_inner") }
    theme("night") { rule(part("panel")) { color(rgb(220,235,240)) } }
    theme("paper") { rule(part("panel")) { color(rgb(60,55,45)) } }
    media(media_max_width(dp(900))) {
        rule(part("layout")) { property("flex-direction", "column") }
    }
    media(media_and(media_theme("night"), media_min_resolution(1.5))) {
        rule(part("panel")) { padding(dp(28)) }
    }
}

// After the context is created, for example in a button handler:
set_theme("night")
set_ui_scale(1.5)
```

`media(query) { ... }` writes a native `@media`. Typed query helpers:
`media_min_width`, `media_max_width`, `media_min_height`, `media_max_height` take a
`UiLength` (`px` or `dp`); `media_min_resolution` takes a pixel ratio;
`media_orientation("portrait" | "landscape")` and `media_theme(name)` set the other
conditions. `media_and(a,b)` combines positive conditions; `media_not(query)`
negates the whole query. For the remaining native conditions there is a string form,
for example `media("(min-aspect-ratio: 4/3) and (max-resolution: 2x)")`.

Nested media/theme blocks are not allowed: combine conditions with `media_and`.
Negating a single argument of `media_and` is also rejected, so that the meaning of the
expression does not change when it is serialized into a native `not`. The syntax of a
string query is checked by RmlUi; this is not a separate CSS parser. Only the conditions
and operations that RmlUi supports are available, without CSS `or` and comparisons such
as `width <= ...`.

`theme(name) { ... }` is shorthand for a media query on the active theme of the context.
`set_theme(name)` switches the one selected palette: it deactivates the previous one and
activates the new one; `set_theme("")` clears it. Independent flags such as contrast
are turned on with `activate_theme("contrast", true)` and off with `false`.
Changing the palette does not turn off other independent flags. `ui_theme()` returns
the selected palette; `theme_active(name)` returns whether the native theme is actually
active. Themes are shared by all documents of the context; their names are not scoped.

`dp(value)` creates a typed length. `set_ui_scale(value)` sets a positive finite user
multiplier; `ui_scale()` returns it. The resulting `ui_dp_ratio()` equals
SDL display scale × user scale. On initialization the bridge reads the display scale and
the real pixel size of the window; on a display scale change event it keeps the user
multiplier. `px` stays a physical pixel, while sizes and fonts in `dp` are scaled.
Media queries with lengths in `dp` take the resulting ratio into account; `resolution`
in RmlUi means this same ratio, not the screen resolution in pixels.

Media/theme styles change in native RmlUi without recreating the tree or recomputing
ordinary components. Direct calls to `ui_theme`, `theme_active`, `ui_dp_ratio`,
`ui_scale` inside the annotation subscribe the component to environment changes
automatically; the runtime wakes it and the required ancestors. For a read hidden inside
an ordinary helper function, add `watch_style_environment()` to the component. A
viewport size change still uses the existing `ui_width`/`ui_height` dependencies.
`ui_reset` clears the DSL but keeps the settings of the live context; `rui_shutdown`
resets both the themes and the scale.

`spritesheet(source, resolution) { ... }` sets the native resolution, 1 by default.
`sprite` coordinates are always in pixels of the source image. For a 2x atlas, sprite
sizes and the ninepatch frame at ratio=1 are half the source size. Several sheets
in one style get different names; sheets can be declared inside media blocks.

`ninepatch(outer, inner, paint_area="padding-box")` uses two scoped sprite names from
one atlas: the outer rectangle and the inner stretchable area. Corners keep their
natural size, edges stretch along one axis, the center stretches along both. The form
`ninepatch(outer, inner, dp(12), "border-box")` sets the same thickness for all edges
explicitly. For different thicknesses per side, the native `property("decorator",...)`
remains. The frame size does not add padding automatically: content padding is set
separately.

Tests: `style_environment` covers themes, media, dp, initial and changed DPI, selective
invalidation, focus/state and context restart; `ninepatch_pixels` covers the real pixels
of the four corners and the center on two panels at 1x/2x and on a theme change.
Physically dragging the window between monitors with different DPI is not tested
separately; the ratio change is tested programmatically.

## Animations and deferred removal

`examples/animations.das` is the Orbital menu with a floating ship, a slide-out panel,
notifications and a one-shot launch animation. Transform requires the GL3 renderer.

```das
[ui_style]
def menu_style() {
    keyframes("enter") {
        keyframe(0.) { opacity(0.); property("transform", "translateX(40px)") }
        keyframe(100.) { opacity(1.); property("transform", "translateX(0px)") }
    }
    keyframes("leave") {
        keyframe(0.) { opacity(1.); property("transform", "translateX(0px)") }
        keyframe(100.) { opacity(0.); property("transform", "translateX(40px)") }
    }
    rule(part("inspector")) { opacity(1.); property("transform", "translateX(0px)") }
}

// Inside [ui_component], after use_style(@@menu_style):
animated_when("inspector", model.open,
    motion("enter", 0.3), motion("leave", 0.25)) {
    inspector_content(model)
}
```

`keyframes` are declared outside `rule`, inside `[ui_style]`. Percentages increase from
`0.` to `100.`; both end keys are required. The typed style helpers and `property`
write the properties of a key. Names are scoped: `motion("enter", ...)` uses the
current `use_style`; `animation_name("enter")` returns the full native name.

`motion(name, seconds, easing="cubic-out", iterations=1, alternate=false)` describes an
animation. `iterations=-1` sets an infinite loop. Inside an element:

```das
animate(motion("pulse", 1.2, "sine-in-out", -1, true), 0, model.ambient)

// For a finite animation: a change of revision starts it again.
animate(motion("launch", 0.4), model.launch_revision, model.launching)
on_animation_end() $(name:string) { model.launching=false; model.completed+=1 }
```

These are alternative examples for different elements: one element runs one managed
animation. Do not mix `animate`, `animated_when` and a direct assignment of `animation`
on one node. `enabled=false` stops the animation and restores the base style; enabling
it again starts it from the beginning. This is stop/replay, not pause/resume. The
initial key is applied before the first render; completion or cancellation restores the
values from the stylesheet. So set the base values of animated properties in a `rule`,
not through an inline property/binding on the same element.

RmlUi interpolates properties in `Update`; unchanged components and bindings are not
recomputed every frame. The runtime collects the native `animationend` of all properties
into one `on_animation_end`, delivered through the ordinary queue on the next
`ui_frame`. The argument is the full scoped name. Each run gets a generation: the
completion of an old run is not called after replay/cancel. An infinite or canceled
animation has no completion. `on_transition_end` separately receives the property name
from the native `transitionend`; `transition` is set with an ordinary `property` in the
style.

`animated_when` creates an extra `div` with the given name. With `visible=false` it
keeps the DOM and the child local state until the exit actually finishes, disables
input in the subtree and returns focus to the outer element through `focus_scope`.
Then it performs an ordinary unmount before render. If `visible` becomes true again,
the exit is canceled, the enter starts from the first key, and handles and state are
kept. This is not a smooth reversal from the current interpolated value. The exit must
have exactly one iteration. Removing the parent and `ui_reset` clear the subtree
immediately.

In a keyed list, keep the entry in the model for the duration of the exit and change its
`visible`. Physically removing the entry from the array unmounts the component
immediately: removed list items are not retained automatically yet. Managed keyframes
accept native numbers/lengths/angles, colors, transform, keywords, decorator and filter.
Box-shadow, font-effect and not yet resolved `var(...)`/shorthand placeholders in keys
are rejected, so that the runtime does not wait for a completion that never comes.
Direct bindings for `Element::Animate` and `AddAnimationKey`, several parallel clips on
one node, and a timeline are not added yet.

`tests/animations.das` uses a controlled clock and small native Update steps: RmlUi
limits the interpolation step to 0.1 second. It checks interpolation while components
sleep, completion grouping, a stale event after replay, repeat/infinite, stop,
exit/unmount, focus, state preservation, GC and parent removal.

## Local state and lifecycle

```das
struct Counter { id:int; count:int }

[ui_component]
def counter(id:int) {
    state(Counter(id=id)) $(var local:Counter) {
        on_mount() { local.count = 10; request_focus("increment") }
        on_unmount() { print("Closed {local.id} at {local.count}\n") }
        column() {
            text("count", "{local.count}")
            button("increment", "+ 1") { on_click() { local.count += 1 } }
        }
    }
}
```

`state(initial)` takes a block with an **explicitly typed mutable argument**.
The initializer runs once. The macro creates a separate typed storage
`table<string;array<T>>`; the key includes the component instance path and the
declaration site. The single-element array keeps the address of the value stable when
the table grows. The runtime does not store a pointer to the stack of the calling
function.

In `each_keyed`, reordering keeps the local state. Removal triggers cleanup; if the same
key appears again later, a new state is created. For data that must outlive removal,
store it in the model. `state` and `computed` declarations must be at the component
level, before DOM containers, and unconditional. The same rule applies to the
`on_mount`/`on_unmount` hooks. Inside a condition or a list, call a child component
with its own declaration. For several identical components whose order can change, use
`each_keyed`.

`on_mount` runs once **at the declaration site during the first pass**, before layout
is finished. So you can initialize state in it; for focus, use the deferred
`request_focus`. It is not an "after render" callback. Do not measure DOM elements in
it that are not created yet.

`on_unmount` is called before the DOM is removed, with the last value of the local
state. Child components are cleaned up before their parents; several hooks of one
component run in reverse order. Then the state is freed. `ui_reset()` performs the same
cleanup; a repeated reset calls nothing. You must not create UI or call reset from
teardown.

The cleanup becomes a separate named function that obtains the owned state again.
Global values and the enclosing `state`/`computed` are available in it; borrowed
parameters of the original function and temporary local variables are not captured.
Store the identifier you need in the state, like `local.id` above. Keep in the state
values that really belong to the component, not pointers to temporary arrays.

## Computed, slots and events

```das
[ui_component]
def panel(title:string; changed:block<(delta:int):void>; content:block) {
    column() {
        text("title",title)
        slot(content)
        button("add","Add") { on_click() { emit(changed,1) } }
    }
}

[ui_component]
def screen(var model:Model) {
    computed(expensive(model.amount)) $(total:int) {
        panel("Total: {total}", $(delta:int) { model.amount += delta }) {
            text("caption",model.caption)
        }
    }
}
```

`computed` caches the result by the fields that were read, here `model.amount`. A
change of `model.caption` does not call `expensive`. Owning results are supported,
including arrays; they are freed together with the component. The result type is given
by the block argument. The getter must be pure. For hidden external dependencies, pass
a revision/value explicitly or use `ui_watch` and `ui_touch`.

`slot` calls the content block synchronously; `emit` calls a typed component event.
There is `emit(event)` without a payload and `emit(event,value)` with a payload. None of
these blocks is stored between frames. A component with a callable parameter gets a
conservative pass whenever its parent visits it: comparing the address of a borrowed
closure is not safe. If the parent is skipped, the child slots do not run either.
Inner bindings and computed values keep their own separate dependency checks.

## Fields and validation

```das
text_input("units") {
    bind_int(model.units,0,10000,"Enter") $(value:int) { model.units=value }
}
text("error") { return field_error("units") }

text_input("price") {
    bind_float(model.price,0.0,10000.0,"blur") $(value:float) { model.price=value }
}
text_input("name") {
    bind_edit(model.name,"change",$(value:string):string {
        return length(value) < 3 ? "At least 3 characters" : ""
    }) $(value:string) { model.name=value }
}
checkbox("enabled") {
    bind_checked(model.enabled) $(value:bool) { model.enabled=value }
}
select_input("collection") {
    select_options(choices)
    bind_value(model.collection) $(value:string) { model.collection=value }
}
```

`choices` has the type `array<UiOption>`, for example
`UiOption(value="audio",caption="Audio")`. Captions are escaped as text.
The option list is rebuilt only when its content changes. The model value must match
an existing option. `checkbox` is created with the correct input type from the start;
it does not change the type of an already created text field.

`bind_int`, `bind_float` and `bind_edit` have an input draft. The strings `-`, `12xyz`,
overflow and out-of-range values do not change the model and do not turn into zero. The
draft stays in the field for correction, `field_error` returns the message, and the
element gets the `:invalid` pseudo-class. `bind_float` rejects NaN and infinity when the
bounds are finite. For `bind_edit`, the validator returns an empty string for a valid
value.

The `change` mode applies valid changes immediately; `Enter` waits for Enter; `blur`
waits for focus loss. Escape resets the draft to the model. An external change of the
model value replaces the draft. `field_pending(name[,key])` reports input that is not
applied yet; for example, in Catalog, Save is unavailable until the quantity is
confirmed with Enter. `field_error` and `field_pending` look for the field inside the
current component; outside rendering they search the whole tree. For repeated fields,
pass a key. Field names within a scope must be distinct.

Plain `bind_value` keeps no draft: the setter can reject or normalize the string, and
the next pass restores the model value.
Programmatic updates of checkbox/select suppress events so that they do not create a
model → DOM → model loop. Drafts are removed together with their DOM nodes.

## Virtualization

```das
virtual_each("assets",items,54.0,420.0,$(item:Asset) => item.id) $(item:Asset) {
    asset_row(item)
}
```

Parameters: name, array, row height, viewport height, a function returning a unique
`int` key, and the row block. The optional last argument `overscan` defaults to 2.
Heights are in pixels and must be positive. For now this is a **fixed height**, with no
measurement of variable rows.

The runtime creates a scroll container, a top and a bottom spacer, and only the visible
rows plus a margin. The row wrapper has a fixed height and hides overflow: the content
must fit into it. On scroll, the owner of the list and its ancestors wake up.
When the array shrinks, the scroll offset is clamped to the new length. For a
programmatic jump: `rui_scroll_to(ui_find("assets"),offset)`.

Only the visible slice is copied, so that a setter can safely change the source during
an event. All keys are checked for duplicates: the cost of a list update includes an
**O(N) key check**, while DOM creation/update is O(visible rows). On an idle frame the
list is not traversed if the component is skipped. Passing a huge array as an argument
of the root component still requires a snapshot of that argument. In Catalog the root
receives small query/selection/revision values, and the filter caches the array in
`computed`.

A row that moves beyond the overscan is unmounted. Coming back creates a new component.
Store durable editable row state in the model by key; component local state is meant
for the currently mounted instance.

## Focus and window size

```das
on_mount() { request_focus("name") }
focus_scope("editor") {
    text_input("name") { on_submit() { save() } }
    button("cancel","Cancel") { on_click() { close() } }
}
flow("workspace",900.0) {
    list_panel()
    details_panel()
}
```

`request_focus(name[,key])` is applied after reconciliation and layout. The search is
limited to the component instance that made the request; a call from outside searches
globally. `focus_scope` cycles Tab/Shift+Tab between the visible, enabled elements of
the scope. When a scope that held the focus is removed, it restores the previous
focus if that element is still alive. Nested scopes are restored correctly even when
the whole outer subtree is removed at once.
This is a keyboard focus scope; for a modal window, create a covering backdrop
separately, as in Catalog. Hidden and disabled elements are skipped. Buttons support
keyboard activation through the standard RmlUi behavior.

`on_key("Enter"/"Escape"/"Tab"/"Up"/"Down"/"Space") { ... }` receives a named
key; `on_submit` is shorthand for Enter. The event goes to the nearest subscribed
element. Tab inside a focus_scope is handled by navigation before ordinary delivery.
For other key codes the native SDL loop is available; this helper is not a full
manager of global keyboard shortcuts.

`flow(name,breakpoint)` switches the flex direction between row and column and keeps the
nodes. `ui_width()` and `ui_height()` return the size of the RmlUi context in pixels.
A resize invalidates components, and reading the size inside a binding is counted in its
dependencies. Ordinary `pct`, flex properties and `property` remain available.
`[ui_style]` styles are static; set computed sizes inside the component. A long page
scrolls.

## Diagnostics

`[ui_component(dump=true)]` prints the actual AST of the three generated functions at
compile time. Example: `tests/macros_probe.das`.

```das
ui_trace(true)
ui_frame(state) $(model:Model) { screen(model) }
for (i in range(ui_trace_count())) {
    let entry=ui_trace_at(i)
    print("{entry.owner} / {entry.site}: {entry.reason}\n") // owner: the component chain, "name:number/name:number"
}
```

The trace keeps the last 256 entries: mount, argument/field change, explicit signal,
opaque getter, input event. While tracing is on, named dependency snapshots are stored,
and the reason lists the reads that changed, for example `model.amount` or
`viewport.width`. Field values are not written to the log. `ui_trace(false)` clears
the extra snapshots. `ui_stats()` returns counters for components, bindings and
computed values; `ui_clear_stats()` resets them. An opaque getter is a conservative
fallback, not proof that arbitrary global reads are fully tracked.

RmlUi warnings and errors are printed to the console with the prefix `rmlui warning:` or
`rmlui error:`. This includes typos in `property(...)` and in `[ui_style]` rules.
For a rejected inline property, the next line prints the tag and classes of the element.
The same value is not applied again, so there is one message, not one per pass.
`rui_warning_count()` returns the number of such messages since `rui_init`; in tests it
is useful to check that a correct tree gives zero. The example hosts `run_demo` and
`run_gl_demo` do this themselves: a smoke run in which RmlUi produced at least one
warning ends with an error. This check itself is guarded by the negative test
`smoke_warning_error`.

## Primitive and part names

The annotation recognizes DSL primitives by name, but only in statement position. A
call used as a value (`let h = height(item)`, an argument, an operand) stays ordinary
user code, even if its name matches `height`, `color`, `text` and the like. Qualify
your own function with such a name, when it is called as a statement, with the module:
`_::height(item)`.

A part name can be an expression: `box(model.wide ? "wide" : "narrow") { ... }`.
The element stays the same, its scoped class changes, and `ui_find` sees the new name.
This works for containers and for `text`, `tab_label`, `sprite_image`, `progress_bar`.

`button("name") { ... }` without a caption creates a button whose content is defined
entirely by the body, for example an icon. For a button with a caption, child elements
come after the text and are kept when the caption changes.

## Conditional properties, style order and blocks

A property is applied when execution reaches its call, including under `if` or
`when` on an already existing container. It is not removed when the condition becomes
false: set both branches, or give the value as an expression.

```das
box("panel") {
    if (model.wide) { width(px(300)) } else { width(px(120)) }
    property("border-color", model.error ? "#b3261e" : "#5f6b7a")
}
```

`[ui_style]` sheets go into the shared CSS in order of first use. With equal
specificity, the rule from the sheet used later wins. This matters only for global
selectors (`rule("progress")`, `rule("input")`): `part(...)` classes differ between
sheets and do not conflict with each other.

`box` is a block element (`display: block`) under any parent; `row` and `column` are
flex. To get an inline `box`, set `property("display","inline")`.

`on_key("Enter")` and `on_submit` also fire for Enter on the numeric keypad. Keys that
have no name in `on_key` do not enter the DSL queue and do not wake components.

In GL mode `rui_render` clears the frame itself. `rui_gl_clear(false)` turns the clear
off: the application draws its own scene and the UI is drawn on top of it.

## Base font

For paragraphs with mixed formatting, use `rich_text`, `span`, `strong`,
`emphasis`, `link`, `inline_image`/`inline_sprite`, `line_break`.
[Inline rich text: API, inheritance, baseline and dynamic bindings](rich-text.md).
`rui_default_font_styles()` also loads Bold, Italic and BoldItalic.

```das
verify(rui_font("assets/Inter-Regular.ttf"))
set_base_text("Inter", px(15), rgb(30,34,40))
```

`set_base_text(family, size, color)` sets the default text for all documents: family,
size and color. Size and color are optional and default to `px(16)` and
`rgb(232,237,246)`. Without the call, `LatoLatin` is used: the family of the font that
`rui_default_font()` loads. `base_font_family()` returns the current family.

This call does not load the font file itself: first call `rui_font(path)`, then pass
the family name. If the family is not loaded, RmlUi reports it with a warning. Call
`set_base_text` once at startup: the main document and documents opened later get the
new values, while an already open template document keeps the values it was loaded
with. A `rule("body")` in `[ui_style]` still overrides these values.

The host looks for the `rui_default_font()` file next to the exe
(`assets/LatoLatin-Regular.ttf`); for details see the README, section "Where the
executable looks for scripts and the font". If the file is not found, the function
returns `false`.

## State classes and arbitrary tags

```das
[ui_style]
def card_style() {
    rule(part("card")) { background(rgb(30,40,56)); property("transition","background-color 0.2s") }
    part("card") |> with_class("selected") |> rule() { background(rgb(65,117,183)) }
    part("card") |> with_pseudo("flagged") |> rule() { property("border","2px #d9a441") }
    part("field") |> with_pseudo("focus") |> rule() { property("border-color","#6aa7ff") }
}

// Inside [ui_component], after use_style(@@card_style):
box("card") {
    class_if("selected", model.selected == item.id)
    pseudo_if("flagged", item.flagged)
}
```

`class_if(name, condition)` turns a class of the current container on and off;
`pseudo_if(name, condition)` does the same for a pseudo-class. The condition is an
ordinary binding dependency: it is not evaluated again until the values it read change.
The class gets the prefix of the current style sheet, so select it with
`with_class(selector, name)`, not with the string `.selected`.
`with_pseudo(selector, name)` appends `:name` and also works for the states of RmlUi
itself: `focus`, `active`, `checked`.

The difference from a property matters. An inline property (`background(...)` with an
expression) changes instantly: RmlUi starts a `transition` only when a class or
pseudo-class changes. So express a state that must change smoothly as a class, and
describe both appearances in `[ui_style]`.

For `pseudo_if`, choose your own names: RmlUi sets `hover`, `active`, `focus`, `checked`
and `disabled` itself and will overwrite your value. In `[ui_template]`, `class_if` is
available with a constant condition; `pseudo_if` is rejected there, because the template
is static.

```das
box("avatar") { element("photo","img") { attribute("src","assets/avatar.png") } }
element("name_label","label") { attribute("for","name_field"); text("caption","Name") }
text_input("name") { attribute("id","name_field") }
```

`element(name, tag)` creates an element with any RmlUi tag; the argument order is the
same as for the other primitives: the part name comes first. The body is optional. This
gives access to `img` with `src`, `label`, `form`, `p` and other tags that have no
helper of their own. Native behavior is kept: `img` takes the size of the file, and a
click on a `label` moves focus to the field named in its `for` attribute. RmlUi has no
built-in style sheet, so such an element is inline until a rule sets `display`; inside
`row` and `column` it behaves as a block, like any flex item. The tag of a call site
must not change between passes. `element` and `attribute` also work in `[ui_template]`.

## Typed properties

```das
rule(part("card")) {
    padding(px(12)); margin_x(dp(8)); min_width(px(180)); max_width(pct(60))
    border(px(1), rgb(54,116,84)); border_radius(px(6))
    background(rgb(20,28,40), 0.85)
}
rule(part("badge")) { position("absolute"); top(px(-6)); right(px(-6)); z_index(2) }
```

Each helper only writes one declaration through `property`, so it works wherever
`property` works: in `rule`, `keyframe`, `[ui_template]` and in a component body.
Inside a component, a helper call is a binding with dependencies, like `width`.

| Group | Helpers | Arguments |
|---|---|---|
| Units | `px`, `dp`, `pct`, `em`, `rem`, `vw`, `vh` | number → `UiLength` |
| Sizes | `width`, `height`, `min_width`, `min_height`, `max_width`, `max_height` | `UiLength` |
| Margins | `margin`, `margin_top`, `margin_bottom`, `margin_left`, `margin_right`, `margin_x`, `margin_y` | `UiLength` |
| Padding | `padding`, `padding_top`, `padding_bottom`, `padding_left`, `padding_right`, `padding_x`, `padding_y` | `UiLength` |
| Border | `border`, `border_top`, `border_right`, `border_bottom`, `border_left` | width, color, alpha |
| | `border_width`, `border_radius` | `UiLength` |
| | `border_color` | color, alpha |
| Color | `background`, `color` | color, alpha |
| Position | `position` | `static`, `relative`, `absolute`, `fixed` |
| | `left`, `top`, `right`, `bottom` | `UiLength` |
| | `z_index` | `int` |
| Layout | `display` | a `display` value from RCSS |
| | `gap` | `UiLength` |
| | `flex_grow`, `flex_shrink` | `float` |
| Text | `font_size`, `letter_spacing` | `UiLength` |
| Other | `opacity` | `float` |

Alpha is optional and ranges from 0 to 1, as in the other color functions of the DSL.
`margin_x` and `padding_x` write the left and right sides, `_y` the top and bottom.

What typing gives you. Length and color are different types, so
`border_radius(rgb(1,2,3))` does not compile. `position` and `display` take a string
and check it against the values that RmlUi understands: a typo stops the program with a
clear message on first use of the style sheet, instead of turning into a parser warning.

The `[ui_component]` annotation recognizes the names of these helpers, like those of the
other primitives, by a statement call. Write your own function named `left`, `top`,
`position`, `display`, `margin`, `border` or `gap`, when it is called as a statement
inside a component, with the module: `_::display(text)`. A call used as a value is not
affected.

`transform`, `transition`, `box-shadow`, `font-effect`, `decorator` and `filter` stay
strings: they have compound syntax, and there is no helper for them yet.

## Limits of the current implementation

The DSL covers the listed structural constructs, forms, styles and composition,
but not every RmlUi feature. There is no automatic dependency inference through the
bodies of arbitrary called functions, no variable height for virtual rows, and no
general shortcut manager. Hot reload with migrations is described in
[a separate document](hot-reload.md). For drag-and-drop there are
`draggable`/`on_drop` and the tested example `examples/drag_drop.das`. The SDL_Renderer
backend does not implement the full set of RmlUi renderer extensions; a separate GL3
path is used in `examples/effects.das`.

Current differences between native features, bindings, the DSL and the examples:
[RmlUi coverage matrix](rmlui-coverage.md).

## Native documents and templates

`[ui_template]` describes a native template with ordinary daScript calls. Hand-written
RML/RCSS strings are not needed. Styles are set through `[ui_style]` or the usual
`width`, `padding`, `property` inside a template node.

```das
[ui_style]
def frame_style() {
    rule(root()) {
        property("position", "absolute")
        width(px(430))
        height(px(390))
    }
    rule(part("move")) { height(px(42)); padding(px(12)) }
    rule(part("mission_actions")) { padding(px(12)) }
    rule(part("field_notes")) { padding(px(22)) }
    rule(part("crew_status")) { padding(px(12)) }
    rule(part("resize")) {
        property("position", "absolute")
        property("right", "2px"); property("bottom", "2px")
        width(px(28)); height(px(28))
    }
}

[ui_template]
def tool_window() {
    use_style(@@frame_style)
    window_frame("window") {
        move_handle("move") { title_slot("title") }
        slot("mission_actions")
        slot("field_notes")
        slot("crew_status")
        resize_handle("resize")
    }
}
```

A template function takes no parameters; the static description is cached.
`open_template(@@tool_window, title, float2(x,y))` creates a separate document,
sets its position and fills `title_slot` with safe text. Closing the document
and dynamic content stay in `[ui_component]`:

```das
state(WindowLife()) $(var local:WindowLife) {
    on_mount() { local.document = open_template(@@tool_window, "Inspector", float2(50.,210.)) }
    on_unmount() { rui_close_document(local.document) }
    document_content(local.document, "mission_actions") { actions(model) }
    document_content(local.document, "field_notes") { notes_editor(model) }
    document_content(local.document, "crew_status") { crew_status(model) }
}
```

`slot(name)` takes a name chosen by the application: `mission_actions`, `field_notes`
and `crew_status` are examples, not built-in slot types. The name can be computed with
ordinary daScript code while the static definition is built. A slot becomes an empty
`div` with a document-local ID and a scoped style class; style it through `part(name)`
or `slot(name) { padding(...); property(...); attribute(...); }`.

There is no main slot: every slot is named. The native `<template>` is generated
without the `content` attribute; the DSL itself routes each component into its declared
slot.

DSL rules:

- Exactly one `window_frame` is required. There can be zero, one or many named slots;
  filling each of them is optional. An unfilled slot stays an empty element.
- `title_slot` is optional; at most one is allowed.
- `move_handle`/`resize_handle` generate a native `<handle>` with the target `#document`.
- `row`, `column`, `box`, `text` inside the annotation describe the static frame.
  Their names become document-local IDs and scoped style classes. Names must not
  repeat within one template; the same names in different instances are allowed.
- Slot names are non-empty and do not repeat the names of other template nodes. Choose
  names that are valid as IDs and CSS classes, for example `quest_details`; `#` is not
  allowed.
- `slot`, `title_slot` and `resize_handle` have forms with a style block.
  A `slot` block may contain properties and attributes, not child elements;
  put application content into `document_content` inside `[ui_component]`.
- Text and `attribute` values are escaped during serialization. `attribute("id",...)`,
  `class`, `style`, `template`, `data-rui-slot` and `data-rui-template` are reserved:
  use the node name and `property`.
- State, `when`, keyed lists, bindings and handlers belong to components.
  The annotation reports these constructs in a static template. `return` inside
  the description is not supported; computations can be moved into ordinary helper
  functions.

The macro redirects container calls to a builder and wraps the description in a cache.
The builder creates the native `<template>`, an RCSS resource and the root document
parameters; `open_template` registers the resources in memory and attaches the native
template through `<link type="text/template">`. RmlUi parses the result with its
standard parser. There is no separate DSL parser. `template_markup(@@tool_window)`
returns the generated native template for inspection; the RCSS is linked from a separate
in-memory resource. The call preserves the current style scope of the calling component.

`ui_reset` clears the builder cache, and `open_template` registers the resources again
for a new context. Definitions are static: this is not hot reload, and changing global
values inside a template is not a way to update an already loaded native cache.
For changing data, use components.

`document_content(document, name)` routes node creation into a declared slot.
A typo in the name, or an attempt to fill an ordinary static node instead of a slot,
raises an error that names the target. A slot is not a component and holds no state
itself: the inserted components use ordinary bindings, `state`, `when` and `each_keyed`.
If a condition removes the `document_content` call, the child components are unmounted
and the empty slot container stays in the frame. Other slots and documents do not
change.

The template owns the frame and the target; the runtime owns the inserted children. The
document ID and the slot handle are part of the identity of the inserted nodes. Changing `name` on the
same call unmounts the old subtree and creates a new one in the other slot; local state
is not carried over. On an ordinary content update of the same slot, handles and local
state are kept. DSL stylesheets are applied to documents together with the template's
own styles; more specific template rules can override the common base.
Do not remove the target manually while the component is mounted. Close the document
in `on_unmount`; handles into a closed document become invalid.

`examples/templates.das` shows `[ui_template]` without RML strings, two instances,
three named slots with separate components, conditional removal of the editor,
native `move_target`/`size_target`, editing, and close/reopen.
The model survives closing the window; local state is created anew.

The low-level `rui_resource` and `rui_document` are kept for existing RML templates
and for integrations that need to load markup directly. RmlUi lays out a document
during loading, and DSL styles are attached after it, so such markup must set
`font-family` itself: otherwise the first layout runs without a font and RmlUi reports
"No font face defined". Templates from `[ui_template]` carry the base font in their own
CSS. For documents created directly through `rui_document`, `document_content` still
accepts any existing ID: the slot declaration check applies to documents from
`open_template`. The existing `slot(block)` for component composition remains a separate
overload.

## Text translation

```das
rui_translation("en", "hello", "Hello")
rui_translation("de", "hello", "Hallo")
// In a component:
text("greeting", tr("hello"))
// In a handler or before ui_frame:
set_locale("de")
```

`tr` calls the installed `SystemInterface::TranslateString`. The native parser
also translates `[hello]` when RML is loaded. For a missing translation the
English catalog is used; an unknown key stays `[key]`. Token replacement is single-pass.
Catalogs and strings are copied into native storage; script callbacks are not stored.

A language or catalog change increments a revision. Components see the revision in
their input snapshot, and direct `tr(...)`/`ui_locale()` calls in bindings get a
dependency on it. So the text updates without a remount and without changing input
handles. If a helper hides the `tr` call, pass `ui_locale()` explicitly as a helper
argument, as in `sample_phrase` in `examples/localization.das`. There is no automatic interprocedural
analysis.

Already parsed native RML text is not translated again automatically: for a live
language switch, use `tr` in the DSL. `tr` in `text` creates ordinary safe text; it
does not interpret the translation as RML. The native RML parser itself can parse
markup from a trusted catalog, following RmlUi behavior.

`examples/localization.das` shows plural rules and `%name%` substitution in daScript
for en/de/ru; this is not ICU. `rui_font` loads the main face, `rui_fallback_font` loads
a fallback face. The example does not cover HarfBuzz/RTL or CJK scenarios.

## Drag-and-drop and progress

`draggable(payload)` enables native `drag: clone`; `on_drop() $(payload:string)` on the
nearest subscribed element receives a copy of the payload. The handler changes the
model, and keyed reconciliation then updates the DOM. The original native pointer is not
stored. The clone has `:drag`, the drop target has `:drop`. The handler is responsible
for validating the payload and any constraints; a drop outside a target does not change
the model. The full set of drag lifecycle callbacks is available through
`on_event("dragstart"/"dragend"/"dragdrop", ...)`; `event.source` is a safe handle of
the source if the native event contains `drag_element`. Auto-scroll of drop zones is not
implemented separately.

`progress_bar(name,value,maximum,direction)` creates a real `<progress>`.
`fill-image` takes a sprite name; `clockwise` turns on radial fill.
For an arbitrary curve, `examples/progress_lab.das` measures the length of the path
segments and updates their opacity, with a fractional last segment. Speed follows path
length, not the horizontal coordinate. This is DSL composition, not a new native
progress type.

## Element and document events

`on_event` works inside `[ui_component]` on the current element, with any native
event name (including custom events). The macro adds a unique site; the runtime
creates a native listener, keeps it cached while the component is skipped, and removes
it on unmount or when the subscription disappears. Several subscriptions of one type
are allowed. The specialized `on_click`, `on_key`, `bind_value` and `on_drop` work
separately and do not get duplicates from these listeners.

```dascript
column("panel") {
    on_event("click", UiEventOptions(use_capture=true)) $(event:UiEvent) {
        print("target={event.target}, current={event.handle}, phase={event.phase}\n")
    }
    button("action", "Run") {
        on_event("click") $(event:UiEvent) { run_command() }
    }
}
document_events(editor_document) {
    on_event("keydown", UiEventOptions(key="S", modifiers=1, stop=true)) $(event:UiEvent) {
        save_draft()
    }
    on_event("hide") $(event:UiEvent) { print("Editor hidden\n") }
}
```

`UiEvent` is a copy that owns its data; native Event/Element pointers and daScript
closures are not stored. To save an event together with its parameter table, use
`saved := event`.

| Field | Meaning |
|---|---|
| `handle`, `target` | currentTarget and the original target; weak handles are checked with `rui_alive` |
| `kind`, `value` | The native name and the string value of the `value` parameter |
| `phase` | 1 capture, 2 target, 4 bubble |
| `key_code`, `key` | The full native KeyIdentifier; convenient names A–Z, 0–9, F1–F24, Enter, Escape, Tab, Space, arrows, Home/End/PageUp/PageDown/Insert/Delete/Backspace. For other keys the name is empty and the code is kept |
| `modifiers` | Ctrl=1, Shift=2, Alt=4, Meta=8, CapsLock=16, NumLock=32, ScrollLock=64; helpers `event_ctrl/shift/alt/meta` |
| `mouse`, `screen`, `button`, `wheel` | Native mouse_x/y (projected for the current element), the original context coordinates in pixels, button 0=left/1=right/2=middle or -1, native wheel_delta_x/y |
| `interruptible` | Whether RmlUi allows this event to be stopped |
| `source` | Handle of the native drag_element, or 0 |
| `parameters` | A table of parameter copies: scalar, string, vector and color in string form; `event_parameter(event,"text")`, `event_parameter(event,"reason")` and so on. Native pointer/resource parameters are not exported |

`UiEventOptions`: `use_capture`, `stop`, `stop_immediate`, `key`, `modifiers`,
`enabled`. An empty key does not filter by key. Modifiers=-1 accepts any combination;
0–15 requires that exact combination of Ctrl/Shift/Alt/Meta and ignores lock keys.
`enabled=false` removes the listener. Changing subscription parameters invalidates old
queued snapshots; while type and phase are unchanged, the order of listeners on one node
is kept.

Handler delivery is deferred until `ui_frame`, in native dispatch order. Reconciliation
runs after each handler; the following commands check the subscription, target,
disabled state, visibility and modal focus again. So a removed target, a closed window
or the background of a new modal do not receive input commands that were already queued.
When an event is delivered, parent listeners do not replace `target` with their own
`handle`.

**Stopping is applied synchronously, from the subscription parameters**, before the
native default action. In RmlUi, StopPropagation also cancels default actions; there is
no independent PreventDefault in this version. `stop` leaves the other listeners of the
same node running; `stop_immediate` stops them too. Non-interruptible events (for
example change) ignore this. A deferred block cannot cancel a native event after the
fact. A focus change in such a block also happens at `ui_frame`, after the native input
has already been processed. The existing `focus_scope` handles Tab/Shift+Tab on its own.

Subscribe after the document is created: a `load` that has already happened is not
replayed. After `close_document`, snapshots of removed handles are dropped; to release
resources, use `on_unmount`, not a deferred `unload`. `show`/`hide` keep native
semantics: the event fires on every matching call, even if the visibility is already in
that state. Custom events from external native code are available through the same API.
These are RmlUi events, not a new browser-style PointerEvent/TouchEvent system.

## Document modes, popups and editors

```dascript
// Usually in on_mount; on_unmount must call close_document(document).
let document = open_template(@@editor_window, "Notes", float2(40.,250.),
    UiDocumentOptions(visible=false))

show_document(document, UiDocumentOptions(focus=UiDocumentFocus.Keep))
hide_document(document)       // DOM, handles and local state are kept
bring_to_front(document)
send_to_back(document)
position_document(document, float2(100.,200.))

show_document(dialog, UiDocumentOptions(modal=UiModal.Modal))
show_popup(menu, float2(300.,180.))
```

`UiDocumentOptions` has `visible=true`, `modal=UiModal.None`,
`focus=UiDocumentFocus.Auto`, `scroll=true`. `UiModal.Keep` keeps the previous modal
flag. Focus None does not change focus; Document focuses the document; Keep returns
focus to its last child recipient; Auto looks for `autofocus` and otherwise focuses the
document. These are native modes: a modal blocks the background while the document holds
the focus. The combination Modal+Focus.None does not take focus by itself.

`open_template(..., visible=false)` creates a hidden document without an intermediate
Show and without stealing focus. Keep calling `document_content` for a hidden editor:
visibility is not an unmount. If you remove its component through `when`, the state
is destroyed by the ordinary DSL rules. `hide_document`/`close_document` return
focus to the saved recipient if the focus was inside the document being hidden and
the recipient is still alive, visible and enabled. `document_visible`/`document_modal`
are state queries; they do not create a separate reactive subscription.

Front/back change the order within one native z-index group. An explicit z-index is
needed if a full-screen main document must not cover auxiliary windows when it
receives focus. Managing several SDL windows/contexts is out of scope here.

`show_popup` shows a document with modal focus and Auto, brings it to the front and
clamps its position to the viewport bounds; after a resize the position is recomputed.
The popup size is set by the template: an oversized window is not shrunk automatically.
A popup can be opened on top of a modal; after it closes, focus returns to the modal.
The topmost popup closes on Escape and on an outside press, and it swallows the matching
mouse-up so that the click does not activate the background.
`document_events(menu)` + `on_event("dismiss")` receives `reason="escape"` or
`"outside"`. An ordinary `hide_document` does not generate dismiss.

For a menu, use `attribute("autofocus","")` on the initial item, native Enter/Tab,
and `on_event("keydown", UiEventOptions(key="Down",stop=true))` with
`focus_next(menu)`; for Up, use `focus_next(menu,true)`. The callback does not outlive
the frame. A real example is `examples/event_studio.das`: a context menu, Ctrl+S, a log,
a movable editor with a local draft, hide/show and a modal confirmation.
`tests/events.das` and `tests/documents.das` check native input, lifetime and queues.

## Native spatial navigation

The DSL uses the standard RCSS `nav`, `nav-up/right/down/left` and `tab-index`. RmlUi
itself performs the neighbor search, the `:focus-visible` switch, scrolling and
Enter/Space during native keyboard handling. `on_event("keydown", stop=true)` handlers
can still cancel this default action.

```dascript
[ui_style]
def navigation_style() {
    rule(part("tile")) { nav(UiNav.Auto) }
    rule(part("tile")+":focus-visible") { background(rgb(90,110,65)) }
}

[ui_component]
def panel() {
    use_style(@@navigation_style)
    document_nav(rui_root())
    row() {
        button("tile", "First") {
            nav_id("first")
            nav_right(nav_to("last"))
        }
        button("tile", "Last") { nav_id("last"); nav_left(nav_to("first")) }
    }
    box("custom_control") { tab_stop(); nav(UiNav.Vertical); text("caption","Focusable") }
}
```

| Helper/mode | Native behavior |
|---|---|
| `nav()` / `nav(UiNav.Auto)` | Geometric search in all four directions |
| `UiNav.None` | No automatic move |
| `UiNav.Horizontal` / `UiNav.Vertical` | Search only along the given axis |
| `UiNav.TreeOrder` | The next/previous tabbable element in DOM order, without wrapping around to the root |
| `nav_up/right/down/left(mode)` | Mode for a single direction |
| `nav_up/right/down/left(nav_to("id"))` | Explicit move to an ID in the current document |
| `nav_id("id")` | Set a real native ID on the current element |
| `tab_stop(true/false)` | `tab-index: auto/none` for an ordinary element |
| `document_nav(document, mode=UiNav.Auto)` | Navigation when the focus is on the document itself |

The style helpers work both in `[ui_template]` and directly in a component.
`nav_id`/`nav_to` take a non-empty ID without `#` or whitespace; the `#` prefix
is added when the property is generated. The names are document-local: they do not
become scoped classes and are not resolved through the global `ui_find`. For repeated
components, set unique IDs, for example `nav_id("item_{item.id}")`.
The same IDs in different documents are allowed. An explicit target must exist and
be focusable; the DSL does not create it and does not replace the native validation
rules.

Nav properties are not inherited. Usually `nav` is set for each kind of button through
`[ui_style]`, and for the document through `document_nav` or `nav()` inside
`window_frame`. Without `autofocus`/`request_focus` the initial focus can be on the
document; its native `nav:auto` lets you move to the first/last tabbable element.

`Auto` is limited to the nearest scroll container and skips hidden or non-focusable
elements. `TreeOrder` can move between scroll containers.
`focus_scope` still limits **Tab/Shift+Tab**, not all arrow moves;
for a native geometric scope, set `overflow: auto` on the container.
Explicit ID moves can cross such scopes within a document. They do not move
into another document; a native modal/popup stays a separate focus scope.
Text fields keep native cursor handling; `nav(UiNav.None)` stops them from being a
source of automatic arrow moves, but not of Tab.

`nav*` and `tab_stop` take part in the ordinary generation of mount/update code and of
the dependencies of individual bindings. Moving the focus does not require recomputing
components; if you need model changes, subscribe to `on_event("focus")`.
`tests/navigation.das` checks modes, IDs, disabled/hidden, scroll, Tab scope,
the text cursor, popups, activation and the absence of extra updates. SDL gamepad
glue is not part of this native API.

## Built-in RmlUi Debugger

The official `RmlUi::Debugger` is included; its DOM inspector, Event Log, Outlines and
Data Models work in the current RmlUi context. The interface and the built-in font
belong to the plugin; the DSL has no inspector implementation of its own.

```dascript
// Usually in the application's on_mount. The plugin loads on first enable.
debugger_hotkey()           // F8; key name in SDL format
debugger_hotkey("F9")       // change the key
debugger_hotkey("")         // disable the hotkey

debugger_init()             // optional early initialization
debugger_show()             // show the panel; initializes automatically
debugger_toggle()
debugger_show(false)
debugger_shutdown()         // release the plugin and disable the hotkey
```

By default the plugin is not loaded and no hotkey is assigned. Registering the key
does not require a repeated call from render. Press and release are intercepted before
the application queue; autorepeat does not toggle the panel repeatedly. The hotkey also
works when the focus is in the native tool documents and in a popup.

`debugger_ready()` and `debugger_visible()` can be read in a component: the macro
subscribes it to Debugger state changes automatically. Unrelated components are not
invalidated. This is the state of the toolbar, not a check of a particular Element Info
or Event Log window.

Upstream `SetVisible(false)` hides only the toolbar. `debugger_show(false)`
also closes the tool windows, turns off Outlines and stops picking. On the next show
the toolbar appears; the tool you need is opened with its button.
If the focus was in a Debugger window, it returns to the live, enabled element that was
saved at show time. A click on the Debugger over a popup does not count as an outside
click that closes the popup. The first picking click is intercepted by the native
inspector; a repeated click on the already selected element may pass through to the
application, following RmlUi rules.

Debugger documents are not part of component reconciliation and do not receive DSL
stylesheets. `ui_reset` removes application nodes but does not turn off a separately
started plugin; for a component-owned lifetime, call `debugger_shutdown()` in
`on_unmount`. On `rui_shutdown`, RmlUi itself releases the plugin. Initialization is
idempotent; an explicit restart and the creation of a new context after a full shutdown
are tested.

Data Models shows **native RmlUi data models**, including the scalar slots of the
`dasrmlui` hybrid model and the named fields of
[public models for external RML](data-models.md).
`ui_data_debugger()` opens this panel directly. A public model can also be used
inside `[ui_component]` through `native_data(name, model)` with `data_*` bindings,
without external RML; see
[syntax and the ownership boundary](data-models.md#inside-ui_component-without-external-rml).
Arbitrary daScript variables and the full structure of component state are not shown.
For the DSL, `ui_stats` and `ui_trace` remain. Another context cannot be selected yet:
the bridge serves one context.

Example: `examples/navigation_lab.das` (Vector deck). Arrows/Enter control the tiles
and the popup; F8 opens the standard Debugger. Element Info lets you pick an element and
see its native ID, scoped classes, RCSS and geometry. `tests/debugger.das` checks
picking, the absence of extra callbacks, removal of the selected element, style
isolation, focus return, hide/shutdown, GC and re-initialization.

## SVG and Lottie

The official RmlUi plugins are included in the build. The elements work in
`[ui_component]` and in a static `[ui_template]`; styles are set through `[ui_style]` or
the parent container. These are the native `<svg>` and `<lottie>` elements; the DSL has
no player of its own.

```das
[ui_style]
def vector_style() {
    rule(part("icon")) { width(px(160)); height(px(120)); image_color(rgb(255,255,255)) }
    rule(part("motion")) { width(px(240)); height(px(240)) }
    rule(part("seal")) { width(px(80)); height(px(60)); svg_decorator("examples/assets/vector_orbit.svg",true) }
}
[ui_component]
def vector_view(var model:Model) {
    use_style(@@vector_style)
    svg_image("icon",model.svg_path,model.crop)
    svg_inline("badge",model.svg_fragment,float2(100.,100.))
    lottie("motion",model.animation_path)
    box("seal") {}
}
```

- `svg_image(name, source, crop=false)` loads an SVG through the RmlUi FileInterface.
  `crop=true` sets `crop-to-content`: transparent margins are removed during
  rasterization; the intrinsic size of the SVG itself stays the original one.
- `svg_inline(name, fragment, viewport:float2, crop=false)` takes SVG XML
  **without the outer `<svg>`**. The DSL sets the namespace, width/height and
  `viewBox="0 0 w h"`. The sizes must be finite and positive. SVG paths inside the
  fragment are not RmlUi DOM elements and do not receive separate UI events. You can
  build the fragment with a daScript function; the API does not introduce a separate
  parser or drawing language.
- `lottie(name, source)` loads Lottie JSON. In the current plugin, playback is
  automatic, looped and driven by RmlUi time; there is no pause/seek/speed API.
  `when` removes and recreates the element; a remount and a source change start a new
  animation. Hiding the element does not pause it.
- `svg_decorator(source, crop=false, paint_area="padding-box")` sets a native
  SVG decorator. `padding-box`, `border-box` and `content-box` are allowed. Use `/` in
  paths; quotes and line breaks are not allowed. The decorator is stretched over the
  element area.
- `image_color(rgb(...))` and `opacity(...)` modulate the SVG/Lottie image.
  To change proportions or sizes, use ordinary RCSS width/height. The native plugin
  accounts for DPI; when the size changes it creates a texture of a suitable resolution.

Source, fragment, viewport and crop are tracked **at the binding level**. An unchanged
component is not recomputed for Lottie frames; the host keeps calling
`rui_update`/`rui_render`. When the content of a file is replaced at the same path, the
native cache is not required to read it again: this is not hot reload. Use a new
resource path. `rui_resource(path, data)` lets you register SVG/JSON in memory and pass
its path to the same functions. Relative paths are resolved relative to the document.

The build downloads pinned LunaSVG 3.2.1 (with PlutoVG) and rlottie; see
[dependencies](vector-dependencies.md). The supported SVG/Lottie subset is defined by
these libraries; an arbitrary After Effects export is not guaranteed to work.
The `examples/vector_lab.das` example uses GL3; functional tests run with the SDL
dummy driver, while SVG and animation pixel tests run with a real SDL renderer.

## Custom native elements

`register_native_element` registers a real `Rml::ElementInstancer`. A native
subclass of `Rml::Element` calls the daScript handler from its virtual methods,
and `native_element` creates it through the Factory in a component or a template.
Registration is done **after `rui_init`/`rui_init_gl` and before elements are created**.

```das
def meter(event:UiNativeEvent) {
    if (event.kind==UiNativeKind.Paint) {
        native_rect(event.element,float4(0.,0.,event.size.x,event.size.y),rgb(30,50,40))
        native_line(event.element,float2(10.,10.),event.size-float2(10.,10.),3.,rgb(240,190,70))
    }
}
// At startup, after RmlUi is initialized:
// register_native_element("app-meter",@@meter,float2(200.,80.))

[ui_component]
def meter_view(var model:Model) {
    native_element("meter","app-meter") {
        width(px(300)); height(px(100))
        attribute("value","{model.value}")
        on_click() { model.value+=1 }
    }
}
```

Signature: `register_native_element(tag, handler, intrinsic=float2(0.), continuous=false)`.
The handler is an ordinary function `@@name` or an owning lambda
`@(event:UiNativeEvent) { ... }`. The name must start with a lowercase Latin letter,
contain a hyphen and consist of `a-z`, `0-9`, `-`. Built-in types and a repeated
registration of the same name are rejected. A failed registration does not replace the
previous handler. A unique registration ID is returned.

`UiNativeEvent` contains `element:uint64`, `kind:UiNativeKind`, `name:string`,
`size:float2` (the content box in pixels) and `time:double` (RmlUi time).

| Kind | When it is called |
|---|---|
| `Create` | Once after the handle is obtained, before the Factory sets attributes and before attachment to a document; the size can be zero |
| `Attribute` | For each changed attribute; `name` is its name, the value is read with `rui_get_attr`/`rui_has_attr` |
| `Property` | For each changed computed property; `name` is the RCSS property name; take the current sizes for drawing in Paint |
| `Resize` | Native `OnResize`, after the content box changes |
| `Update` | Native `OnUpdate`, only with `continuous=true`; can be called several times per frame and for a hidden element |
| `Paint` | In native `OnRender`, when geometry must be built or updated |
| `Destroy` | Once when the native object is destroyed; the handle is already invalid and is used only as a key for cleanup |

`native_rect`, `native_triangle`, `native_line` take a handle, geometry,
a `UiColor` and an optional `alpha=1`. Coordinates are local to the content box,
in physical pixels. Solid geometry is copied into a native mesh and compiled
through `RenderManager`. The saved native clipping/transform/layer states are applied
when drawing; transform/filter capabilities depend on the renderer (GL3).
RCSS opacity is applied to the vertex colors of each primitive: overlapping
translucent primitives are blended one after another; this is not a separate opacity
layer. The primitives are implemented entirely in daScript on top of `native_mesh`;
there are no separate C++ bindings for rect/triangle/line. Custom shader commands, hit
testing and baseline overrides are not exported yet.

### Mesh, UV and textures

`UiNativeMesh` is an ordinary daScript struct with three arrays:

- `vertices:array<float4>`: `(x,y,u,v)`, coordinates relative to the content box in
  pixels, UV normalized to the whole texture;
- `colors:array<uint4>`: one **non-premultiplied** RGBA 0..255 per vertex;
- `indices:array<int>`: zero-based indices, each triple defines a triangle.

```das
var mesh:UiNativeMesh
let a=mesh_vertex(mesh,float2(0.,0.),rgb(255,120,80),float2(0.,0.))
let b=mesh_vertex(mesh,float2(200.,0.),rgb(80,230,210),float2(1.,0.))
let c=mesh_vertex(mesh,float2(100.,120.),rgb(180,120,255),float2(0.5,1.))
mesh_triangle(mesh,a,b,c)
native_mesh(event.element,mesh) // No texture, colors are interpolated.
// native_mesh(event.element,mesh,texture) — the same vertices with a texture.
```

`mesh_vertex(mesh,position,ink,uv=float2(0.),alpha=1.)` returns the index of the added
vertex. `mesh_triangle(mesh,a,b,c)` adds indices; vertices can be reused.
`mesh_quad(mesh,bounds,ink,uv=float4(0.,0.,1.,1.),alpha=1.)` adds a quad.
`bounds` holds `(x,y,width,height)`; `uv` holds **`(u0,v0,u1,v1)`**, not width/height.
The arrays can be filled directly. Their data is copied into C++ synchronously by
`native_mesh(element,mesh,texture=0ul)`; after the call the source arrays can be
changed, freed and collected by the GC. A zero texture means solid geometry.

One Paint can submit several meshes with different textures. The call order is
preserved; adjacent submissions with the same texture are merged, including solid
geometry. RCSS opacity modulates vertex alpha; premultiplication of vertex RGBA and
generated texture RGBA is done in C++. On frames without invalidation the geometry is
not rebuilt. All positions/UVs must be finite, the lengths of vertices and colors must
match, and the number of indices must be a multiple of three and refer to existing
vertices. The limit for one Paint is 1,000,000 submitted vertices and 3,000,000 indices.
An invalid mesh is rejected as a whole before any batch changes. An empty mesh is
allowed; the call still requires Paint.

Textures belong to a **specific element instance**:

```das
// Initialize once in Paint, then store the handles in state keyed by element.
let atlas=native_texture_load(event.element,"examples/assets/native_mesh_atlas.png")
verify(atlas!=0ul)
var pixels=array<uint4>(uint4(255u,100u,40u,255u),uint4(40u,200u,255u,128u))
let generated=native_texture_rgba(event.element,int2(2,1),pixels)
verify(generated!=0ul)
// The left half of the atlas. native_image is also a daScript wrapper over mesh.
native_image(event.element,atlas,float4(0.,0.,64.,64.),float4(0.,0.,0.5,1.))
```

- `native_texture_load(element,source):uint64` loads a PNG through RenderManager;
  a relative path is resolved relative to the native document. A load failure gives 0,
  and RmlUi may log a warning. Do not call load again on every Paint.
- `native_texture_rgba(element,size:int2,pixels:array<uint4>):uint64` creates a texture
  from row-major RGBA, row 0 at the top. Channels are 0..255, alpha is not
  premultiplied. Each side is 1..4096, and the array length must be exactly
  width*height. Invalid arguments raise an error; a creation failure in the renderer
  gives 0. The pixels are copied; the RmlUi callback owns the C++ copy and keeps no
  pointers into the daScript heap.
- `native_texture_size(element,texture):int2` returns the size, or `(0,0)` for a
  stale or foreign handle.
- `native_texture_release(element,texture):bool` removes the handle; a repeated call
  returns false. Already cached geometry keeps the resource until the next Paint
  or until the element is destroyed. Release by itself does not invalidate geometry.
- `native_texture_resources():int` is the number of live resource wrappers, for
  diagnostics, including those held by batches. It is not the number of GPU allocations:
  file textures are additionally cached by RmlUi until its texture cache is released or
  it shuts down. Generated textures are released together with the last element/batch
  reference.

Creating textures requires an element that is already attached to the context; Create
is called too early. Use lazy initialization in Paint or ordinary code after mount.
On Destroy all remaining resources are released automatically; the element handle
is already invalid in this callback. Handles are monotonic and are not reused on remount
or shutdown/restart. Passing a foreign or released texture to a mesh raises an error.
To replace an image, create a new handle, release the old one and call invalidate.

For now the sampler is set by the backend: GL3 uses repeat/linear, SDL uses its standard
sampling. For atlases, leave padding/inset if the edges of neighboring cells must not
blend. Per-texture sampler/filter/wrap settings are not exported yet.
The `examples/mesh_lab.das` example shows a UV ribbon, a ring progress indicator, a
vertex gradient, PNG sprites, tint/alpha, caching and remount/GC. The
`native_mesh_pixels` test checks the same APIs on SDL and GL3, including the lifecycle
after a Paint error.

Paint is normally not called every frame. Attributes, native style changes, sizes
and DPI mark the geometry as stale; `native_invalidate(element)` does this explicitly.
For animation, register with `continuous=true`, update your state in Update
and call invalidate. The component itself stays cached. Changing a daScript table
alone is not enough for a native repaint without invalidate.

`intrinsic` sets the size in dp and the aspect ratio; positive sizes make the element a
replaced element. `(0,0)` keeps ordinary container layout. The intrinsic size can be
changed with `native_set_intrinsic(element,size)` from Create/Attribute/Update or from
ordinary code. This is not allowed during Paint/Destroy. The sizes must be finite and
positive. RCSS width/height override the intrinsic size. Attributes in the DSL are
tracked by separate bindings.

Handlers are synchronous and run on the UI thread. From a native hook you may read
properties/attributes, change your own daScript state, call native invalidate/size and
draw in Paint. DOM/context mutations and a re-entrant update/render/shutdown are not
allowed: do them in ordinary `on_event`/`on_click` handlers or in the main loop. This
prevents an element from being removed during its own native traversal. Drawing is
allowed only in the Paint of the current element. `Create`/`Destroy` should not be used
as a replacement for the component `on_mount`/`on_unmount`: the native lifetime also
covers elements from RML/templates.

The lambda registry is kept in a global daScript table that the GC sees; C++ stores
only a static dispatcher and its Context. Captured owning values and state tables
survive GC. Do not capture pointers to stack variables whose scope has already ended.
For per-instance state, use a table keyed by `event.element`; create the entry in
Create and remove it in Destroy (see `examples/native_lab.das`).

`ui_reset` removes component elements and keeps registrations. Closing a document
also releases its static native elements. `unregister_native_element(tag)`
returns false while live instances exist; on success it releases the handler/captures.
`rui_shutdown` first destroys the elements, then removes the GC roots of the handlers.
The host shuts down the native context before the script Context is destroyed; after a
new init the types must be registered again. IDs are not reused.
Shut down RmlUi before the SDL renderer or GL context is destroyed. The host guard
protects the lifetime of the script Context, but it does not replace this order of
releasing graphics resources.

A callback exception is caught at the C++ boundary. The element stops receiving
ordinary callbacks, but Destroy is still called for cleanup and must allow for a
partially completed Create. The diagnostic is returned
after `ui_frame`, `ui_reset`, `rui_render` or a script `rui_shutdown`, once the native
traversal has finished. When working through raw APIs, call `rui_native_check()` after
the operation; `rui_native_error()` lets you read the deferred diagnostic.
An unhandled terminal script exception ends the host without re-entering
the damaged script Context; arbitrary user cleanup is not guaranteed in such an
abnormal exit.

For diagnostics there are `native_registered`, `native_instance_count`,
`native_handler_count` and `rui_is_native`. Example: `examples/native_lab.das`; tests:
`native_elements.das`, `native_safety.das`, `native_host_lifetime.das` and
`native_render.das` with a pixel checker.
The native contract is checked against [RmlUi custom elements](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/custom_elements.html)
and the headers of the local revision in use.

## Custom decorators

`register_decorator` registers an `Rml::DecoratorInstancer` that creates ordinary
native `Decorator` objects. They decorate existing `box`, `button`, `input` and other
elements: no separate native element is needed for this. Registration is done after
RmlUi is initialized, **before styles are first computed**.

```das
def draw_frame(event:UiDecoratorEvent) {
    if (event.kind!=UiDecoratorKind.Paint) { return }
    let ink=decorator_color(event.canvas,"ink")
    let edge=decorator_length(event.canvas,"edge",event.size.x)
    native_rect(event.canvas,float4(0.,0.,edge,event.size.y),ink.ink,ink.alpha)
}
// At startup, after rui_init / rui_init_gl:
// register_decorator("app-frame",array<UiDecoratorParam>(
//     decorator_color_param("ink",rgb(70,120,100)),
//     decorator_length_param("edge",dp(4))),@@draw_frame)

[ui_style]
def frame_style() {
    rule(part("card")) {
        custom_decorator("app-frame",array<UiDecoratorArg>(
            decorator_arg("edge",dp(8)),decorator_arg("ink",rgb(160,90,60))))
    }
    rule(hover(part("card"))) {
        custom_decorator("app-frame",array<UiDecoratorArg>(decorator_arg("edge",pct(8))))
    }
}
```

Signature: `register_decorator(name,parameters,handler):uint64`. The handler is an
owning lambda `@(event:UiDecoratorEvent) { ... }` or a function `@@name`. Type names
consist of lowercase Latin letters, digits and hyphens, start with a letter and contain
a hyphen. Built-in types and duplicates are not replaced. Parameter names are unique and
follow the same rules, except that the hyphen is not required; the maximum is 32
parameters, and the name `decorator` is reserved. An empty schema is allowed.

| Parameter declaration | Getter in the callback | Native parser |
|---|---|---|
| `decorator_number_param(name,value:float)` | `decorator_number(canvas,name):float` | `number` |
| `decorator_length_param(name,value:UiLength)` | `decorator_length(canvas,name,percentage_base=0.):float` | `length_percent` |
| `decorator_color_param(name,value:UiColor,alpha=1.)` | `decorator_color(canvas,name):UiDecoratorColor` | `color` |
| `decorator_string_param(name,value:string)` | `decorator_string(canvas,name):string` | `string` |

`UiDecoratorColor` contains `ink:UiColor` and `alpha:float` in the range 0..1.
The length getter returns physical pixels: dp accounts for DPI, em for the element font,
and percentages are resolved against the explicitly passed `percentage_base`. For
example, for a corner bevel you can pass `min(event.size.x,event.size.y)`.
An unknown parameter, a wrong getter or a stale canvas raises an error.

`custom_decorator(name,args,paint_area="padding-box")` takes named
`decorator_arg(name,value)` arguments; there are overloads for float/int, UiLength,
UiColor/alpha and string. The order of named arguments does not matter; omitted ones are
taken from the schema. `custom_decorator(name)` applies all defaults. RCSS values are
checked by the standard RmlUi parsers and serialized into a canonical declaration, for
example `app-frame(rgb(160,90,60), 8dp) padding-box`. Name errors, duplicates and
invalid values are detected before the style changes. String values must not contain
quotes, backslashes, line breaks, `;` or braces.

The helper works in `[ui_style]`, in static templates and directly in
`[ui_component]`, where it becomes a separate reactive binding. The ordinary
RCSS cascade applies, including hover, classes, media and themes. Like `svg_decorator`,
the helper sets the whole `decorator` property; a repeated call replaces the previous
value. Several decorators in a native RCSS list (`a(), b()`) are supported by the
runtime; each application gets its own canvas, even on one element.

`UiDecoratorEvent` contains:

- `canvas:uint64` — the unique data of **one application** of the decorator. Pass it
  to `native_mesh`, `native_rect/triangle/line/image`, the texture API and
  `native_invalidate`;
- `element:uint64` — an ordinary DOM handle for reading attributes/properties. It is
  not a canvas;
- `kind:UiDecoratorKind` — Create, Paint or Destroy;
- `size:float2` — the size of the selected area in physical pixels;
- `dpi:float` — the current density-independent pixel ratio;
- `paint_area:string` — `border-box`, `padding-box` or `content-box`.

Drawing coordinates start at the top-left corner of the **selected paint area**; the
runtime applies its offset. The area does not automatically clip an arbitrary mesh to
the border-radius: for a shaped frame, build the matching geometry.
Native clipping/transform/layer states apply; capabilities depend on the renderer.
Opacity is applied to each submission, as for native elements.

Create corresponds to `GenerateElementData`, Destroy to `ReleaseElementData`.
RmlUi can recreate the data on resize, DPI change, opacity change, or a change of
parameters or the cascade, **without removing the DOM element itself**. In that case
the new Create sometimes arrives before the old Destroy. Keep state in a table keyed by
`event.canvas`, not only by element.
Paint is called for a new or invalidated canvas; later frames use the cached mesh
without entering daScript. When external state changes, call
`native_invalidate(canvas)`. A change of an arbitrary DOM attribute is not by itself a
dependency of the decorator: pass the reactive value as a parameter or invalidate the
canvas explicitly.

Textures are available in Create/Paint, because the decorated element is already
attached to the context. All canvas resources are released automatically after Destroy.
During Destroy the canvas is already invalid; it serves as the key for removing state,
and the element may be in the process of destruction. A Create/Paint error disables
Paint for that canvas but does not cancel Destroy. Errors are caught at the C++ boundary
and reported through the same `rui_native_check`/`rui_native_error` as for native
elements. DOM mutations and update/render/shutdown inside callbacks are not allowed.

The owning lambda stays in the GC-root table until unregister/shutdown. C++ keeps no
pointers into the script heap; meshes and pixels are copied. The bindings preserve the
real call position and stack frame, so that a GC inside Paint/Destroy correctly walks
the local values of the suspended calling daScript code.

`decorator_registered`, `decorator_instance_count` (live canvases) and
`decorator_handler_count` are available for diagnostics. `unregister_decorator(name)`
returns false while the type is used by canvases **or by cached native Decorator
definitions**. So a stylesheet can hold the type even after the elements are removed.
An unused type can be unregistered and registered again; the old C++ instancer
stays inactive until shutdown, because parsed RCSS holds raw pointers to it and to its
property definitions. On a successful unregister the lambda is released immediately.
A repeated registration does not rebind the already parsed RCSS of an old stylesheet:
for the new type, recreate the corresponding styles/documents.
`ui_reset` keeps registrations; `rui_shutdown` removes them after the native teardown.
As for native elements, shutdown must come before the SDL/GL renderer is released.

Example: `examples/decorator_lab.das` (Decorator Studio). `decorator_pixels` checks
SDL/GL3, parameters/defaults, hover, paint area, texture, opacity, DPI/resize, clipping,
cache, several decorators on one element, captured values/GC, stale handles and errors.
`decorator_host_lifetime` checks a late Destroy before the script Context is released.


## Custom GL3 filters and shaders

Registration is done after `rui_init_gl` and before styles are computed. The GLSL code
lives in an ordinary daScript string; the built-in `%_esc~ ... %_esc` lets you avoid
escaping braces. No separate DSL parser or shader file is needed.

```das
register_shader("app-stripes",%_esc~
vec4 effect(vec2 uv) {
    float stripe = step(0.5, fract(uv.x * u_size.x / p_pitch + u_time * p_speed));
    return vec4(p_tint.rgb * mix(0.2, 1.0, stripe), p_tint.a);
}
%_esc,array<UiEffectParam>(
    effect_length_param("pitch",dp(20)),
    effect_number_param("speed",0.2),
    effect_color_param("tint",rgb(80,200,240))))

register_filter("app-desaturate",%_esc~
vec4 effect(vec2 uv) {
    vec4 c = sample_source(uv);
    float luma = dot(c.rgb,vec3(0.2126,0.7152,0.0722));
    return vec4(mix(c.rgb,vec3(luma),p_amount),c.a);
}
%_esc,array<UiEffectParam>(effect_number_param("amount",0.5)))

[ui_style]
def material_style() {
    rule(part("surface")) {
        width(px(320)); height(px(180));
        custom_shader("app-stripes",array<UiEffectArg>(effect_arg("pitch",pct(10))))
    }
    rule(part("glass")) { custom_backdrop_filter("app-desaturate") }
}

[ui_component]
def material(amount:float) {
    use_style(@@material_style)
    box("surface") {
        custom_filter("app-desaturate",array<UiEffectArg>(effect_arg("amount",amount)))
        text("caption","The filter processes children too")
    }
}
```

`register_shader(name, source, params)` creates a native DecoratorInstancer that
draws the element background through a CompiledShader.
`register_filter(name, source, params, overflow=0.)` creates a native FilterInstancer:
it processes the element layer together with its descendants, or the backdrop.
`overflow` is an extra drawing area in `dp` around the element, for example for a blur
or an offset; for a backdrop it does not extend its area. There are registration
overloads without the parameter array.

`UiEffectParam`/`UiEffectArg` use the same schema format as the parameters of
script decorators. `effect_number_param`, `effect_length_param`,
`effect_color_param` and `effect_arg` overloads for float/int, UiLength and UiColor
with alpha are supported. String parameters are not supported for the GPU. Effect names
contain a hyphen; parameter names consist of lowercase Latin letters, digits and
hyphens; the first character is a letter. The schema is immutable: up to 32 parameters,
source up to 1 MiB. Defaults and values go through the native RCSS parser; unknown and
repeated arguments are rejected.

`custom_shader(name, args, paint_area="padding-box")` also supports
`border-box` and `content-box`. The geometry respects RmlUi rounded corners, opacity
and transforms. `custom_filter` writes `filter`, `custom_backdrop_filter` writes
`backdrop-filter`. Several calls for the same property replace its value.
For sequential passes, use:

```das
custom_filters(array<UiFilterEffect>(
    filter_effect("app-desaturate",array<UiEffectArg>(effect_arg("amount",0.8))),
    filter_effect("app-other"))) // app-other must be registered
```

`custom_backdrop_filters` takes the same kind of array. The order of the items is the
order of the passes. An empty array removes the filter (`none`). Native built-in and
custom filters can be mixed through an ordinary
`property("filter", "app-desaturate(0.5) blur(2px)")`.
All helpers are available in `[ui_style]`, `[ui_template]` and `[ui_component]`. In a
component, a parameter change updates only the corresponding property binding.

### GLSL contract

You define `vec4 effect(vec2 uv)`; `#version 330`, the uniforms and `main`
are added by the runtime. You can define your own GLSL helper functions.
The function returns **straight RGBA** in the range 0..1; the wrapper clamps and
premultiplies it for RmlUi native blending. RGB does not need to be multiplied by alpha
in advance.

| Name | Meaning |
|---|---|
| `uv` | Local coordinates 0..1, origin at the top left |
| `u_time` | RmlUi SystemInterface time, float in seconds; updated on draw |
| `u_size` | Shader: size of the paint area in px. Filter: size of the current clipped postprocess area, including overflow |
| `u_texel` | `1 / u_size`, convenient for neighboring samples |
| `p_<name>` | Number and length are float; color is vec4 straight RGBA 0..1. Hyphens in the name are replaced with `_` |
| `sample_source(uv)` | Filter only: straight RGBA of the source layer, transparent black outside the current area |

Length/dp values are resolved to pixels; percentages are resolved against the **width**
of the paint area for a shader, or of the element border box for a filter. The filter
`u_size` can differ from the element size because of clipping, overflow and the
viewport. Sampling is limited to the current area, so that leftover pixels of another
layer are not read from a reused framebuffer.
`u_time` does not create a daScript dependency: GPU animation runs without component
updates as long as the application keeps calling render.

### Lifetime and limitations

Sources and schemas are copied; GLSL is compiled and linked once at registration.
A compiler error raises a daScript exception with the GL diagnostic; partial
resources are released, and the name can be registered again. A parameter change
recreates the native instance with new uniforms but reuses the GL program.
There are no separate daScript callbacks during render; a GC collection does not affect
GPU resources.

`gpu_effects_available()` checks the GL3 capability. `gpu_effect_counts()` returns
`int2(programs, compiled_instances)` for diagnostics. `shader_registered` and
`filter_registered` check a type; `unregister_shader`/`unregister_filter` return
false while native definitions (including the RCSS cache) or compiled instances exist.
Removing an element releases its instances; the RCSS cache can hold definitions
until the corresponding stylesheet/document caches are reset. Retired instancers are
kept until shutdown, because parsed RCSS may contain pointers to them. On shutdown,
native instances/definitions are released before the registry and the GL context.

This is a GL3 fragment API with a ready-made vertex stage and one pass per filter.
Arbitrary vertex/compute shaders, additional texture samplers, mutable framebuffer
handles and user uniforms outside the registered schema are not exported yet.
For several passes, use a chain. SDL_Renderer gives an explicit registration error;
there is no automatic fallback. GLSL is executed by the driver and is meant
for trusted application code.

`examples/shader_lab.das` shows a procedural Aurora, a chromatic filter and a frosted
backdrop, a slider, a tint change, a static phase, remount and GC. `gpu_effect_pixels`
checks colors, alpha, pass order, backdrop, a built-in filter after a custom one,
transform/clipping, overflow, DPI, time without binding updates, a template, GC, and
shutdown/restart with live instances. `gpu_backend` checks the rejection on the SDL
renderer.

## Shaders in daScript: dasGlsl

`require dasrmlui/shaders` brings in `[ui_shader]` and `[ui_filter]`. They pass the
typed AST of functions to the existing `dasGlsl` generator from daScript.
There is no separate parser; functions, helpers, arithmetic, branches, loops and local
structs are compiled to GLSL 330. The AST is compiled when the script is loaded;
the GL program is compiled and linked at registration. These stages are not repeated
every frame.

```das
require dasrmlui/shaders

[ui_shader]
def stripes(uv,size:float2; time:float; pitch,speed:float; tint:float4):float4 {
    let stripe=step(0.5,fract(uv.x*size.x/pitch+time*speed))
    return float4(tint.xyz*lerp(0.2,1.,stripe),tint.w)
}

[ui_filter]
def desaturate(uv:float2; amount:float):float4 {
    let c=sample_source(uv)
    let luma=dot(c.xyz,float3(0.2126,0.7152,0.0722))
    return float4(lerp(c.xyz,float3(luma),amount),c.w)
}

// After rui_init_gl, before styles are applied:
register_shader("app-stripes",stripes_shader(),array<UiEffectParam>(
    effect_length_param("pitch",dp(20)),
    effect_number_param("speed",0.2),
    effect_color_param("tint",rgb(80,200,240))))
register_filter("app-desaturate",desaturate_filter(),array<UiEffectParam>(
    effect_number_param("amount",0.5)))
```

The annotation generates a descriptor factory `<name>_shader()` or `<name>_filter()`.
It returns a `UiShaderProgram`: the generated source, the parameter signature and the
effect type. The source can be inspected through `.source`; it is one string constant
per function. Overloads of `register_shader`/`register_filter` take this descriptor
instead of a GLSL string. The string overloads keep working.

The signature of the entry function defines the uniforms:

| Argument | daScript type | Meaning |
|---|---|---|
| `uv` | `float2` | Local UV, origin at the top left |
| `time` | `float` | GPU uniform `u_time` |
| `size` | `float2` | GPU uniform `u_size` |
| `texel` | `float2` | GPU uniform `u_texel` |
| Any other | `float` | A named RCSS parameter with the number or length/percent parser |
| Any other | `float4` | A named RCSS color, straight RGBA 0..1 |

Built-in arguments can be omitted and reordered; they are not part of the RCSS schema.
For example, `[ui_shader] def pulse(time:float):float4` needs no parameter array.
All other arguments must be present in the schema exactly once, including those
not used in the body. The schema order does not have to match the argument order.
`edge_width` in daScript corresponds to the RCSS name `edge-width`. Number and length
remain different RCSS parsers, although both are passed to the function as float.
A kind mismatch, a missing, duplicated or extra parameter, or a wrong parser
raises an exception before the native registry entry and the GL program are created.

The arguments of the entry function are read-only; to modify a value, create a
local variable. Default values are set in the schema, not in the function arguments.
The return type is `float4`, straight RGBA. The final clamp, premultiply, opacity,
clipping and transforms are done by the existing GL3/RmlUi glue.

`sample_source(uv)` is available in `[ui_filter]`, including calls from helpers. It
returns straight RGBA of the source layer; outside the current postprocess area it
returns transparent black. The adapter uses the same coordinate conversion and
framebuffer bounds protection as the string API. In `[ui_shader]` such sampling is not
allowed, because there is no source layer.

Styles and reactive bindings stay the usual ones:

```das
[ui_style]
def material_style() {
    rule(part("surface")) {
        width(px(320)); height(px(180)); custom_shader("app-stripes")
    }
}
[ui_component]
def material(amount:float) {
    use_style(@@material_style)
    box("surface") {
        custom_filter("app-desaturate",array<UiEffectArg>(effect_arg("amount",amount)))
        text("caption","daScript on the GPU")
    }
}
```

This is a shader subset of daScript. Mutable CPU globals, dynamic arrays, strings and
CPU-only operations do not become GPU data automatically. Mutable globals,
unsuitable arguments or result, and source sampling in a shader are rejected when the
script is compiled; other unsupported constructs are reported by dasGlsl or the GL
compiler. Numeric constants and helper functions from imported modules are supported.
Entry names cannot be overloaded; the names `main` and `dasrmlui_entry` are reserved,
and annotation options are not provided yet. These functions are meant to run
on the GPU: do not call filter functions as CPU functions to read the screen.

The standalone host loads `glsl` from `daScript/modules/dasGlsl/glsl`; the runtime
package installs this folder together with daslib. The adapter does not need dasOpenGL,
SPIR-V, shadercross or an additional native renderer. The daScript dependency is not
modified.

The full example is `examples/shader_lab_effects.das` and `examples/shader_lab.das`:
Aurora, Prism and Glass are written entirely in daScript. The `shader_dsl_compiler` test
checks generation, signatures and helpers; eight negative tests check the diagnostics.
`gpu_effect_pixels` runs the original GLSL and dasGlsl against the same pixel oracles,
including alpha, chain/backdrop, DPI, time, GC, remount and shutdown/restart.
`runtime_package` runs Shader Lab from the installed standalone folder.

## Hot reload

LiveHost, named root/local state, `ui_migrate` and `[ui_style(name="...")]` for the styles entry: [hot-reload.md](hot-reload.md).
