options gen2
require examples/inventory_ui
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

[export]
def main(smoke:bool) : int {
    var model <- initial_inventory()
    model.items |> push <| Item(id=12,title="Duplicate",count=1)
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let window : SDL_Window? = with_window("negative test",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer : SDL_Renderer? = window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480))
        ui_frame() { inventory_panel(model) }
        rui_shutdown()
        return sdl_ok()
    }
    return 0
}
