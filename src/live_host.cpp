// SDL3/RmlUi frame driver for the upstream daScript LiveHost module.
#include "daScript/daScript.h"
#include "dasLiveHost.h"
#include "live_host.h"
#include "script_access.h"
#include <SDL3/SDL.h>
#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <chrono>
#include <cstdio>
#include <cstring>
using namespace das;
extern "C" {
void live_host_set_live_mode(bool); void live_host_set_is_reload(bool);
void live_host_clear_reload_flags(); void live_host_clear_live_vars();
void live_host_bump_reload_generation(); void live_host_set_last_error(const char*);
void live_host_set_fps(float);
void live_host_set_watched_files(const char**,int); void live_host_advance_clock(float);
bool live_host_reload_requested(); bool live_host_full_reload(); bool live_host_reset_requested();
bool live_host_files_changed();
}
const char* rui_last_native_error();
void rui_shutdown(); void rui_live_close(); bool rui_live_tick(Context*);
void rui_live_isolate(bool);
void rui_live_present(Context*); void rui_live_hidden(bool);
bool rui_live_set_css(const std::string&);
namespace {
std::string canonical(const std::string& name) {
    std::error_code error; auto p=std::filesystem::weakly_canonical(name,error);
    return error ? name : p.generic_string();
}
uint64_t fingerprint(const std::string& name) {
    std::ifstream f(name,std::ios::binary); if (!f) return 0;
    uint64_t h=14695981039346656037ull; char buf[8192];
    while (f) { f.read(buf,sizeof(buf)); for(std::streamsize i=0;i<f.gcount();++i) { h^=uint8_t(buf[i]); h*=1099511628211ull; } }
    return h;
}
struct Unit {
    // The program and ModuleGroup must outlive their Context.
    ModuleGroup modules;
    smart_ptr<FileAccess> access;
    ProgramPtr program;
    std::unique_ptr<Context> context;
    std::map<std::string,uint64_t> files;
    bool changed() {
        bool result=false;
        for(auto& f:files) { auto h=fingerprint(f.first); if(h!=f.second) { f.second=h; result=true; } }
        return result;
    }
};
struct Driver {
    std::string das_root,sdl_root,ui_root,examples_root;
    TextPrinter out;
    std::string error;
    void fail(const std::string& message) {
        error=message; live_host_set_last_error(message.c_str());
        std::fprintf(stderr,"[live] %s\n",message.c_str()); std::fflush(stderr);
    }
    bool simulate(Unit& unit) {
        unit.context=std::make_unique<Context>(unit.program->getContextStackSize());
        rui_live_isolate(true);
        const bool simulated=unit.program->simulate(*unit.context,out);
        rui_live_isolate(false);
        if (!simulated) { fail("simulation failed"); return false; }
        for(auto* file:unit.context->getAllFiles()) if(file && !file->name.empty()) {
            auto name=canonical(file->name.c_str()); unit.files[name]=fingerprint(name);
        }
        return true;
    }
    std::unique_ptr<Unit> compile(const char* path,bool styles,bool prepare=true) {
        auto u=std::make_unique<Unit>();
        auto access=rui_script_access();
        access->addFsRoot("dassdl3",sdl_root); access->addFsRoot("dasrmlui",ui_root);
        access->addFsRoot("glsl",das_root+"/modules/dasGlsl/glsl");
        access->addFsRoot("live",das_root+"/modules/dasLiveHost/live");
        access->addFsRoot("examples",examples_root); u->access=access;
        CodeOfPolicies policies; policies.persistent_heap=true; policies.threadlock_context=true;
        policies.ignore_shared_modules=true; policies.rtti=true;
        u->program=compileDaScript(path,access,out,u->modules,policies);
        if (!u->program || u->program->failed()) {
            TextWriter errors;
            if (u->program) for(auto& e:u->program->errors) errors<<reportError(e.at,e.what,e.extra,e.fixme,e.cerr);
            fail("compile failed; current UI kept\n"+std::string(errors.str().c_str())); return nullptr;
        }
        u->files[canonical(path)]=fingerprint(path);
        if(prepare && (!simulate(*u) || !validate(*u,styles))) return nullptr;
        return u;
    }
    bool validate(Unit& u,bool styles) {
        for(const char* name:styles ? std::vector<const char*>{"live_styles"} : std::vector<const char*>{"init","update"}) {
            auto fn=u.context->findFunction(name);
            if(!fn || !(styles ? verifyCall<char*>(fn->debugInfo,u.modules) : verifyCall<void>(fn->debugInfo,u.modules))) {
                fail(std::string("Expected [export] def ")+name+"()"+(styles ? ":string" : "")); return false;
            }
        }
        return true;
    }
    bool call(Unit& u,const char* name,bool optional=true) {
        auto fn=u.context->findFunction(name);
        if(!fn) return optional;
        if(!verifyCall<void>(fn->debugInfo,u.modules)) { fail(std::string("Invalid void() lifecycle hook: ")+name); return false; }
        u.context->evalWithCatch(fn,nullptr);
        if (auto e=u.context->getException()) { fail(std::string(name)+": "+e); u.context->clearException(); return false; }
        return true;
    }
    bool hooks(Unit& u,const char* prefix) {
        for(int i=0;i<u.context->getTotalFunctions();++i) {
            auto fn=u.context->getFunction(i);
            if(fn && fn->name && !strncmp(fn->name,prefix,strlen(prefix))) {
                if(!verifyCall<void>(fn->debugInfo,u.modules)) { fail("Invalid annotated lifecycle hook"); return false; }
                u.context->evalWithCatch(fn,nullptr);
                if(auto e=u.context->getException()) { fail(e); u.context->clearException(); return false; }
            }
        }
        return true;
    }
    bool sheet(Unit& u) {
        rui_live_isolate(true);
        auto result=u.context->evalWithCatch(u.context->findFunction("live_styles"),nullptr);
        rui_live_isolate(false);
        if(auto e=u.context->getException()) { fail(e); u.context->clearException(); return false; }
        auto css=cast<char*>::to(result);
        if(!rui_live_set_css(css ? css : "")) { fail("invalid stylesheet; current styles kept"); return false; }
        return true;
    }
};
}
int run_ui_live(const char* path,const char* styles,const std::string& das_root,const std::string& sdl_root,
    const std::string& ui_root,const std::string& examples_root,bool hidden,int frames) {
    std::setvbuf(stdout,nullptr,_IONBF,0);
    Driver d{das_root,sdl_root,ui_root,examples_root};
    live_host_set_live_mode(true); rui_live_hidden(hidden);
    auto app=d.compile(path,false);
    if(!app) return 1;
    auto css=styles ? d.compile(styles,true) : nullptr;
    if(styles && !css) return 1;
    if(!d.call(*app,"init",false) || (css && !d.sheet(*css))) { rui_shutdown(); rui_live_close(); return 2; }
    auto watched=[&] {
        std::vector<const char*> names;
        for(auto& f:app->files) names.push_back(f.first.c_str());
        if(css) for(auto& f:css->files) if(!app->files.count(f.first)) names.push_back(f.first.c_str());
        live_host_set_watched_files(names.data(),int(names.size()));
    };
    watched();
    std::printf("[live] ready\n"); std::fflush(stdout);
    auto last=std::chrono::steady_clock::now(),poll=last;
    int count=0,code=0;
    while(!live_exit_requested() && (frames<=0 || count<frames)) {
        auto now=std::chrono::steady_clock::now();
        live_host_advance_clock(std::chrono::duration<float>(now-last).count()); last=now;
        if(!rui_live_tick(app->context.get())) {
            if(auto e=app->context->getException()) { d.fail(e); app->context->clearException(); code=3; }
            break;
        }
        live_host_set_fps(live_get_dt()>0.f ? 1.f/live_get_dt() : 0.f);
        bool source_changed=false,style_changed=false;
        if(now-poll>=std::chrono::milliseconds(250)) {
            source_changed=app->changed(); if(css) style_changed=css->changed(); poll=now;
        }
        bool updated=false;
        bool full=live_host_full_reload() || live_host_reset_requested();
        if(source_changed || live_host_reload_requested() || live_host_files_changed() || full) {
            live_host_clear_reload_flags();
            auto next=d.compile(path,false,false);
            // Compile and validate before touching the running context or its DOM.
            if(next) {
                if(!d.hooks(*app,"__before_reload_") || !d.call(*app,"rt_ui_live_snapshot")) { code=3; break; }
                if(full) live_host_clear_live_vars();
                // Simulate only after saving the latest state: ui_state may be a
                // global initializer. RmlUi remains untouched if this step fails.
                if(!d.simulate(*next) || !d.validate(*next,false)) {
                    if(!d.call(*app,"rt_ui_live_resume")) { code=3; break; }
                    continue;
                }
                live_host_set_is_reload(true);
                if(!d.call(*app,"shutdown") || !d.call(*app,"rt_ui_live_release")) { code=3; break; }
                // All RmlUi callbacks are released while the old Context is alive.
                rui_shutdown();
                bool ok=d.hooks(*next,"__after_reload_") && d.call(*next,"init",false) && d.call(*next,"update",false);
                updated=true;
                if(ok) {
                    app=std::move(next); live_host_bump_reload_generation();
                    live_host_set_last_error(""); live_set_paused(false);
                    std::printf("[live] reloaded %llu\n",(unsigned long long)live_get_reload_generation()); std::fflush(stdout);
                } else {
                    // Failed migration/init: discard candidate objects before its Context,
                    // then re-simulate the last good program from the unchanged snapshot.
                    d.call(*next,"rt_ui_live_release"); rui_shutdown(); next.reset();
                    app->context.reset();
                    if(!d.simulate(*app) || !d.hooks(*app,"__after_reload_") || !d.call(*app,"init",false) || !d.call(*app,"update",false)) { code=4; break; }
                    std::fprintf(stderr,"[live] restored last good program\n");
                }
                watched();
            }
        }
        if(css && style_changed) {
            auto next=d.compile(styles,true);
            if(next && d.sheet(*next)) {
                css=std::move(next); watched(); live_host_set_last_error("");
                std::printf("[live] styles reloaded (no remount)\n"); std::fflush(stdout);
            }
        }
        if(!live_is_paused() && !updated) {
            if(!d.hooks(*app,"__before_update_") || !d.call(*app,"update",false)) { code=3; break; }
        }
        rui_live_present(app->context.get());
        if(auto e=app->context->getException()) { d.fail(e); app->context->clearException(); code=3; break; }
        app->context->collectHeapIfMostlyFree();
        ++count; SDL_Delay(16);
    }
    live_host_set_is_reload(false);
    if(code==0 && !d.call(*app,"shutdown")) code=3;
    if(!d.call(*app,"rt_ui_live_release")) code=3;
    rui_shutdown();
    if(auto error=rui_last_native_error()) { d.fail(error); code=3; }
    rui_live_close();
    live_host_set_live_mode(false);
    return code;
}
