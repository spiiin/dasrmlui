#include "bundle_scripts.h"

#define SDL_MAIN_USE_CALLBACKS 1
#include <SDL3/SDL_main.h>

DECLARE_MODULE(Module_dasSDL3);
DECLARE_MODULE(Module_dasRmlUi);
DECLARE_MODULE(Module_LiveHost);

MAKE_TYPE_FACTORY(SDL_Window, SDL_Window);
MAKE_TYPE_FACTORY(SDL_Renderer, SDL_Renderer);
MAKE_TYPE_FACTORY(SDL_Event, SDL_Event);

void rui_shutdown();
void rui_set_default_font(const char* path);
const char* rui_last_native_error();

namespace {
struct App {
    SDL_Window* window = nullptr;
    SDL_Renderer* renderer = nullptr;
    das::ModuleGroup modules;
    das::ProgramPtr program;
    std::unique_ptr<das::Context> context;
    das::SimFunction* frame = nullptr;
    das::SimFunction* event = nullptr;
    SDL_AtomicInt active{};
    bool smoke = false;
    bool native_lab = false;
    bool first_frame = true;
    das::SimFunction* select_name = nullptr;
    Uint64 keyboard_step_time = 0;
    int keyboard_step = 0;
    bool keyboard_hidden = false;
    bool frame_verified = false;
};

bool loadExample(App& app, const das::string& root) {
    using namespace das;
    setDasRoot(root.substr(0, root.size() - 1));
    rui_set_default_font((root + "assets/LatoLatin-Regular.ttf").c_str());
    auto access = make_smart<dassdl3_ios::BundleAccess>();
    access->addFileSystem(new dassdl3_ios::BundleScripts(root), true, false);
    access->addFsRoot("dasrmlui", root + "dasrmlui");
    access->addFsRoot("examples", root + "examples");
    access->addFsRoot("dassdl3", root + "dassdl3");
    TextWriter diagnostics;
    const char* script = app.native_lab ? "ios/native_lab.das" : "ios/inventory.das";
    app.program = compileDaScript(root + script, access, diagnostics, app.modules);
    if (!app.program->failed()) {
        app.context = std::make_unique<Context>(app.program->getContextStackSize());
        if (app.program->simulate(*app.context, diagnostics)) return true;
    }
    for (const auto& error : app.program->errors)
        diagnostics << reportError(error.at, error.what, error.extra, error.fixme, error.cerr);
    SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "%s", diagnostics.str().c_str());
    return false;
}

das::SimFunction* getEntry(App& app, const char* name) {
    auto* function = app.context->findFunction(name);
    if (!function) SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "Missing script entry %s", name);
    return function;
}

bool call(App& app, das::SimFunction* function, vec4f* args, vec4f& result) {
    app.context->restart();
    result = app.context->evalWithCatch(function, args);
    const char* error = app.context->getException();
    if (!error) error = rui_last_native_error();
    if (!error) return true;
    SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "%s: %s", function->name, error);
    return false;
}

bool sendText(App& app, const char* text) {
    SDL_Event event{};
    event.type = SDL_EVENT_TEXT_INPUT;
    event.text.windowID = SDL_GetWindowID(app.window);
    event.text.text = text;
    vec4f args[] = {das::cast<const SDL_Event*>::from(&event)};
    vec4f result;
    return call(app, app.event, args, result);
}

bool hasExamplePixels(SDL_Renderer* renderer, bool native_lab) {
    std::unique_ptr<SDL_Surface, decltype(&SDL_DestroySurface)> pixels(
        SDL_RenderReadPixels(renderer, nullptr), SDL_DestroySurface);
    if (!pixels) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "Capture frame: %s", SDL_GetError());
        return false;
    }
    for (int y = 0; y < pixels->h; y += 2) {
        for (int x = 0; x < pixels->w; x += 2) {
            Uint8 r, g, b, a;
            if (!SDL_ReadSurfacePixel(pixels.get(), x, y, &r, &g, &b, &a)) continue;
            if (native_lab ? (r > 240 && g > 170 && g < 220 && b < 105)
                           : (r > 180 && g > 180 && b > 180)) return true;
        }
    }
    SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "Expected content is missing from the rendered frame");
    return false;
}
}

