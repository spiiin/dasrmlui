options gen2
options persistent_heap
options gc
require examples/inventory_ui
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

[export]
def main(smoke:bool) : int {
    var initial <- initial_inventory()
    var state=ui_state(initial)
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let flags = smoke ? SDL_WINDOW_HIDDEN : SDL_WINDOW_RESIZABLE
        let window : SDL_Window? = with_window("dasrmlui - Inventory",960,640,flags) |> sdl_use
        let renderer : SDL_Renderer? = window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,960,640))
        verify(rui_default_font())
        var event = SDL_MakeEvent()
        var running = true
        var frames = 0
        while (running) {
            while (is_some(poll_event(event))) {
                if (should_close(event)) { running = false }
                rui_event(event)
            }
            ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
            renderer |> set_color(uint4(19u,25u,38u,255u)) |> sdl_try
            renderer |> clear() |> sdl_try
            rui_render()
            if (smoke && frames == 2) { verify(rui_screenshot("logs/inventory.png")) }
            renderer |> present() |> sdl_try
            frames += 1
            if (frames % 120 == 0) { unsafe { heap_collect(true,false) } }
            if (smoke && frames >= 3) { break }
            SDL_Delay(16u)
        }
        ui_reset()
        rui_shutdown()
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}

