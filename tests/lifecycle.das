options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Counter { id:int; count:int; notes:array<string> }
struct Model { ids:array<int>; visible:bool = true }
var mounts, unmounts, outer_mounts, outer_unmounts : int
var disposed : table<int;int>
var teardown_order = ""

[ui_component]
def counter(id:int) {
    state(Counter(id=id)) $(var local:Counter) {
        on_mount() {
            mounts += 1
            local.count = 10
            local.notes |> push("owned")
        }
        on_unmount() {
            verify(rui_alive(ui_find("count",local.id)), "Unmount must run while the DOM is still alive")
            unmounts += 1
            disposed[local.id] = local.count
            teardown_order += "child;"
            verify(length(local.notes) == 1)
        }
        row() {
            text("count") { return "{local.count}" }
            button("increment","+") { on_click() { local.count += 1 } }
        }
    }
}
[ui_component]
def group(model:Model) {
    on_mount() { outer_mounts += 1 }
    on_unmount() { outer_unmounts += 1; teardown_order += "parent;" }
    column() {
        model.ids |> each_keyed($(id:int) => id) $(id:int) { counter(id) }
    }
}
[ui_component]
def screen(model:Model) { when(model.visible) { group(model) } }

[export]
def main(smoke:bool):int {
    var model = Model()
    model.ids |> push(1); model.ids |> push(2)
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let window : SDL_Window? = with_window("lifecycle tests",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer : SDL_Renderer? = window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480)); verify(rui_default_font())
        ui_frame() { screen(model) }
        verify(mounts == 2 && outer_mounts == 1 && unmounts == 0)
        let first = ui_find("count",1)
        for (i in range(10)) { ui_frame() { screen(model) } }
        verify(mounts == 2)
        rui_test_event(ui_find("increment",1),"click","")
        ui_frame() { screen(model) }
        verify(find(rui_markup(),">11<") >= 0)
        model.ids[0] = 2; model.ids[1] = 1
        ui_frame() { screen(model) }
        verify(ui_find("count",1) == first && mounts == 2 && unmounts == 0)
        unsafe { heap_collect(true,false) }
        rui_test_event(ui_find("increment",1),"click","")
        ui_frame() { screen(model) }
        verify(find(rui_markup(),">12<") >= 0)
        model.ids |> erase(1)
        ui_frame() { screen(model) }
        verify(!rui_alive(first) && unmounts == 1 && disposed[1] == 12)
        model.ids |> push(1)
        ui_frame() { screen(model) }
        verify(mounts == 3 && ui_find("count",1) != first)
        teardown_order = ""
        model.visible = false
        ui_frame() { screen(model) }
        verify(unmounts == 3 && outer_unmounts == 1 && teardown_order == "child;child;parent;")
        verify(disposed[1] == 10)
        ui_frame() { screen(model) }
        verify(unmounts == 3)
        model.visible = true
        ui_frame() { screen(model) }
        verify(mounts == 5 && outer_mounts == 2)
        ui_reset()
        verify(unmounts == 5 && outer_unmounts == 2)
        ui_reset()
        verify(unmounts == 5)
        ui_frame() { screen(model) }
        verify(mounts == 7 && outer_mounts == 3)
        ui_reset(); rui_shutdown()
        print("PASS: mount once, keyed local state, current-state cleanup, child-first unmount, GC, reset and remount\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
