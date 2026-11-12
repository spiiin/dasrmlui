options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

// The typed style helpers: every one maps to the declaration it is named after,
// RmlUi accepts all of them, and they behave like the older helpers in rules,
// keyframes, templates and dependency-tracked component code.

struct Model { offset:float = 4.; unrelated:int }
var offset_reads : int
def offset_of(value:float) : UiLength { offset_reads += 1; return px(value) }

[ui_style]
def helper_style() {
    rule(part("strip")) { gap(px(12)) }
    rule(part("sized")) { min_width(px(150)); height(px(80)); max_height(px(30)); margin_left(px(25)) }
    rule(part("stage")) { position("relative"); height(px(100)) }
    rule(part("pinned")) { position("absolute"); left(px(40)); top(px(10)); width(px(20)); height(px(20)); z_index(3) }
    rule(part("framed")) { border(px(2),rgb(10,20,30)); border_radius(px(4)); padding_left(px(7)); width(px(50)); height(px(10)) }
    rule(part("relative_units")) { width(em(2)); height(vh(10)) }
    rule(part("hidden")) { display("none") }
    keyframes("slide") {
        keyframe(0.) { left(px(0)) }
        keyframe(100.) { left(px(10)) }
    }
}

[ui_component]
def screen(var model:Model) {
    use_style(@@helper_style)
    column("screen") {
        row("strip") {
            box("first") { width(px(10)); height(px(10)) }
            box("second") { width(px(10)); height(px(10)) }
        }
        row("sized_row") { box("sized") {} }
        box("stage") { box("pinned") {} }
        box("framed") {}
        box("relative_units") {}
        box("hidden") {}
        box("dynamic") { margin_left(offset_of(model.offset)) }
        box("inline") {
            margin_x(px(3)); margin_y(px(4))
            padding_right(px(5)); padding_top(px(6)); padding_bottom(px(7)); padding_left(px(8))
            border_top(px(1),rgb(1,2,3)); border_right(px(2),rgb(1,2,3),0.5)
            border_bottom(px(3),rgb(4,5,6)); border_left(px(4),rgb(7,8,9))
            letter_spacing(px(2)); flex_grow(2.); flex_shrink(0.)
            background(rgb(1,2,3),0.5); color(rgb(4,5,6),0.25)
            min_height(px(11)); max_width(px(300)); right(px(1)); bottom(px(2)); z_index(3)
            border_radius(px(4)); gap(px(9)); min_width(rem(1)); max_height(vw(50))
        }
        box("recolored") { border(px(1),rgb(1,1,1)); border_width(px(6)); border_color(rgb(9,8,7)) }
        box("spaced") { margin(px(13)) }
    }
}

[ui_template]
def helper_frame() {
    window_frame("window") {
        box("panel") { border_radius(px(4)); margin_x(px(3)) }
        slot("content")
    }
}

def has(handle:uint64; name,value:string) {
    let actual = rui_local_property(handle,name)
    if (actual != value) { panic("{name}: expected '{value}', got '{actual}'") }
}

[export]
def main(smoke:bool):int {
    var model = Model()
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let window : SDL_Window? = with_window("style helper tests",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer : SDL_Renderer? = window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480))
        verify(rui_default_font())
        ui_frame() { screen(model) }
        verify(rui_warning_count() == 0ul,"RmlUi must accept every declaration the helpers write")

        // Each helper writes the declaration it is named after.
        let direct = ui_find("inline")
        has(direct,"margin-left","3px"); has(direct,"margin-right","3px")
        has(direct,"margin-top","4px"); has(direct,"margin-bottom","4px")
        has(direct,"padding-right","5px"); has(direct,"padding-top","6px")
        has(direct,"padding-bottom","7px"); has(direct,"padding-left","8px")
        has(direct,"border-top-width","1px"); has(direct,"border-top-color","#010203")
        has(direct,"border-right-width","2px"); has(direct,"border-right-color","#0102037f")
        has(direct,"border-bottom-width","3px"); has(direct,"border-bottom-color","#040506")
        has(direct,"border-left-width","4px"); has(direct,"border-left-color","#070809")
        has(direct,"letter-spacing","2px"); has(direct,"flex-grow","2"); has(direct,"flex-shrink","0")
        has(direct,"background-color","#0102037f"); has(direct,"color","#0405063f")
        has(direct,"min-height","11px"); has(direct,"max-width","300px")
        has(direct,"right","1px"); has(direct,"bottom","2px"); has(direct,"z-index","3")
        has(direct,"border-top-left-radius","4px"); has(direct,"border-bottom-right-radius","4px")
        has(direct,"row-gap","9px"); has(direct,"column-gap","9px")
        has(direct,"min-width","1rem"); has(direct,"max-height","50vw")
        let recolored = ui_find("recolored")
        has(recolored,"border-left-width","6px"); has(recolored,"border-bottom-color","#090807")
        let spaced = ui_find("spaced")
        has(spaced,"margin-top","13px"); has(spaced,"margin-right","13px")

        // The same helpers inside rules, measured through the layout they produce.
        verify(rui_bounds(ui_find("second")).x - rui_bounds(ui_find("first")).x == 22.,"gap")
        let sized = rui_bounds(ui_find("sized"))
        verify(sized.z == 150. && sized.w == 30.,"min_width and max_height")
        verify(sized.x - rui_bounds(ui_find("sized_row")).x == 25.,"margin_left")
        let stage = rui_bounds(ui_find("stage"))
        let pinned = rui_bounds(ui_find("pinned"))
        verify(pinned.x - stage.x == 40. && pinned.y - stage.y == 10. && pinned.z == 20. && pinned.w == 20.,"position, left and top")
        let framed = rui_bounds(ui_find("framed"))
        verify(framed.z == 61. && framed.w == 14.,"border and padding_left add to the box")
        let relative_units = rui_bounds(ui_find("relative_units"))
        verify(relative_units.z == 32. && relative_units.w == 48.,"em and vh")
        verify(!rui_visible(ui_find("hidden")),"display")

        // A helper call is a binding: its value is read again only when it changed.
        let dynamic = ui_find("dynamic")
        has(dynamic,"margin-left","4px")
        verify(offset_reads == 1)
        model.unrelated += 1
        ui_frame() { screen(model) }
        verify(offset_reads == 1,"An unchanged helper argument must not be read again")
        model.offset = 9.
        ui_frame() { screen(model) }
        has(dynamic,"margin-left","9px")
        verify(offset_reads == 2)

        let frame = template_markup(@@helper_frame)
        verify(find(frame,"border-radius: 4px;") >= 0 && find(frame,"margin-left: 3px;") >= 0,"Helpers must work in a template frame")

        verify(rui_warning_count() == 0ul)
        ui_reset()
        rui_shutdown()
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    print("style helpers: ok\n")
    return 0
}
