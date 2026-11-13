options gen2
options persistent_heap
options gc
require dasrmlui/ui
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope
var destroyed:int
[ui_component(legacy=true)]
def scene() { native_element("late","test-late") }
[export]
def main(smoke:bool):int {
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Native host lifetime",320,200,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,320,200)); verify(rui_default_font())
        let captured="still-alive-{71}"
        register_native_element("test-late",@(event:UiNativeEvent) {
            if (event.kind==UiNativeKind.Destroy) {
                destroyed+=1; verify(destroyed==1 && captured=="still-alive-71")
                unsafe { heap_collect(true,false) }
                print("PASS: host destroys native elements before script Context\n")
                if (!smoke) { panic("late native destroy fault") }
            }
        },float2(20.,20.))
        ui_legacy_frame() { scene() }
        // No geometry was rendered. Deliberately leave the native context alive
        // to exercise the host's final lifetime guard after main returns.
        return sdl_ok()
    }
    if (is_err(result)) { return 1 }
    return 0
}
