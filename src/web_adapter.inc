#ifdef __EMSCRIPTEN__
#include <emscripten.h>
static bool web_stopped=false;
extern "C" EMSCRIPTEN_KEEPALIVE void rui_web_stop() { web_stopped=true; das::live_request_exit(); }
static int rui_web_run(const char* title,const das::TBlock<void,float>& tick,const das::TBlock<void>& render,
    das::Context* context,das::LineInfoArg* at) {
    if(!rui_live_open(title,1200,820,true)) context->throw_error_at(at,"WebGL2 initialization failed: %s",SDL_GetError());
    uint64_t previous=SDL_GetTicks(); bool ready=false;
    while(!web_stopped) {
        if(!rui_live_tick(context)) break;
        uint64_t now=SDL_GetTicks(); float dt=(std::min)(0.1f,float(now-previous)*0.001f); previous=now;
        vec4f args[]={das::cast<float>::from(dt)};
        context->invoke(tick,args,nullptr,at);
        context->invoke(render,nullptr,nullptr,at);
        rui_live_present(context);
        if(context->getException()) context->rethrow();
        if(!ready) { ready=true; EM_ASM({ Module.onUiReady?.(); }); }
        // Yield at the frame boundary, preserving the interpreter's stack blocks.
        emscripten_sleep(16);
    }
    return 0;
}
#endif
