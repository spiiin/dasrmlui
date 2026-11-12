options gen2
module demo_host public
require dasrmlui/ui public
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

def run_demo(title, screenshot:string; smoke:bool; render:block; check:block<(frame:int):void>) : int {
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let flags = smoke ? SDL_WINDOW_HIDDEN : SDL_WINDOW_RESIZABLE
        let window : SDL_Window? = with_window(title,1200,820,flags) |> sdl_use
        let renderer : SDL_Renderer? = window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,1200,820))
        verify(rui_default_font())
        var event = SDL_MakeEvent()
        var running = true
        var frame = 0
        while (running) {
            while (is_some(poll_event(event))) {
                if (should_close(event)) { running = false }
                rui_event(event)
            }
            ui_frame(render)
            renderer |> set_color(uint4(12u,18u,29u,255u)) |> sdl_try
            renderer |> clear() |> sdl_try
            rui_render()
            if (smoke && frame == 0) { verify(rui_screenshot(screenshot)) }
            if (smoke && (frame == 3 || frame == 7)) { verify(rui_screenshot("{screenshot}.frame{frame}.png")) }
            renderer |> present() |> sdl_try
            if (smoke) { invoke(check,frame) }
            frame += 1
            if (frame % 120 == 0) { unsafe { heap_collect(true,false) } }
            if (smoke && frame == 8) { break }
            SDL_Delay(16u)
        }
        ui_reset()
        rui_shutdown()
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
