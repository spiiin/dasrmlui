options gen2
require rml_native
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

def save_frame(renderer:SDL_Renderer?; path:string) {
    verify(is_ok(renderer |> set_color(uint4(0u,0u,0u,255u))))
    verify(SDL_RenderClear(renderer))
    rui_update()
    rui_render()
    verify(rui_screenshot(path))
    verify(SDL_RenderPresent(renderer))
}

[export]
def main(smoke:bool):int {
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window? = with_window("Unicode input",720,480,SDL_WINDOW_RESIZABLE) |> sdl_use
        let renderer:SDL_Renderer? = window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,720,480))
        verify(rui_default_font())
        verify(rui_font("web/assets/DejaVuSans.ttf"))
        let field = rui_create(rui_root(),"input","","text")
        rui_css("input \{ position: absolute; top: 12px; left: 12px; width: 500px; height: 80px; font-family: LatoLatin; font-size: 48px; color: white; background-color: black; border-width: 0px; \}")
        rui_update()
        rui_focus(field)
        rui_test_text("Привет, Ёж!")
        verify(rui_get_value(field) == "Привет, Ёж!")
        // Move the caret out of the measured field. Compare each glyph to
        // an explicit face at the same size to catch replacement boxes.
        let other = rui_create(rui_root(),"button","","")
        rui_focus(other)
        for (glyph,index in fixed_array("Ж","Я","ё"),range(3)) {
            rui_value(field,glyph)
            rui_property(field,"font-family","LatoLatin")
            save_frame(renderer,"logs/font-default-{index}.png")
            rui_property(field,"font-family","DejaVu Sans")
            save_frame(renderer,"logs/font-reference-{index}.png")
        }
        rui_shutdown()
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
