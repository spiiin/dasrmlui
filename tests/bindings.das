options gen2
options persistent_heap
options gc
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Row { id:int; title:string }
struct Profile { name:string = "Ada"; detail:string = "Engineer" }
struct Model {
    profile : Profile = Profile()
    input : string = "accepted"
    size : float = 100.0
    show : bool = true
    enabled : bool = true
    unrelated : int
    rows : array<Row>
}
var title_reads, detail_reads, width_reads, disabled_reads, condition_reads, input_reads, row_reads, clicks : int
def input_text(value:string) : string { input_reads += 1; return value }

[ui_component(legacy=true)]
def screen(var model:Model) {
    column("screen") {
        text("title") { let value = model.profile.name; title_reads += 1; return value }
        box("sized") {
            width() { width_reads += 1; return px(model.size) }
            text("static","unchanged")
        }
        button("action","Action") {
            disabled() { disabled_reads += 1; return !model.enabled }
            on_click() { clicks += 1 }
        }
        button("disable_action","Disable action") {
            on_click() { model.enabled = false }
        }
        text_input("input") {
            bind_value(input_text(model.input)) $(value:string) {
                if (!empty(value)) { model.input = value }
            }
        }
        when($() { condition_reads += 1; return model.show }) {
            text("detail") { detail_reads += 1; return model.profile.detail }
        }
        model.rows |> each_keyed($(item:Row) => item.id) $(item:Row) {
            text("row") { row_reads += 1; return item.title }
        }
        text("first_row") {
            if (!empty(model.rows)) { return model.rows[0].title }
            return "No rows remain"
        }
    }
}

[export]
def main(smoke:bool):int {
    var model = Model()
    model.rows |> push <| Row(id=1,title="one")
    model.rows |> push <| Row(id=2,title="two")
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let window : SDL_Window? = with_window("binding tests",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer : SDL_Renderer? = window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480))
        verify(rui_default_font())
        ui_legacy_frame() { screen(model) }
        let title_handle = ui_find("title")
        let row1 = ui_find("row",1)
        let input = ui_find("input")
        verify(title_reads == 1 && detail_reads == 1 && width_reads == 1 && disabled_reads == 1)
        verify(condition_reads == 1 && input_reads == 1 && row_reads == 2)

        ui_clear_stats()
        model.unrelated += 1
        ui_legacy_frame() { screen(model) }
        verify(ui_stats().binding_updates == 0 && ui_stats().binding_skips > 0,
            "An unrelated field must not evaluate any binding")
        verify(title_reads == 1 && detail_reads == 1 && width_reads == 1 && condition_reads == 1 && input_reads == 1 && row_reads == 2)
        model.profile.name = "Grace"
        ui_legacy_frame() { screen(model) }
        verify(title_reads == 2 && detail_reads == 1 && width_reads == 1 && disabled_reads == 1 && input_reads == 1,
            "A nested field must not invalidate sibling fields")
        verify(ui_find("title") == title_handle && find(rui_markup(),"Grace") >= 0)

        model.profile.detail = "Compiler designer"
        ui_legacy_frame() { screen(model) }
        verify(detail_reads == 2 && condition_reads == 1,
            "A cached true condition must still update its children")
        model.size = 140.0
        ui_legacy_frame() { screen(model) }
        verify(width_reads == 2 && title_reads == 2 && disabled_reads == 1)
        model.enabled = false
        ui_legacy_frame() { screen(model) }
        verify(disabled_reads == 2 && width_reads == 2)
        verify(!rui_enabled(ui_find("action")))
        rui_test_event(ui_find("action"),"click","")
        ui_legacy_frame() { screen(model) }
        verify(clicks == 0, "Disabled buttons must reject clicks")
        model.enabled = true
        ui_legacy_frame() { screen(model) }
        rui_test_event(ui_find("action"),"click","")
        ui_legacy_frame() { screen(model) }
        verify(clicks == 1)
        rui_test_event(ui_find("disable_action"),"click","")
        rui_test_event(ui_find("action"),"click","")
        ui_legacy_frame() { screen(model) }
        verify(clicks == 1, "An earlier event may disable a later event's target")

        model.rows[0].title = "ONE"
        ui_legacy_frame() { screen(model) }
        verify(row_reads == 3 && ui_find("row",1) == row1)
        let swap = model.rows[0]
        model.rows[0] = model.rows[1]
        model.rows[1] = swap
        ui_legacy_frame() { screen(model) }
        verify(row_reads == 3, "Keyed reorder must retain binding snapshots without evaluating getters")

        rui_test_event(input,"change","")
        ui_legacy_frame() { screen(model) }
        verify(rui_get_value(input) == "accepted" && input_reads == 2,
            "Rejected input forces only its binding and never evaluates its value during dispatch")
        verify(title_reads == 2 && row_reads == 3 && condition_reads == 1)
        rui_test_event(input,"change","new value")
        ui_legacy_frame() { screen(model) }
        verify(model.input == "new value" && input_reads == 3 && width_reads == 2)

        let detail = ui_find("detail")
        model.show = false
        ui_legacy_frame() { screen(model) }
        verify(!rui_alive(detail) && condition_reads == 2)
        model.profile.detail = "changed while hidden"
        ui_legacy_frame() { screen(model) }
        verify(detail_reads == 2 && condition_reads == 2)
        model.show = true
        ui_legacy_frame() { screen(model) }
        verify(ui_find("detail") != detail && detail_reads == 3 && condition_reads == 3)
        model.rows |> erase(1)
        ui_legacy_frame() { screen(model) }
        model.rows |> push <| Row(id=1,title="ONE")
        ui_legacy_frame() { screen(model) }
        verify(ui_find("row",1) != row1 && row_reads == 4,
            "A remounted key must not inherit a retired binding snapshot")
        unsafe { heap_collect(true,false) }
        ui_legacy_frame() { screen(model) }
        verify(row_reads == 4 && detail_reads == 3)
        ui_reset()
        ui_legacy_frame() { screen(model) }
        verify(title_reads == 3 && row_reads == 6)
        clear(model.rows)
        ui_legacy_frame() { screen(model) }
        verify(find(rui_markup(),"No rows remain") >= 0,
            "Dependency sampling must preserve short-circuit safety for array indexing")
        ui_reset()
        rui_shutdown()
        print("PASS: field-level text/properties/conditions/input, keyed retention, unmount, GC and reset\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
