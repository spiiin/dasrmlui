// Host-owned SDL objects survive Context swaps. RmlUi is rebuilt on a code
// reload so no native registration can keep a pointer into the retired VM.
namespace {
SDL_Window* live_window=nullptr;
SDL_Renderer* live_renderer=nullptr;
SDL_GLContext live_gl=nullptr;
bool live_hidden=false;
bool live_isolated=false;
bool live_advanced=false;
}
void rui_live_isolate(bool isolated) { live_isolated=isolated; }
void rui_live_hidden(bool hidden) { live_hidden=hidden; }
void rui_live_close() {
    if(live_gl) SDL_GL_DestroyContext(live_gl);
    if(live_renderer) SDL_DestroyRenderer(live_renderer);
    if(live_window) SDL_DestroyWindow(live_window);
    live_gl=nullptr; live_renderer=nullptr; live_window=nullptr;
    live_extra_css.clear(); live_base_css.clear();
}
static bool rui_live_open(const char* title,int width,int height,bool advanced) {
    if(width<=0 || height<=0) return false;
    if(live_window && advanced!=live_advanced) return false;
    if(!live_window) {
        if(!SDL_Init(SDL_INIT_VIDEO)) return false;
        SDL_WindowFlags flags=SDL_WINDOW_RESIZABLE | (live_hidden ? SDL_WINDOW_HIDDEN : 0);
#if defined(DASRMLUI_IOS)
        flags |= SDL_WINDOW_HIGH_PIXEL_DENSITY;
#endif
        if(advanced) {
            SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION,3);
#if defined(__EMSCRIPTEN__) || defined(DASRMLUI_IOS)
            SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION,0);
            SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK,SDL_GL_CONTEXT_PROFILE_ES);
#else
            SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION,3);
            SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK,SDL_GL_CONTEXT_PROFILE_CORE);
#endif
            SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE,8);
            SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER,1);
            flags |= SDL_WINDOW_OPENGL;
        }
        live_window=SDL_CreateWindow(title,width,height,flags);
        if(!live_window) return false;
        live_advanced=advanced;
        if(advanced) live_gl=SDL_GL_CreateContext(live_window);
        else live_renderer=SDL_CreateRenderer(live_window,nullptr);
        if(advanced ? !live_gl : !live_renderer) { rui_live_close(); return false; }
        if(advanced) SDL_GL_SetSwapInterval(1);
    }
    SDL_SetWindowTitle(live_window,title);
    if(state) return true;
#if defined(DASRMLUI_IOS)
    const int w=width,h=height;
#else
    int w,h; SDL_GetWindowSizeInPixels(live_window,&w,&h);
#endif
    live_base_css.clear();
    return rui_init_backend(live_window,live_renderer,w,h,advanced) && rui_default_font();
}
static uint64_t rui_live_window_id() { return live_window ? SDL_GetWindowID(live_window) : 0; }
static bool live_native_call(das::Context* context,const das::callable<void()>& body) {
    char error[2048]{};
    try { return context->runWithCatch(body); }
    catch(const std::exception& e) { std::snprintf(error,sizeof(error),"%s",e.what()); }
    return context->runWithCatch([&] { context->throw_error(error); });
}
bool rui_live_tick(das::Context* context) {
    bool running=true;
    bool ok=live_native_call(context,[&] {
        SDL_Event event;
        while(SDL_PollEvent(&event)) {
            if(event.type==SDL_EVENT_QUIT || event.type==SDL_EVENT_WINDOW_CLOSE_REQUESTED) { running=false; break; }
            if(event.type==SDL_EVENT_KEY_DOWN && !event.key.repeat && event.key.key==SDLK_F5) {
                das::live_request_reload((event.key.mod & SDL_KMOD_SHIFT)!=0);
            } else if(state) rui_event(event);
        }
        rui_native_check(context,nullptr);
    });
    return ok && running;
}
void rui_live_present(das::Context* context) {
    if(!state) return;
    live_native_call(context,[&] {
        rui_update();
        if(live_renderer) { SDL_SetRenderDrawColor(live_renderer,12,18,29,255); SDL_RenderClear(live_renderer); }
        rui_render(context,nullptr);
        if(live_gl) SDL_GL_SwapWindow(live_window);
        else if(live_renderer) SDL_RenderPresent(live_renderer);
#ifdef __EMSCRIPTEN__
        // Canvas input must wait until SDL has processed the focus event. This
        // also lets browser tests synchronize with a completed native frame.
        EM_ASM({ Module.uiFrame = (Module.uiFrame || 0) + 1; });
#endif
    });
}
bool rui_live_set_css(const std::string& css) {
    if(!state) return false;
    const auto warnings=state->system->problems;
    auto sheet=Rml::Factory::InstanceStyleSheetString(live_base_css+css);
    if(!sheet || state->system->problems!=warnings) return false;
    live_extra_css=css; state->css=live_base_css+css;
    state->document->SetStyleSheetContainer(std::move(sheet));
    for(const auto& entry:state->document_styles) document_css(entry.first);
    return true;
}
