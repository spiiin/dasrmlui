options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

// State classes, pseudo-classes and arbitrary tags: what they select, that a
// class change runs a transition, and that native img and label behave natively.

struct Model { selected:int; flagged:bool; unrelated:int }
var selected_reads : int
def is_selected(value:int) : bool { selected_reads += 1; return value == 1 }

[ui_style]
def card_style() {
    rule(part("card")) { width(px(40)); height(px(20)); property("transition","width 0.2s") }
    part("card") |> with_class("selected") |> rule() { width(px(120)) }
    part("card") |> with_pseudo("flagged") |> rule() { height(px(60)) }
}

[ui_component]
def screen(var model:Model) {
    use_style(@@card_style)
    column("screen") {
        box("card") {
            class_if("selected",is_selected(model.selected))
            pseudo_if("flagged",model.flagged)
        }
        // The image sits in a block so that it keeps the size of its source.
        box("holder") {
            element("pic","img") { attribute("src","examples/assets/style_atlas.png") }
        }
        element("name_label","label") {
            attribute("for","name_field")
            text("caption","Name")
        }
        text_input("name") { attribute("id","name_field") }
        element("note","p") { text("note_text","A paragraph") }
    }
}

// The same calls describe a static frame.
[ui_template]
def tagged_window() {
    window_frame("window") {
        element("lead","p") { class_if("quiet",true) }
        slot("content")
    }
}

def frames(var model:Model; count:int) {
    for (i in range(count)) {
        rui_test_advance_time(double(0.05))
        ui_frame() { screen(model) }
    }
}

[export]
def main(smoke:bool):int {
    var model = Model()
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let window : SDL_Window? = with_window("element tests",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer : SDL_Renderer? = window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480))
        verify(rui_default_font())
        rui_test_advance_time(double(0.)) // from here on time moves only when the test says so
        ui_frame() { screen(model) }

        // The condition is a dependency like any other: unrelated changes skip it.
        let card = ui_find("card")
        verify(rui_bounds(card).z == 40. && rui_bounds(card).w == 20. && selected_reads == 1)
        model.unrelated += 1
        ui_frame() { screen(model) }
        verify(selected_reads == 1,"class_if must not read an unchanged condition again")

        // A class change runs the transition; an inline property change would not.
        model.selected = 1
        ui_frame() { screen(model) }
        frames(model,2)
        let midway = rui_bounds(card).z
        verify(midway > 40. && midway < 120.,"A class change must run the width transition")
        frames(model,6)
        verify(rui_bounds(card).z == 120. && ui_find("card") == card && selected_reads == 2)
        model.selected = 0
        ui_frame() { screen(model) }
        frames(model,8)
        verify(rui_bounds(card).z == 40.,"Removing the class must restore the base rule")

        model.flagged = true
        ui_frame() { screen(model) }
        verify(rui_bounds(card).w == 60.,"pseudo_if must select the :flagged rule")
        model.flagged = false
        ui_frame() { screen(model) }
        verify(rui_bounds(card).w == 20.)

        // Native behaviour of the tags themselves.
        let pic = rui_bounds(ui_find("pic"))
        verify(pic.z == 192. && pic.w == 96.,"An img element must take the size of its source")
        let field = ui_find("name")
        verify(!rui_focused(field))
        rui_test_click(ui_find("name_label"))
        ui_frame() { screen(model) }
        verify(rui_focused(field),"A label must hand its click to the field it names")
        verify(find(rui_markup(),"<p ") >= 0)

        let frame = template_markup(@@tagged_window)
        verify(find(frame,"<p id=\"lead\"") >= 0 && find(frame,"__is_quiet") >= 0,"A template frame accepts element and class_if")

        verify(rui_warning_count() == 0ul)
        ui_reset()
        rui_shutdown()
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    print("elements: ok\n")
    return 0
}
