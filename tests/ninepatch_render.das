options gen2
options persistent_heap
options gc
require dasrmlui/ui
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

[ui_style]
def patches() {
    spritesheet("examples/assets/style_atlas.png",2.) {
        sprite("night",0,0,96,96); sprite("night_inner",24,24,48,48)
        sprite("paper",96,0,96,96); sprite("paper_inner",120,24,48,48)
    }
    rule(part("small")+", "+part("large")) { property("position","absolute"); property("top","20px"); ninepatch("night","night_inner") }
    rule(part("small")) { property("left","20px"); width(px(120)); height(px(80)) }
    rule(part("large")) { property("left","200px"); width(px(240)); height(px(160)) }
    theme("paper") { rule(part("small")+", "+part("large")) { ninepatch("paper","paper_inner") } }
}
[ui_component]
def screen() { use_style(@@patches); box("small") {}; box("large") {} }
[export]
def main(smoke:bool):int {
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Ninepatch pixels",600,400,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,600,400)); verify(rui_default_font())
        rui_test_display_scale(1.)
        ui_frame() { screen() }
        verify(rui_bounds(ui_find("small"))==float4(20.,20.,120.,80.))
        verify(rui_bounds(ui_find("large"))==float4(200.,20.,240.,160.))
        rui_render(); verify(rui_screenshot("logs/ninepatch_1.png"))
        set_ui_scale(2.)
        ui_frame() { screen() }
        rui_render(); verify(rui_screenshot("logs/ninepatch_2.png"))
        set_ui_scale(1.); set_theme("paper")
        ui_frame() { screen() }
        rui_render(); verify(rui_screenshot("logs/ninepatch_paper.png"))
        ui_reset(); rui_shutdown()
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
