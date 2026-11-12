options gen2
options persistent_heap
options gc
require dasrmlui/ui
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Frame { alternate:bool }
def snapshot(renderer:SDL_Renderer?; name:string) {
    verify(is_ok(renderer |> clear(uint4(0u,0u,0u,255u))))
    rui_render(); verify(rui_screenshot("logs/vector_{name}.png"))
}
[ui_style]
def vector_style() {
    rule("body") { background(rgb(0,0,0)) }
    rule(part("file")+", "+part("crop")+", "+part("inline")+", "+part("decorated")+", "+part("motion")) { property("position","absolute"); width(px(100)); height(px(100)); property("top","20px") }
    rule(part("file")) { property("left","20px") }
    rule(part("crop")) { property("left","140px") }
    rule(part("inline")) { property("left","260px"); image_color(rgb(60,120,240)); opacity(0.5) }
    rule(part("decorated")) { property("left","380px"); svg_decorator("examples/assets/vector_probe.svg",true) }
    rule(part("motion")) { property("left","20px"); property("top","160px"); width(px(200)); height(px(100)) }
}
[ui_component]
def scene(var frame:Frame) {
    use_style(@@vector_style)
    svg_image("file",frame.alternate ? "examples/assets/vector_probe_alt.svg" : "examples/assets/vector_probe.svg")
    svg_image("crop","examples/assets/vector_probe.svg",true)
    svg_inline("inline",frame.alternate ? "<rect width='50' height='100' fill='white'/>" : "<rect width='100' height='100' fill='white'/>",float2(100.,100.))
    box("decorated") {}
    lottie("motion",frame.alternate ? "examples/assets/vector_probe_alt.json" : "examples/assets/vector_probe.json")
}
[export]
def main(smoke:bool):int {
    var frame=Frame()
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Vector pixels",520,300,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,520,300)); verify(rui_default_font())
        rui_test_display_scale(1.); rui_test_advance_time(0.0lf)
        rui_property(rui_root(),"background-color","#000000")
        ui_frame() { scene(frame) }
        verify(rui_bounds(ui_find("file"))==float4(20.,20.,100.,100.))
        verify(rui_bounds(ui_find("motion"))==float4(20.,160.,200.,100.))
        snapshot(renderer,"0")
        ui_clear_stats(); rui_test_advance_time(0.5lf); ui_frame() { scene(frame) }
        verify(ui_stats().binding_updates==0,"Lottie must animate without evaluating bindings")
        snapshot(renderer,"half")
        rui_test_advance_time(0.5lf); ui_frame() { scene(frame) }
        snapshot(renderer,"1")
        rui_test_advance_time(1.0lf); ui_frame() { scene(frame) }
        snapshot(renderer,"loop")
        set_ui_scale(2.); ui_frame() { scene(frame) }
        snapshot(renderer,"dpi")
        frame.alternate=true; ui_frame() { scene(frame) }
        snapshot(renderer,"changed")
        rui_property(ui_find("crop"),"width","200px")
        rui_property(ui_find("motion"),"width","300px"); rui_property(ui_find("motion"),"height","150px")
        rui_update(); snapshot(renderer,"resized")
        verify(rui_bounds(ui_find("motion"))==float4(20.,160.,300.,150.))
        verify(rui_warning_count()==0)
        ui_reset(); rui_shutdown()
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
