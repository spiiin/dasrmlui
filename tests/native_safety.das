options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope
var released:int
[ui_component(legacy=true)]
def view() { native_element("fault","test-fault") }
[export]
def main(smoke:bool):int {
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Native callback isolation",320,240,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,320,240)); verify(rui_default_font())
        for (mode in range(4)) {
            register_native_element("test-fault",@(event:UiNativeEvent) {
                if (mode==0 && event.kind==UiNativeKind.Create) { panic("create fault") }
                if (mode==1 && event.kind==UiNativeKind.Paint) { rui_remove(event.element) }
                if (mode==2 && event.kind==UiNativeKind.Update) { rui_update() }
                if (event.kind==UiNativeKind.Destroy) { released+=1; if (mode==3) { panic("destroy fault") } }
            },float2(40.,40.),true)
            var caught=0
            try { ui_legacy_frame() { view() }; rui_render() } recover { caught+=1 }
            try { ui_reset() } recover { caught+=1 }
            verify(caught==1,"callback failure is caught inside native traversal, then reported outside it")
            verify(released==mode+1 && native_instance_count("test-fault")==0,"failed elements still release exactly once")
            verify(unregister_native_element("test-fault") && native_handler_count()==0)
            unsafe { heap_collect(true,false) }
        }
        var rejected=false
        try { register_native_element("input",@(event:UiNativeEvent) {}) } recover { rejected=true }
        verify(rejected,"built-in tags cannot be overridden")
        register_native_element("test-fault",@(event:UiNativeEvent) {},float2(20.,20.))
        rejected=false
        try { register_native_element("test-fault",@(event:UiNativeEvent) {}) } recover { rejected=true }
        verify(rejected && native_handler_count()==1,"duplicate registration retains original handler")
        rejected=false
        try { native_rect(0ul,float4(0.,0.,10.,10.),rgb(255,0,0)) } recover { rejected=true }
        verify(rejected,"drawing outside Paint is rejected")
        ui_legacy_frame() { view() }; rui_render()
        verify(rui_is_native(ui_find("fault")) && empty(rui_native_error()),"context remains usable after recovered callback errors")
        ui_reset(); rui_shutdown(); verify(native_handler_count()==0)
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    print("PASS: native callback failure isolation, reentry guards, duplicate registration and recovery\n")
    return 0
}
