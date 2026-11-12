#include "daScript/daScript.h"
#include <SDL3/SDL.h>
#define SDL_MAIN_HANDLED
#include <SDL3/SDL_main.h>
#include <cstring>
DECLARE_MODULE(Module_dasSDL3);
DECLARE_MODULE(Module_dasRmlUi);
void rui_shutdown();
static int run(const char* path, bool smoke) {
    using namespace das;
    TextPrinter out; ModuleGroup modules;
    auto access = make_smart<FsFileAccess>();
    access->addFsRoot("dassdl3", SDL_MODULE_ROOT);
    access->addFsRoot("dasrmlui", UI_MODULE_ROOT);
    access->addFsRoot("examples", std::string(UI_MODULE_ROOT) + "/../examples");
    auto program = compileDaScript(path, access, out, modules);
    auto errors = [&] { for (auto& e : program->errors) out << reportError(e.at,e.what,e.extra,e.fixme,e.cerr); };
    if (program->failed()) { errors(); return 1; }
    Context context(program->getContextStackSize());
    if (!program->simulate(context, out)) { errors(); return 2; }
    auto fn = context.findFunction("main");
    if (!fn || !verifyCall<int32_t,bool>(fn->debugInfo,modules)) {
        out << "Expected [export] def main(smoke : bool) : int\n"; return 3;
    }
    vec4f args[] = {cast<bool>::from(smoke)};
    auto result = context.evalWithCatch(fn,args);
    if (auto ex = context.getException()) { out << "Script exception: " << ex << "\n"; return 4; }
    return cast<int32_t>::to(result);
}
int main(int argc, char** argv) {
    if (argc < 2) return 2;
    SDL_SetMainReady(); das::setDasRoot(DAS_ROOT);
    NEED_ALL_DEFAULT_MODULES; NEED_MODULE(Module_dasSDL3); NEED_MODULE(Module_dasRmlUi);
    das::Module::Initialize();
    int code = run(argv[1], argc > 2 && !strcmp(argv[2], "--smoke-test"));
    rui_shutdown(); SDL_Quit(); das::Module::Shutdown(); return code;
}
