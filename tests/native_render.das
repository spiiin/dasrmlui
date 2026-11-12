options gen2
options persistent_heap
options gc
require dasrmlui/ui
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope
var paints:int
struct Model { alternate:bool; opacity:float=1. }
def painter(event:UiNativeEvent) {
    if (event.kind!=UiNativeKind.Paint) { return }
    let ink=rui_get_attr(event.element,"alternate")=="true" ? rgb(240,80,60) : rgb(40,200,100)
    native_rect(event.element,float4(0.,0.,event.size.x,event.size.y),ink)
    native_triangle(event.element,float2(10.,10.),float2(40.,10.),float2(10.,40.),rgb(240,240,240))
    paints+=1
}
[ui_component]
def scene(var model:Model) {
    box("clip") {
        property("position","absolute"); property("left","20px"); property("top","20px")
        width(px(80)); height(px(60)); property("overflow","hidden")
        native_element("paint","test-pixels") {
            width(px(120)); height(px(90)); property("display","block")
            attribute("alternate","{model.alternate}"); opacity(model.opacity)
        }
    }
}
def snapshot(renderer:SDL_Renderer?; name:string) {
    verify(is_ok(renderer |> clear(uint4(0u,0u,0u,255u))))
    rui_render(); verify(rui_screenshot("logs/native_{name}.png"))
}
[export]
def main(smoke:bool):int {
    var model=Model()
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Native pixels",240,180,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,240,180)); verify(rui_default_font()); rui_test_display_scale(1.)
        register_native_element("test-pixels",@@painter,float2(120.,90.))
        ui_frame() { scene(model) }; snapshot(renderer,"initial"); verify(paints==1)
        ui_clear_stats(); ui_frame() { scene(model) }; snapshot(renderer,"cached")
        verify(paints==1 && ui_stats().binding_updates==0)
        model.alternate=true; ui_frame() { scene(model) }; snapshot(renderer,"changed"); verify(paints==2)
        model.opacity=0.5; ui_frame() { scene(model) }; snapshot(renderer,"alpha"); verify(paints==3)
        set_ui_scale(2.); ui_frame() { scene(model) }; snapshot(renderer,"dpi"); verify(paints==4)
        let element=ui_find("paint")
        rui_property(element,"width","50px"); rui_property(element,"height","40px")
        rui_update(); snapshot(renderer,"resized"); verify(paints==5)
        verify(rui_warning_count()==0)
        ui_reset(); rui_shutdown(); return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
