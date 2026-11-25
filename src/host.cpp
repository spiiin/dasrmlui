#include "daScript/daScript.h"
#include "live_host.h"
#include <SDL3/SDL.h>
#define SDL_MAIN_HANDLED
#include <SDL3/SDL_main.h>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <filesystem>
#include <string>
#include <vector>
#ifdef __ANDROID__
#include <unistd.h>
#include "script_access.h"
#endif
DECLARE_MODULE(Module_dasSDL3);
DECLARE_MODULE(Module_dasRmlUi);
DECLARE_MODULE(Module_LiveHost);
void rui_shutdown();
void rui_live_close();
const char* rui_last_native_error();
void rui_set_default_font(const char* path);
// The build records its own tree only when DASRMLUI_DEV_PATHS is on. A packaged
// binary is built without it and carries no absolute path at all.
#ifndef DAS_ROOT
#define DAS_ROOT ""
#endif
#ifndef SDL_MODULE_ROOT
#define SDL_MODULE_ROOT ""
#endif
#ifndef UI_MODULE_ROOT
#define UI_MODULE_ROOT ""
#endif
#ifndef EXAMPLES_ROOT
#define EXAMPLES_ROOT ""
#endif
#ifndef RMLUI_FONT
#define RMLUI_FONT ""
#endif
namespace {
struct Location { std::string path; const char* origin; };
// Looked up in order: the DASRMLUI_HOME folder, the folder of the executable
// and the one above it (an installed package keeps the binary in bin/), then
// the tree this binary was built from, if the build recorded it.
Location locate(const char* relative, const char* build_time, bool directory = true) {
    namespace fs = std::filesystem;
    std::vector<std::pair<fs::path,const char*>> homes;
    const char* home = std::getenv("DASRMLUI_HOME");
    if (home && *home) homes.push_back({fs::path(home), "DASRMLUI_HOME"});
    if (const char* base = SDL_GetBasePath()) {
        homes.push_back({fs::path(base), "beside the executable"});
        homes.push_back({fs::path(base) / "..", "beside the executable"});
    }
    for (const auto& entry : homes) {
        std::error_code error;
        const auto candidate = entry.first / relative;
        const auto status = fs::status(candidate, error);
        if (error || (directory ? !fs::is_directory(status) : !fs::is_regular_file(status))) continue;
        const auto resolved = fs::weakly_canonical(candidate, error);
        return {(error ? candidate : resolved).generic_string(), entry.second};
    }
    if (build_time && *build_time) return {build_time, "build tree"};
    return {"", "not found"};
}
struct Roots {
    Location das = locate("daScript", DAS_ROOT);
    Location sdl = locate("dassdl3", SDL_MODULE_ROOT);
    Location ui = locate("dasrmlui", UI_MODULE_ROOT);
    Location examples = locate("examples", EXAMPLES_ROOT);
    Location font = locate("assets/LatoLatin-Regular.ttf", RMLUI_FONT, false);
    void print() const {
        const std::pair<const char*,const Location*> all[] = {
            {"daScript",&das},{"dassdl3",&sdl},{"dasrmlui",&ui},{"examples",&examples},{"font",&font}};
        for (const auto& item : all)
            std::printf("%-9s %s (%s)\n", item.first, item.second->path.empty() ? "-" : item.second->path.c_str(), item.second->origin);
    }
    // Scripts cannot run without these three; examples and the font are optional.
    const char* missing() const { return das.path.empty() ? "daScript" : sdl.path.empty() ? "dassdl3" : ui.path.empty() ? "dasrmlui" : nullptr; }
};
}
static int run(const char* path, bool smoke, const Roots& roots) {
    using namespace das;
    TextPrinter out; ModuleGroup modules;
#ifdef __ANDROID__
    auto access = android_script_access();
#else
    auto access = make_smart<FsFileAccess>();
#endif
    access->addFsRoot("dassdl3", roots.sdl.path);
    access->addFsRoot("dasrmlui", roots.ui.path);
    access->addFsRoot("live", roots.das.path + "/modules/dasLiveHost/live");
    access->addFsRoot("glsl", roots.das.path + "/modules/dasGlsl/glsl");
    if (!roots.examples.path.empty()) access->addFsRoot("examples", roots.examples.path);
    auto program = compileDaScript(path, access, out, modules);
    auto errors = [&] { for (auto& e : program->errors) out << reportError(e.at,e.what,e.extra,e.fixme,e.cerr); out.output(); std::fflush(stdout); };
    if (program->failed()) { errors(); return 1; }
    Context context(program->getContextStackSize());
    // Native registrations may retain this Context's static dispatcher. Tear
    // down RmlUi while the Context/program are still alive, including on error.
    struct UiLifetime { ~UiLifetime() { rui_shutdown(); } } ui_lifetime;
    if (!program->simulate(context, out)) { errors(); return 2; }
    auto fn = context.findFunction("main");
    if (!fn || !verifyCall<int32_t,bool>(fn->debugInfo,modules)) {
        out << "Expected [export] def main(smoke : bool) : int\n"; return 3;
    }
    vec4f args[] = {cast<bool>::from(smoke)};
    auto result = context.evalWithCatch(fn,args);
    if (auto ex = context.getException()) { out << "Script exception: " << ex << "\n"; return 4; }
    rui_shutdown();
    if (auto error = rui_last_native_error()) { out << error << "\n"; return 4; }
    return cast<int32_t>::to(result);
}
#ifdef __ANDROID__
static int run_host(int argc, char** argv) {
#else
int main(int argc, char** argv) {
#endif
#ifdef __EMSCRIPTEN__
    std::setvbuf(stdout,nullptr,_IONBF,0); std::setvbuf(stderr,nullptr,_IONBF,0);
#endif
    if (argc < 2) {
        std::printf("usage: dasrmlui <script.das> [--smoke-test] [--watch [--styles styles.das] [--frames N]]\n       dasrmlui --roots   show where the runtime folders were found\n");
        return 2;
    }
    SDL_SetMainReady();
    const Roots roots;
    if (!strcmp(argv[1], "--roots")) { roots.print(); return roots.missing() ? 5 : 0; }
    if (const char* name = roots.missing()) {
        std::printf("dasrmlui: the '%s' folder was not found. Keep the runtime folders beside the executable or set DASRMLUI_HOME.\n", name);
        roots.print();
        return 5;
    }
    das::setDasRoot(roots.das.path);
    rui_set_default_font(roots.font.path.c_str());
    NEED_ALL_DEFAULT_MODULES; NEED_MODULE(Module_dasSDL3); NEED_MODULE(Module_dasRmlUi); NEED_MODULE(Module_LiveHost);
    das::Module::Initialize();
    bool watch=false, smoke=false; const char* styles=nullptr; int frames=0;
    for (int i=2;i<argc;++i) {
        if (!strcmp(argv[i],"--watch")) watch=true;
        else if (!strcmp(argv[i],"--smoke-test")) smoke=true;
        else if (!strcmp(argv[i],"--styles") && i+1<argc) styles=argv[++i];
        else if (!strcmp(argv[i],"--frames") && i+1<argc) frames=std::atoi(argv[++i]);
        else { std::fprintf(stderr,"Unknown/incomplete option: %s\n",argv[i]); return 2; }
    }
    int code = watch ? run_ui_live(argv[1],styles,roots.das.path,roots.sdl.path,roots.ui.path,roots.examples.path,smoke,frames)
                     : run(argv[1],smoke,roots);
    rui_shutdown(); rui_live_close(); SDL_Quit(); das::Module::Shutdown(); return code;
}
#ifdef __ANDROID__
extern "C" SDL_DECLSPEC int SDLCALL SDL_main(int argc, char** argv) {
    if (argc < 3) return 2;
    std::error_code error;
    std::filesystem::current_path(argv[1], error);
    if (error || setenv("DASRMLUI_HOME", argv[1], 1) != 0) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "Could not open the packaged dasRmlUi runtime");
        return 2;
    }
    // Android has no terminal. Preserve compiler diagnostics and live reload
    // receipts in app-private storage, accessible with adb run-as on debug APKs.
    if (std::freopen("logs/host.log", "w", stdout)) {
        dup2(fileno(stdout), STDERR_FILENO);
        std::setvbuf(stdout, nullptr, _IONBF, 0);
    }
    // RmlUi's touch handler generates its own pointer press and release.
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
    SDL_Log("dasRmlUi runtime %s", argv[1]);
    // The extracted root takes argv[0]'s place for the shared command line.
    int code = run_host(argc - 1, argv + 1);
    SDL_Log("dasRmlUi %s exited with %d", argv[2], code);
    return code;
}
#endif
