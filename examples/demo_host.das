options gen2
module demo_host public
require dasrmlui/ui public
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

def run_demo(title, screenshot:string; smoke:bool; render:block; check:block<(frame:int):void>) : int {
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let desktop_flags = smoke ? SDL_WINDOW_HIDDEN : SDL_WINDOW_RESIZABLE
        let flags = SDL_GetPlatform() == "Android" ? (SDL_WINDOW_FULLSCREEN | SDL_WINDOW_RESIZABLE) : desktop_flags
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
            invoke(render)
            renderer |> set_color(uint4(12u,18u,29u,255u)) |> sdl_try
            renderer |> clear() |> sdl_try
            rui_render()
            if (smoke && frame == 0) { verify(rui_screenshot(screenshot)) }
            if (smoke && (frame == 3 || frame == 7)) { verify(rui_screenshot("{screenshot}.frame{frame}.png")) }
            renderer |> present() |> sdl_try
            if (smoke) { invoke(check,frame) }
            frame += 1
            // Every two seconds, and sooner when full passes over a long list
            // have left more than 8 MB of temporary strings behind.
            ui_collect_garbage(8,frame % 120 == 0)
            if (smoke && frame == 8) { break }
            SDL_Delay(16u)
        }
        // A smoke run must be clean. RmlUi reports a mistyped property, a bad
        // selector or a missing font only as a warning, so nothing else fails on it.
        if (smoke && rui_warning_count() != 0ul) {
            panic("smoke run: RmlUi reported {int(rui_warning_count())} warning(s) or error(s); see the 'rmlui' lines above")
        }
        ui_reset()
        rui_shutdown()
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