SDL_AppResult SDL_AppInit(void** state, int argc, char** argv) {
    using namespace das;
    auto* app = new App;
    *state = app;
    for (int i = 1; i < argc; ++i) {
        if (SDL_strcmp(argv[i], "--smoke-test") == 0) app->smoke = true;
        if (SDL_strcmp(argv[i], "--native-lab") == 0) app->native_lab = true;
    }
    const char* title = app->native_lab ? "dasrmlui Native Lab" : "dasrmlui Inventory";
    SDL_SetAtomicInt(&app->active, 1);
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "1");
    NEED_ALL_DEFAULT_MODULES;
    NEED_MODULE(Module_dasSDL3);
    NEED_MODULE(Module_dasRmlUi);
    NEED_MODULE(Module_LiveHost);
    Module::Initialize();
    if (!SDL_Init(SDL_INIT_VIDEO) ||
        !SDL_CreateWindowAndRenderer(title, 800, 390, 0, &app->window, &app->renderer)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "Create example window: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }
    const char* root = SDL_GetBasePath();
    if (!root || !loadExample(*app, root)) return SDL_APP_FAILURE;
    auto* start = getEntry(*app, "app_start");
    app->event = getEntry(*app, "app_event");
    app->frame = getEntry(*app, "app_frame");
    if (!start || !app->event || !app->frame ||
        !verifyCall<bool, SDL_Window*, SDL_Renderer*, const char*>(start->debugInfo, app->modules) ||
        !verifyCall<void, const SDL_Event&>(app->event->debugInfo, app->modules) ||
        !verifyCall<bool, bool>(app->frame->debugInfo, app->modules)) return SDL_APP_FAILURE;
    if (app->smoke && !app->native_lab) {
        app->select_name = getEntry(*app, "inventory_select_name");
        if (!app->select_name || !verifyCall<void>(app->select_name->debugInfo, app->modules))
            return SDL_APP_FAILURE;
    }
    const string fallback_font = string(root) + "assets/DejaVuSans.ttf";
    vec4f args[] = {cast<SDL_Window*>::from(app->window), cast<SDL_Renderer*>::from(app->renderer),
                    cast<const char*>::from(fallback_font.c_str())};
    vec4f result;
    if (!call(*app, start, args, result) || !cast<bool>::to(result)) return SDL_APP_FAILURE;
    SDL_Log("%s ready (%s)", title, SDL_GetRendererName(app->renderer));
    return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppIterate(void* state) {
    using namespace das;
    auto& app = *static_cast<App*>(state);
    if (!SDL_GetAtomicInt(&app.active)) return SDL_APP_CONTINUE;
    const Uint64 now = SDL_GetTicks();
    if (app.smoke && !app.native_lab) {
        if (app.keyboard_step > 0 && (app.keyboard_hidden || !SDL_TextInputActive(app.window))) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "Keyboard closed while editing Inventory");
            return SDL_APP_FAILURE;
        }
        if (app.keyboard_step == 0 && SDL_TextInputActive(app.window) &&
            SDL_ScreenKeyboardShown(app.window)) {
            vec4f result;
            if (!call(app, app.select_name, nullptr, result) || !sendText(app, "A")) return SDL_APP_FAILURE;
            app.keyboard_step = 1;
            app.keyboard_step_time = now;
        } else if (app.keyboard_step == 1 && now - app.keyboard_step_time >= 350) {
            if (!sendText(app, "Привет")) return SDL_APP_FAILURE;
            app.keyboard_step = 2;
            app.keyboard_step_time = now;
        }
    }
    if (!SDL_SetRenderDrawColor(app.renderer, 8, 12, 20, 255) || !SDL_RenderClear(app.renderer)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "Clear example frame: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }
    vec4f args[] = {cast<bool>::from(app.smoke)};
    vec4f result;
    if (!call(app, app.frame, args, result)) return SDL_APP_FAILURE;
    const bool done = cast<bool>::to(result);
    if (done && !app.frame_verified) {
        if (!hasExamplePixels(app.renderer, app.native_lab)) return SDL_APP_FAILURE;
        app.frame_verified = true;
    }
    if (!SDL_RenderPresent(app.renderer)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "Present example frame: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }
    if (app.first_frame) {
        SDL_Log("dasrmlui %s first frame presented", app.native_lab ? "Native Lab" : "Inventory");
        app.first_frame = false;
    }
    if (app.native_lab && done) {
        SDL_Log("dasrmlui Native Lab control input and waveform pixels PASS");
        return SDL_APP_SUCCESS;
    }
    if (!app.native_lab && app.frame_verified && now - app.keyboard_step_time >= 500) {
        if (!SDL_ScreenKeyboardShown(app.window)) return SDL_APP_FAILURE;
        SDL_Log("dasrmlui Inventory interaction, Cyrillic text, rendered pixels and stable keyboard PASS");
        return SDL_APP_SUCCESS;
    }
    return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppEvent(void* state, SDL_Event* event) {
    if (!SDL_IsMainThread()) return SDL_APP_CONTINUE;
    auto& app = *static_cast<App*>(state);
    switch (event->type) {
    case SDL_EVENT_QUIT: return SDL_APP_SUCCESS;
    case SDL_EVENT_SCREEN_KEYBOARD_HIDDEN:
        if (app.keyboard_step > 0) app.keyboard_hidden = true;
        return SDL_APP_CONTINUE;
    case SDL_EVENT_WILL_ENTER_BACKGROUND: SDL_SetAtomicInt(&app.active, 0); return SDL_APP_CONTINUE;
    case SDL_EVENT_DID_ENTER_FOREGROUND: SDL_SetAtomicInt(&app.active, 1); return SDL_APP_CONTINUE;
    default: break;
    }
    // Only window input events enter the VM. Some SDL events are pushed off-thread.
    switch (event->type) {
    case SDL_EVENT_MOUSE_MOTION:
    case SDL_EVENT_MOUSE_BUTTON_DOWN:
    case SDL_EVENT_MOUSE_BUTTON_UP:
    case SDL_EVENT_MOUSE_WHEEL:
    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_KEY_UP:
    case SDL_EVENT_TEXT_INPUT:
    case SDL_EVENT_TEXT_EDITING:
    case SDL_EVENT_WINDOW_FOCUS_LOST:
    case SDL_EVENT_WINDOW_MOUSE_LEAVE:
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
    case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED: break;
    default: return SDL_APP_CONTINUE;
    }
    if (!app.event || !SDL_GetAtomicInt(&app.active)) return SDL_APP_CONTINUE;
    vec4f args[] = {das::cast<const SDL_Event*>::from(event)};
    vec4f result;
    return call(app, app.event, args, result) ? SDL_APP_CONTINUE : SDL_APP_FAILURE;
}

void SDL_AppQuit(void* state, SDL_AppResult) {
    std::unique_ptr<App> app(static_cast<App*>(state));
    rui_shutdown();
    if (app) {
        app->context.reset();
        SDL_DestroyRenderer(app->renderer);
        SDL_DestroyWindow(app->window);
    }
    app.reset();
    das::Module::Shutdown();
    SDL_Quit();
}
