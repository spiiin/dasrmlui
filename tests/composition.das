options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Model { a:int = 2; caption:string = "first" }
var computations, slot_reads : int
def expensive(value:int):int { computations += 1; return value*2 }
[ui_component]
def panel(title:string; changed:block<(value:int):void>; content:block) {
    column() {
        text("title",title)
        slot(content)
        button("add","Add") { on_click() { emit(changed,1) } }
    }
}
[ui_component]
def screen(var model:Model) {
    computed(expensive(model.a)) $(value:int) {
        panel("{value}",$(change:int) { model.a += change }) {
            text("slot") { slot_reads += 1; return model.caption }
        }
    }
}
[export]
def main(smoke:bool):int {
    var model = Model()
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let window : SDL_Window? = with_window("composition tests",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer : SDL_Renderer? = window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480)); verify(rui_default_font())
        ui_trace(true)
        ui_frame() { screen(model) }
        verify(computations == 1 && slot_reads == 1 && ui_trace_count() > 0)
        let slot_node = ui_find("slot")
        for (i in range(10)) { ui_frame() { screen(model) } }
        verify(computations == 1 && slot_reads == 1)
        model.caption = "second"
        ui_frame() { screen(model) }
        verify(computations == 1 && slot_reads == 2 && ui_find("slot") == slot_node)
        rui_test_click(ui_find("add"))
        ui_frame() { screen(model) }
        verify(model.a == 3 && computations == 2 && slot_reads == 2)
        var saw_field=false
        for (i in range(ui_trace_count())) {
            let entry=ui_trace_at(i)
            if (find(entry.reason,"model.a") >= 0 && find(entry.reason,"computed dependency changed") >= 0) { saw_field=true }
        }
        verify(saw_field,"Trace must identify the changed computed field")
        verify(find(rui_markup(),">6<") >= 0)
        unsafe { heap_collect(true,false) }
        ui_frame() { screen(model) }
        verify(computations == 2)
        ui_reset()
        ui_frame() { screen(model) }
        verify(computations == 3)
        ui_reset(); rui_shutdown()
        print("PASS: computed dependency caching, slots, synchronous component events and trace\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
