options gen2
module template_slot_fixture public
require dasrmlui/ui public
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

[ui_template]
def slot_test_frame() {
    window_frame("frame") { box("decoration") {}; slot("actual_slot") }
}
[ui_component(legacy=true)]
def invalid_slot_content(document:uint64; target:string) {
    document_content(document,target) { text("message","Invalid destination") }
}
def check_invalid_slot(target:string):int {
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Invalid slot",320,240,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,320,240)); verify(rui_default_font())
        let document=open_template(@@slot_test_frame,"Invalid slot",float2(0.))
        ui_legacy_frame() { invalid_slot_content(document,target) }
        ui_reset(); rui_close_document(document); rui_shutdown()
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
