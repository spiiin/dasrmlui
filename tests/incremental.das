options gen2
options persistent_heap
options gc
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Model { left : int = 10; right : int = 20; show : bool = true }
var parent_runs, leaf_runs, getter_runs, external_runs : int
var external_value = "outside"
var changed = ui_signal()

[ui_component]
def leaf(value:int) {
    leaf_runs += 1
    box("leaf") {
        padding(px(7.0))
        text("number") { getter_runs += 1; return "{value}" }
    }
}
[ui_component]
def external_view() {
    ui_watch(changed)
    external_runs += 1
    text("external") { return external_value }
}
[ui_component]
def panel(model:Model) {
    parent_runs += 1
    column("parent") {
        text("static","Kept across updates")
        leaf(model.left)
        leaf(model.right)
        when(model.show) {
            box("conditional") { padding(px(9.0)); text("conditional_text","new static") }
            external_view()
        }
    }
}

[export]
def main(smoke:bool):int {
    var model = Model()
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let window : SDL_Window? = with_window("incremental tests",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer : SDL_Renderer? = window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480))
        verify(rui_default_font())
        ui_frame() { panel(model) }
        let static_handle = ui_find("static")
        let external_handle = ui_find("external")
        verify(parent_runs == 1 && leaf_runs == 2 && getter_runs == 2 && external_runs == 1)
        verify(ui_stats().mounts == 4)

        ui_clear_stats()
        for (i in range(120)) { ui_frame() { panel(model) } }
        verify(parent_runs == 1 && leaf_runs == 2 && getter_runs == 2 && external_runs == 1,
            "Idle frames must not execute component bodies or getters")
        verify(ui_stats().updates == 0 && ui_stats().mounts == 0 && ui_stats().skips == 120)
        verify(ui_find("static") == static_handle && ui_find("external") == external_handle)

        model.left += 1
        ui_frame() { panel(model) }
        verify(parent_runs == 2 && leaf_runs == 3 && getter_runs == 3,
            "Only the child with changed arguments should update")
        verify(external_runs == 1)
        verify(ui_find("static") == static_handle, "Static text must survive a generated update")

        external_value = "changed through token"
        changed |> ui_touch()
        ui_frame() { panel(model) }
        verify(parent_runs == 3 && external_runs == 2 && leaf_runs == 3,
            "A watched dependency must invalidate sleeping ancestors")
        verify(ui_find("external") == external_handle)
        verify(find(rui_markup(),external_value) >= 0)
        ui_frame() { panel(model) }
        verify(parent_runs == 3 && external_runs == 2)

        model.show = false
        ui_frame() { panel(model) }
        verify(!rui_alive(external_handle))
        let after_remove = parent_runs
        changed |> ui_touch()
        ui_frame() { panel(model) }
        verify(parent_runs == after_remove, "Unmount must detach dependency subscriptions")
        model.show = true
        ui_frame() { panel(model) }
        verify(ui_find("external") != external_handle && external_runs == 3)
        verify(ui_find("conditional_text") != 0ul && find(rui_markup(),"new static") >= 0,
            "An update must initialize static text in a newly mounted subtree")
        unsafe { heap_collect(true,false) }
        ui_frame() { panel(model) }
        verify(external_runs == 3)

        ui_reset()
        ui_frame() { panel(model) }
        verify(ui_stats().mounts == 4 && external_runs == 4)
        changed |> ui_touch()
        ui_frame() { panel(model) }
        verify(external_runs == 5, "Reset must allow subscriptions to be rebuilt")
        ui_reset()
        rui_shutdown()
        print("PASS: 120 idle frames, selective child updates, static retention, dependency propagation, unmount, GC and reset\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}


