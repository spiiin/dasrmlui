options gen2
options persistent_heap
options gc
require dasrmlui/ui
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope
var created,destroyed:int
[ui_component(legacy=true)]
def scene() {
    box("late") { width(px(20)); height(px(20)); custom_decorator("test-late") }
}
[export]
def main(smoke:bool):int {
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Decorator host lifetime",320,200,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,320,200)); verify(rui_default_font())
        let captured="decorator-root-{71}"
        register_decorator("test-late",array<UiDecoratorParam>(),@(event:UiDecoratorEvent) {
            if (event.kind==UiDecoratorKind.Create) { created+=1 }
            elif (event.kind==UiDecoratorKind.Destroy) {
                destroyed+=1; verify(created==1 && destroyed==1 && captured=="decorator-root-71")
                unsafe { heap_collect(true,false) }
                print("PASS: host destroys decorator data before script Context\n")
                if (!smoke) { panic("late decorator destroy fault") }
            }
        })
        ui_legacy_frame() { scene() }; rui_render(); verify(created==1)
        // No decorator geometry/textures. Leave RmlUi alive to test the host guard.
        return sdl_ok()
    }
    if (is_err(result)) { return 1 }
    return 0
}
