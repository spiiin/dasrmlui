#include "daScript/daScript.h"
#include <SDL3/SDL.h>
#define SDL_MAIN_HANDLED
#include <SDL3/SDL_main.h>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <filesystem>
#include <string>
#include <vector>
DECLARE_MODULE(Module_dasSDL3);
DECLARE_MODULE(Module_dasRmlUi);
void rui_shutdown();
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
Location locate(const char* relative, const char* build_time) {
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
        if (!fs::exists(candidate, error)) continue;
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
    Location font = locate("assets/LatoLatin-Regular.ttf", RMLUI_FONT);
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
    auto access = make_smart<FsFileAccess>();
    access->addFsRoot("dassdl3", roots.sdl.path);
    access->addFsRoot("dasrmlui", roots.ui.path);
    if (!roots.examples.path.empty()) access->addFsRoot("examples", roots.examples.path);
    auto program = compileDaScript(path, access, out, modules);
    auto errors = [&] { for (auto& e : program->errors) out << reportError(e.at,e.what,e.extra,e.fixme,e.cerr); };
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
int main(int argc, char** argv) {
    if (argc < 2) {
        std::printf("usage: dasrmlui <script.das> [--smoke-test]\n       dasrmlui --roots   show where the runtime folders were found\n");
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
    NEED_ALL_DEFAULT_MODULES; NEED_MODULE(Module_dasSDL3); NEED_MODULE(Module_dasRmlUi);
    das::Module::Initialize();
    int code = run(argv[1], argc > 2 && !strcmp(argv[2], "--smoke-test"), roots);
    rui_shutdown(); SDL_Quit(); das::Module::Shutdown(); return code;
}
