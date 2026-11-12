options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

// One scenario per defect found in review. Each of them used to pass silently
// or fail far from its cause, so the checks look at the real DOM and layout.

enum Mode {
    idle
    busy
}
struct Item { h:float = 24. }
struct Model {
    caption:string = "one"
    wide:bool
    mode:Mode = Mode.idle
    origin:float2 = float2(1.,2.)
    item:Item = Item()
    typo:bool
    flag:bool
    clicks, unrelated, submits:int
}
var mode_reads, origin_reads : int

// Shares its name with a style helper. Used as a value it is ordinary user code.
def height(item:Item):float { return item.h }

[ui_style]
def regression_style() {
    rule(part("narrow")) { width(px(40)) }
    rule(part("wide")) { width(px(120)) }
}

// Ten sheets with the same global selector. The one used last must win,
// whichever order that is: the probe is run once in each direction. Ten is
// deliberate: a daScript table keeps insertion order only up to eight keys.
[ui_style]
def order_0() { rule("progress") { width(px(10)); height(px(10)) } }
[ui_style]
def order_1() { rule("progress") { width(px(20)); height(px(10)) } }
[ui_style]
def order_2() { rule("progress") { width(px(30)); height(px(10)) } }
[ui_style]
def order_3() { rule("progress") { width(px(40)); height(px(10)) } }
[ui_style]
def order_4() { rule("progress") { width(px(50)); height(px(10)) } }
[ui_style]
def order_5() { rule("progress") { width(px(60)); height(px(10)) } }
[ui_style]
def order_6() { rule("progress") { width(px(70)); height(px(10)) } }
[ui_style]
def order_7() { rule("progress") { width(px(80)); height(px(10)) } }
[ui_style]
def order_8() { rule("progress") { width(px(90)); height(px(10)) } }
[ui_style]
def order_9() { rule("progress") { width(px(100)); height(px(10)) } }

[ui_component]
def order_probe(reverse:bool) {
    if (reverse) { use_style(@@order_9); use_style(@@order_8); use_style(@@order_7); use_style(@@order_6); use_style(@@order_5); use_style(@@order_4); use_style(@@order_3); use_style(@@order_2); use_style(@@order_1); use_style(@@order_0) }
    else { use_style(@@order_0); use_style(@@order_1); use_style(@@order_2); use_style(@@order_3); use_style(@@order_4); use_style(@@order_5); use_style(@@order_6); use_style(@@order_7); use_style(@@order_8); use_style(@@order_9) }
    column("order") { progress_bar("gauge",0.5) }
}

def check_order(window:SDL_Window?; renderer:SDL_Renderer?; reverse:bool) {
    verify(rui_init(window,renderer,640,480))
    verify(rui_default_font())
    ui_frame() { order_probe(reverse) }
    verify(rui_bounds(ui_find("gauge")).z == (reverse ? 10. : 100.),"Sheets must cascade in the order they were first used")
    ui_reset()
    rui_shutdown()
}

// Enum and vector arguments are compared by value like any other input.
[ui_component]
def mode_badge(mode:Mode; origin:float2) {
    row("badge") {
        text("mode") { mode_reads += 1; return "{mode}" }
        text("origin") { origin_reads += 1; return "{origin}" }
    }
}

// A frame with static text and a title, both measured while the document loads.
[ui_template]
def regression_window() {
    window_frame("window") {
        move_handle("move") { title_slot("title") }
        text("note","Static text of the frame")
        slot("content")
    }
}

[ui_component]
def screen(var model:Model) {
    use_style(@@regression_style)
    column("screen") {
        let row_height = height(model.item)
        button("action",model.caption) {
            text("icon","*")
            on_click() { model.clicks += 1 }
        }
        button("bare") {
            text("glyph","+")
            on_click() { model.clicks += 10 }
        }
        box(model.wide ? "wide" : "narrow") { height(px(row_height)) }
        text(model.wide ? "label_wide" : "label_narrow","label")
        mode_badge(model.mode,model.origin)
        box("checked") { property(model.typo ? "widht" : "width","10px") }
        // Constant values under a condition, on a container that already exists.
        box("by_if") { if (model.flag) { property("width","77px") } else { property("width","33px") } }
        box("by_when") { when(model.flag) { height(px(21)) } }
        // The inner box has a block parent rather than a flex one.
        box("block_outer") { box("block_inner") { width(px(100)); height(px(20)) } }
        text_input("field") { on_submit() { model.submits += 1 } }
    }
}

