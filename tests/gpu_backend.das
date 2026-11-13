options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

[export]
def main(smoke:bool):int {
    verify(!gpu_effects_available() && gpu_effect_counts()==int2(0))
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("GPU capability",100,100,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,100,100))
        verify(!gpu_effects_available())
        var caught=false
        try { register_shader("test-no-gl",%_esc~vec4 effect(vec2 uv) { return vec4(1); }%_esc) } recover { caught=true }
        verify(caught && !shader_registered("test-no-gl"))
        caught=false
        try { register_filter("test-no-gl",%_esc~vec4 effect(vec2 uv) { return sample_source(uv); }%_esc) } recover { caught=true }
        verify(caught && !filter_registered("test-no-gl") && gpu_effect_counts()==int2(0))
        verify(rui_gpu_error()=="Custom GPU effects require the GL3 renderer")
        verify(rui_warning_count()==0ul)
        rui_shutdown()
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    print("PASS: explicit GPU capability and unsupported SDL backend errors\n")
    return 0
}
