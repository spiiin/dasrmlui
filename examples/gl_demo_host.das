options gen2
module gl_demo_host public
require dasrmlui/ui public
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope
require dassdl3/sdl3_gl_egl
require math

def run_gl_demo(title,screenshot:string; smoke:bool; tick:block<(delta:float):void>; render:block; check:block<(frame:int):void>):int {
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        set_gl_attribute(SDL_GLAttr.GL_CONTEXT_MAJOR_VERSION,3) |> sdl_try
        set_gl_attribute(SDL_GLAttr.GL_CONTEXT_MINOR_VERSION,3) |> sdl_try
        set_gl_attribute(SDL_GLAttr.GL_CONTEXT_PROFILE_MASK,int(SDL_GL_CONTEXT_PROFILE_CORE)) |> sdl_try
        set_gl_attribute(SDL_GLAttr.GL_STENCIL_SIZE,8) |> sdl_try
        let flags=SDL_WINDOW_OPENGL | (smoke ? SDL_WINDOW_HIDDEN : SDL_WINDOW_RESIZABLE)
        let window:SDL_Window?=with_window(title,1200,820,flags) |> sdl_use
        let context:SDL_GLContextState?=window |> with_gl_context() |> sdl_use
        verify(rui_init_gl(window,1200,820),"OpenGL 3.3 renderer initialization failed")
        verify(rui_default_font())
        var event=SDL_MakeEvent()
        var running=true
        var frame=0
        var previous=SDL_GetTicks()
        while (running) {
            while (is_some(poll_event(event))) {
                if (should_close(event)) { running=false }
                rui_event(event)
            }
            let now=SDL_GetTicks()
            invoke(tick,min(0.1,float(now-previous)*0.001))
            previous=now
            ui_frame(render)
            rui_render()
            if (smoke && frame == 0) { verify(rui_screenshot(screenshot)) }
            if (smoke && (frame == 3 || frame == 7 || frame == 11)) { verify(rui_screenshot("{screenshot}.frame{frame}.png")) }
            swap_gl_window(window) |> sdl_try
            if (smoke) { invoke(check,frame) }
            frame += 1
            if (smoke && frame == 12) { break }
            SDL_Delay(16u)
        }
        ui_reset(); rui_shutdown()
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}