[export]
def main(smoke:bool):int {
    var model = Model()
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let window : SDL_Window? = with_window("regression tests",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer : SDL_Renderer? = window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480))
        verify(rui_default_font())
        ui_frame() { screen(model) }
        verify(rui_warning_count() == 0ul,"A valid tree must not produce RmlUi warnings")

        // A caption change keeps the button's own children.
        let action = ui_find("action")
        let icon = ui_find("icon")
        verify(find(rui_inner_markup(action),"one") == 0 && rui_child_count(action) == 2)
        model.caption = "two"
        ui_frame() { screen(model) }
        verify(rui_alive(icon) && ui_find("icon") == icon,"Caption change destroyed a child element")
        verify(find(rui_inner_markup(action),"two") == 0 && rui_child_count(action) == 2)
        rui_test_click(action)
        ui_frame() { screen(model) }
        verify(model.clicks == 1)

        // A button without a caption holds only what its body creates.
        let bare = ui_find("bare")
        verify(rui_child_count(bare) == 1 && rui_child(bare,0) == ui_find("glyph"))
        rui_test_click(bare)
        ui_frame() { screen(model) }
        verify(model.clicks == 11)

        // A computed part name restyles the same element, containers and leaves alike.
        let sized = ui_find("narrow")
        let leaf = ui_find("label_narrow")
        verify(sized != 0ul && leaf != 0ul && rui_bounds(sized).z == 40.)
        verify(rui_bounds(sized).w == 24.,"A value call named like a style helper must stay user code")
        model.wide = true
        ui_frame() { screen(model) }
        verify(ui_find("wide") == sized && ui_find("narrow") == 0ul,"Part name was not updated")
        verify(rui_bounds(sized).z == 120.,"Part class was not updated")
        verify(ui_find("label_wide") == leaf && ui_find("label_narrow") == 0ul)
        verify(rui_alive(sized) && rui_alive(leaf))

        // Enum and vector inputs skip and update by value.
        verify(mode_reads == 1 && origin_reads == 1)
        model.unrelated += 1
        ui_frame() { screen(model) }
        verify(mode_reads == 1 && origin_reads == 1)
        model.mode = Mode.busy
        ui_frame() { screen(model) }
        verify(mode_reads == 2 && origin_reads == 1 && rui_inner_markup(ui_find("mode")) == "busy")
        model.origin = float2(5.,2.)
        ui_frame() { screen(model) }
        verify(mode_reads == 2 && origin_reads == 2 && find(rui_inner_markup(ui_find("origin")),"5") == 0)

        // The base text is a setting, not a constant. A larger size makes the
        // same text taller; the defaults bring it back.
        let text_height = rui_bounds(leaf).w
        set_base_text("LatoLatin",px(20))
        ui_frame() { screen(model) }
        verify(base_font_family() == "LatoLatin" && rui_bounds(leaf).w > text_height,"set_base_text did not restyle the tree")
        set_base_text("LatoLatin")
        ui_frame() { screen(model) }
        verify(rui_bounds(leaf).w == text_height && rui_warning_count() == 0ul)

        // RmlUi lays a native template out while loading it, before the DSL
        // stylesheet is attached. Its own sheet must already name a font.
        let frame = open_template(@@regression_window,"Window",float2(20.,20.))
        verify(frame != 0ul && rui_warning_count() == 0ul,"A template must load with a font")
        ui_frame() { screen(model) }
        verify(rui_warning_count() == 0ul)
        rui_close_document(frame)
        ui_frame() { screen(model) }

        // A constant property under a condition is applied when its branch is reached.
        let by_if = ui_find("by_if")
        let by_when = ui_find("by_when")
        verify(rui_local_property(by_if,"width") == "33px" && rui_local_property(by_when,"height") == "")
        model.flag = true
        ui_frame() { screen(model) }
        verify(rui_local_property(by_if,"width") == "77px","A constant property under if was not applied")
        verify(rui_local_property(by_when,"height") == "21px","A constant property under when was not applied")
        model.flag = false
        ui_frame() { screen(model) }
        verify(rui_local_property(by_if,"width") == "33px","The other branch was not applied again")

        // A box is a block wherever it stands, so it keeps its own size.
        let inner = rui_bounds(ui_find("block_inner"))
        verify(inner.z == 100. && inner.w == 20.,"box must be a block outside flex containers")

        // Keypad Enter submits like Enter. A key nobody listens for wakes nothing.
        rui_focus(ui_find("field"))
        rui_test_shortcut("Keypad Enter",0)
        ui_frame() { screen(model) }
        verify(model.submits == 1,"Keypad Enter must submit")
        ui_frame() { screen(model) }
        ui_clear_stats()
        rui_test_shortcut("A",0)
        ui_frame() { screen(model) }
        verify(ui_stats().dispatches == 0,"An unmapped key must not be dispatched")

        // A rejected declaration is reported once, not on every pass.
        verify(rui_warning_count() == 0ul)
        model.typo = true
        ui_frame() { screen(model) }
        let reported = rui_warning_count()
        verify(reported > 0ul,"A mistyped property must be reported")
        model.unrelated += 1
        ui_frame() { screen(model) }
        verify(rui_warning_count() == reported)

        ui_reset()
        rui_shutdown()

        // Each direction gets a fresh context, so both orders are really built.
        check_order(window,renderer,false)
        check_order(window,renderer,true)
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    print("regressions: ok\n")
    return 0
}
