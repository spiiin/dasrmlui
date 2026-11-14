options gen2
options persistent_heap
options gc
options stack = 65536
require examples/native_lab
require dasrmlui/ui
require sdl3

var initial = Bench()
var lab = ui_state(initial)
var frames = 0

[ui_style]
def phone_lab_style() {
    rule(root()) {
        padding(px(24))
        property("box-sizing","border-box")
        background(rgb(225,225,211))
        color(rgb(37,47,42))
    }
    rule(part("heading")) { font_size(px(28)); margin_bottom(px(12)) }
    rule(part("trace")) { height(px(72)); margin_bottom(px(12)); nav() }
    rule(part("pause")) {
        padding(px(8))
        background(rgb(64,80,63))
        color(rgb(243,237,211))
    }
}

[ui_component]
def phone_lab(var model:Bench) {
    use_style(@@phone_lab_style)
    column() {
        width(px(ui_width()))
        text("heading","Signal foundry")
        native_element("trace","lab-waveform") {
            attribute("gain","{model.gain}")
            attribute("frequency","2")
            attribute("paused","{model.paused}")
            attribute("selected","{model.selected==2}")
            on_click() { model.selected = model.selected==2 ? 1 : 2 }
        }
        text("status",model.selected==2 ? "Trace selected" : "Tap the trace to select it")
        button("pause",model.paused ? "Resume acquisition" : "Hold trace") {
            on_click() { model.paused = !model.paused }
        }
    }
}

[export]
def app_start(window:SDL_Window?; renderer:SDL_Renderer?; fallback_font:string):bool {
    verify(rui_init(window,renderer,800,390))
    verify(rui_default_font())
    verify(rui_fallback_font(fallback_font))
    install_waveform()
    return true
}

[export]
def app_event(event:SDL_Event) {
    rui_event(event)
}

[export]
def app_frame(smoke:bool):bool {
    ui_frame(lab) $(model:Bench) { phone_lab(model) }
    rui_render()
    frames += 1
    if (frames % 120 == 0) { unsafe { heap_collect(true,false) } }
    if (smoke && frames == 1) {
        verify(creations==1 && paint_count>0)
        rui_test_click(ui_find("trace"))
        rui_test_click(ui_find("pause"))
    }
    if (smoke && frames == 2) {
        ui_read(lab) $(model:Bench) { verify(model.selected==2 && model.paused) }
        verify(rui_warning_count()==0ul)
        return true
    }
    return false
}
