#include "script_access.h"
#include "live_host.h"

#include <SDL3/SDL_main.h>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string_view>

DECLARE_MODULE(Module_dasSDL3);
DECLARE_MODULE(Module_dasRmlUi);
DECLARE_MODULE(Module_LiveHost);

void rui_shutdown();
void rui_live_close();
const char* rui_last_native_error();
void rui_set_default_font(const char* path);
void rui_set_screenshot_directory(const char* path);

namespace {
int run(const std::string& script, const std::string& root, bool smoke) {
    using namespace das;
    ModuleGroup modules;
    TextWriter diagnostics;
    auto access = ios_script_access(root.c_str());
    for (const char* folder : {"dassdl3", "dasrmlui", "examples"})
        access->addFsRoot(folder, (root + folder).c_str());
    access->addFsRoot("glsl", (root + "modules/dasGlsl/glsl").c_str());
    access->addFsRoot("live", (root + "modules/dasLiveHost/live").c_str());
    auto program = compileDaScript(script.c_str(), access, diagnostics, modules);
    auto report = [&] {
        for (const auto& error : program->errors)
            diagnostics << reportError(error.at, error.what, error.extra, error.fixme, error.cerr);
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "%s", diagnostics.str().c_str());
        return 1;
    };
    if (program->failed()) return report();
    Context context(program->getContextStackSize());
    struct UiLifetime { ~UiLifetime() { rui_shutdown(); } } ui_lifetime;
    if (!program->simulate(context, diagnostics)) return report();
    auto* entry = context.findFunction("main");
    if (!entry || !verifyCall<int32_t, bool>(entry->debugInfo, modules)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "Expected [export] def main(smoke:bool):int");
        return 1;
    }
    vec4f args[] = {cast<bool>::from(smoke)};
    const auto result = context.evalWithCatch(entry, args);
    rui_shutdown();
    const char* error = context.getException();
    if (!error) error = rui_last_native_error();
    if (error) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "%s", error);
        return 1;
    }
    return cast<int32_t>::to(result);
}
}

int main(int argc, char** argv) {
    std::string_view example = "inventory";
    bool smoke = false;
    for (int i = 1; i < argc; ++i) {
        const std::string_view arg = argv[i];
        if (arg == "--smoke-test") smoke = true;
        else if (arg == "--example" && i+1 < argc) example = argv[++i];
        else if (arg == "--native-lab") example = "native_lab";
    }
    const char* base = SDL_GetBasePath();
    if (!base || example.empty() || example.find_first_not_of("abcdefghijklmnopqrstuvwxyz_0123456789") != std::string_view::npos)
        return 1;
    const std::string root(base);
    std::error_code error;
    std::filesystem::current_path(root, error);
    if (error) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "Cannot open app resources: %s", error.message().c_str());
        return 1;
    }
    if (smoke) {
        std::unique_ptr<char, decltype(&SDL_free)> pref(SDL_GetPrefPath("dasrmlui", "Examples"), SDL_free);
        if (!pref) return 1;
        std::filesystem::create_directories(std::filesystem::path(pref.get()) / "logs", error);
        if (error) return 1;
        rui_set_screenshot_directory(pref.get());
    }
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "1");
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    das::setDasRoot(root.substr(0, root.size() - 1).c_str());
    rui_set_default_font((root + "assets/LatoLatin-Regular.ttf").c_str());
    NEED_ALL_DEFAULT_MODULES;
    NEED_MODULE(Module_dasSDL3);
    NEED_MODULE(Module_dasRmlUi);
    NEED_MODULE(Module_LiveHost);
    das::Module::Initialize();
    const std::string script = root + "examples/" + std::string(example) + ".das";
    const int result = example == "live_lab"
        ? run_ui_live(script.c_str(), (root + "examples/live_lab_styles.das").c_str(),
            root, root+"dassdl3", root+"dasrmlui", root+"examples", smoke, smoke ? 8 : 0)
        : run(script, root, smoke);
    rui_shutdown();
    rui_live_close();
    SDL_Quit();
    das::Module::Shutdown();
    SDL_Log("dasrmlui example %s exited with code %d", std::string(example).c_str(), result);
    if (smoke) std::exit(result); // SDL's UIKit delegate otherwise keeps the process alive.
    return result;
}
