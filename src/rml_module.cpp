// RmlUi bindings for daScript: the SDL_Renderer bridge, element handles and the event queue.
#include "daScript/daScript.h"
#include "dasLiveHost.h"
#include "daScript/ast/ast_interop.h"
#include <RmlUi/Core.h>
#include <RmlUi/Debugger.h>
#include <RmlUi/SVG/ElementSVG.h>
#include <RmlUi/Lottie/ElementLottie.h>
#include <RmlUi/Core/Elements/ElementFormControlInput.h>
#include <RmlUi/Core/Elements/ElementFormControlSelect.h>
#include <RmlUi/Core/Elements/ElementTabSet.h>
#include <RmlUi/Core/ComputedValues.h>
#include <RmlUi/Core/StyleSheet.h>
#include <RmlUi/Core/StyleSheetSpecification.h>
#include <RmlUi/Core/Geometry.h>
#include <RmlUi/Core/RenderManager.h>
#include <RmlUi/Core/ElementUtilities.h>
#include <RmlUi/Core/Decorator.h>
#include <RmlUi/Core/PropertyDefinition.h>
#include <RmlUi/Core/RenderBox.h>
#include <RmlUi/Core/Filter.h>
#include <RmlUi/Core/MeshUtilities.h>
#include <algorithm>
#include "RmlUi_Platform_SDL.h"
#include "gl3/RmlUi_Renderer_GL3.h"
#ifdef __EMSCRIPTEN__
#include <GLES3/gl3.h>
#include <emscripten.h>
#else
#include "RmlUi_Include_GL3.h"
#endif
#include <SDL3/SDL.h>
#include <deque>
#include <unordered_map>
#include <unordered_set>
#include <memory>
#include <string>
#include <vector>
#include <cstdio>
#include <cmath>
#include <DataModel.h>
#include <DataView.h>
#include <RmlUi/Core/DataVariable.h>
#ifdef DASRMLUI_BENCHMARK
#include "benchmark_alloc.h"
#include <DataModel.h> // Pinned RmlUi internal API, benchmark-only phase separation.
#include <chrono>
#include <fstream>
#endif
MAKE_TYPE_FACTORY(SDL_Window, SDL_Window);
MAKE_TYPE_FACTORY(SDL_Renderer, SDL_Renderer);
MAKE_TYPE_FACTORY(SDL_Event, SDL_Event);
namespace {
#ifdef DASRMLUI_BENCHMARK
bool bench_defer_update=false;
#endif
struct Geometry { std::vector<SDL_Vertex> verts; std::vector<int> indices; };

class RenderInterface_SDLRenderer : public Rml::RenderInterface {
public:
    SDL_Renderer * r = nullptr;
    bool scissor = false;
    SDL_Rect rect{};

    Rml::CompiledGeometryHandle CompileGeometry(Rml::Span<const Rml::Vertex> vertices, Rml::Span<const int> indices) override {
        auto g = new Geometry();
        g->verts.resize(vertices.size());
        for (size_t i = 0; i < vertices.size(); ++i) {
            const auto & v = vertices[i];
            // colors are premultiplied; the premultiplied blend mode expects that
            g->verts[i] = { {v.position.x, v.position.y},
                            {v.colour.red / 255.f, v.colour.green / 255.f, v.colour.blue / 255.f, v.colour.alpha / 255.f},
                            {v.tex_coord.x, v.tex_coord.y} };
        }
        g->indices.assign(indices.begin(), indices.end());
        return (Rml::CompiledGeometryHandle)g;
    }
    void RenderGeometry(Rml::CompiledGeometryHandle handle, Rml::Vector2f t, Rml::TextureHandle texture) override {
        auto g = (Geometry *)handle;
        std::vector<SDL_Vertex> v = g->verts;
        for (auto & x : v) { x.position.x += t.x; x.position.y += t.y; }
        SDL_Texture * tex = (SDL_Texture *)texture;
        SDL_RenderGeometry(r, tex, v.data(), (int)v.size(), g->indices.data(), (int)g->indices.size());
    }
    void ReleaseGeometry(Rml::CompiledGeometryHandle handle) override { delete (Geometry *)handle; }

    Rml::TextureHandle LoadTexture(Rml::Vector2i & dims, const Rml::String & source) override {
        SDL_Surface * s = SDL_LoadPNG(source.c_str());
        if (!s) { SDL_Log("rmlui: can not load %s", source.c_str()); return 0; }
        SDL_Surface * c = SDL_ConvertSurface(s, SDL_PIXELFORMAT_ABGR8888);
        SDL_DestroySurface(s);
        if (!c) return 0;
        SDL_PremultiplySurfaceAlpha(c, false);
        dims = { c->w, c->h };
        SDL_Texture * tex = SDL_CreateTextureFromSurface(r, c);
        SDL_DestroySurface(c);
        if (tex) SDL_SetTextureBlendMode(tex, SDL_BLENDMODE_BLEND_PREMULTIPLIED);
        return (Rml::TextureHandle)tex;
    }
    Rml::TextureHandle GenerateTexture(Rml::Span<const Rml::byte> source, Rml::Vector2i dims) override {
        SDL_Texture * tex = SDL_CreateTexture(r, SDL_PIXELFORMAT_ABGR8888, SDL_TEXTUREACCESS_STATIC, dims.x, dims.y);
        if (!tex) return 0;
        SDL_UpdateTexture(tex, nullptr, source.data(), dims.x * 4);
        SDL_SetTextureBlendMode(tex, SDL_BLENDMODE_BLEND_PREMULTIPLIED);
        SDL_SetTextureScaleMode(tex, SDL_SCALEMODE_LINEAR);
        return (Rml::TextureHandle)tex;
    }
    void ReleaseTexture(Rml::TextureHandle texture) override { SDL_DestroyTexture((SDL_Texture *)texture); }

    void EnableScissorRegion(bool enable) override {
        scissor = enable;
        SDL_SetRenderClipRect(r, enable ? &rect : nullptr);
    }
    void SetScissorRegion(Rml::Rectanglei region) override {
        rect = { region.Left(), region.Top(), region.Width(), region.Height() };
        if (scissor) SDL_SetRenderClipRect(r, &rect);
    }
};


struct UiEvent {
    uint64_t node; std::string type, value; uint64_t generation=0;
    uint64_t listener=0,target=0,source=0;
    int phase=0,key=0,modifiers=0,button=-1;
    bool interruptible=false;
    Rml::Vector2f mouse{},screen{},wheel{};
    std::vector<std::pair<std::string,std::string>> parameters;
};
struct UiAnimation {
    uint64_t generation=0;
    std::string name,easing;
    float duration=0;
    int iterations=1,status=0; // stopped, queued, running, finished, invalid
    bool alternate=false;
    std::unordered_set<std::string> remaining;
};
// Template resources can live in daScript strings. Open handles own their data,
// so replacing a resource cannot invalidate an in-flight parser read.
class UiFiles : public Rml::FileInterface {
    struct File { FILE* disk=nullptr; std::string data; size_t position=0; };
public:
    std::unordered_map<std::string,std::string> resources;
    Rml::FileHandle Open(const Rml::String& path) override {
        auto file=std::make_unique<File>();
        auto it=resources.find(path);
        if (it!=resources.end()) file->data=it->second;
        else if (!(file->disk=std::fopen(path.c_str(),"rb"))) return 0;
        return reinterpret_cast<Rml::FileHandle>(file.release());
    }
    void Close(Rml::FileHandle handle) override { auto f=reinterpret_cast<File*>(handle); if(f->disk) std::fclose(f->disk); delete f; }
    size_t Read(void* buffer,size_t size,Rml::FileHandle handle) override {
        auto f=reinterpret_cast<File*>(handle);
        if(f->disk) return std::fread(buffer,1,size,f->disk);
        size=std::min(size,f->data.size()-f->position);
        if(size) std::memcpy(buffer,f->data.data()+f->position,size);
        f->position+=size; return size;
    }
    bool Seek(Rml::FileHandle handle,long offset,int origin) override {
        auto f=reinterpret_cast<File*>(handle);
        if(f->disk) return std::fseek(f->disk,offset,origin)==0;
        if(origin!=SEEK_SET && origin!=SEEK_CUR && origin!=SEEK_END) return false;
        const int64_t position=(origin==SEEK_SET ? 0 : int64_t(origin==SEEK_CUR ? f->position : f->data.size()))+offset;
        if(position<0 || uint64_t(position)>f->data.size()) return false;
        f->position=size_t(position); return true;
    }
    size_t Tell(Rml::FileHandle handle) override { auto f=reinterpret_cast<File*>(handle); return f->disk ? size_t(std::ftell(f->disk)) : f->position; }
};
class UiSystem : public SystemInterface_SDL {
public:
    using SystemInterface_SDL::SystemInterface_SDL;
    bool test_clock=false;
    double test_time=0;
    double GetElapsedTime() override { return test_clock ? test_time : SystemInterface_SDL::GetElapsedTime(); }
    // The default Windows logger writes to the debugger only, so a mistyped
    // property or selector would pass without any visible diagnostic.
    uint64_t problems=0;
    bool LogMessage(Rml::Log::Type type,const Rml::String& message) override {
        const char* level = type==Rml::Log::LT_ERROR ? "error" : type==Rml::Log::LT_ASSERT ? "assert" :
            type==Rml::Log::LT_WARNING ? "warning" : nullptr;
        if(!level) return true;
        ++problems;
        std::printf("rmlui %s: %s\n",level,message.c_str()); std::fflush(stdout);
        return true;
    }
    std::unordered_map<std::string,std::unordered_map<std::string,std::string>> translations;
    std::string locale="en";
    uint64_t revision=0;
    int TranslateString(Rml::String& output,const Rml::String& input) override {
        output.clear(); size_t start=0; int count=0;
        while(start<input.size()) {
            const size_t left=input.find('[',start);
            if(left==std::string::npos) { output+=input.substr(start); break; }
            output+=input.substr(start,left-start);
            const size_t right=input.find(']',left+1);
            if(right==std::string::npos) { output+=input.substr(left); break; }
            const auto key=input.substr(left+1,right-left-1);
            const std::string* value=nullptr;
            for(const auto& language : {locale,std::string("en")}) {
                auto catalog=translations.find(language);
                if(catalog==translations.end()) continue;
                auto it=catalog->second.find(key);
                if(it!=catalog->second.end()) { value=&it->second; break; }
            }
            if(value) { output+=*value; ++count; } else output+=input.substr(left,right-left+1);
            start=right+1;
        }
        return count;
    }
};
class RenderInterface_Advanced : public RenderInterface_GL3 {
public:
    Rml::TextureHandle LoadTexture(Rml::Vector2i& dims, const Rml::String& source) override {
        SDL_Surface* original=SDL_LoadPNG(source.c_str());
        if (!original) { SDL_Log("rmlui: cannot load PNG %s: %s",source.c_str(),SDL_GetError()); return 0; }
        SDL_Surface* surface=SDL_ConvertSurface(original,SDL_PIXELFORMAT_RGBA32);
        SDL_DestroySurface(original);
        if (!surface) return 0;
        SDL_PremultiplySurfaceAlpha(surface,false);
        dims={surface->w,surface->h};
        std::vector<Rml::byte> pixels(size_t(dims.x)*dims.y*4);
        for (int y=0;y<dims.y;++y) memcpy(pixels.data()+size_t(y)*dims.x*4,(char*)surface->pixels+y*surface->pitch,size_t(dims.x)*4);
        SDL_DestroySurface(surface);
        return GenerateTexture({pixels.data(),pixels.size()},dims);
    }
};
struct State;
class ScriptInstancer;
class ScriptElement;
class ScriptDecoratorInstancer;
struct GpuDefinition;
class QueueListener : public Rml::EventListener {
public: void ProcessEvent(Rml::Event& event) override;
};
class RichListener : public Rml::EventListener {
public:
    uint64_t token=0,host=0;
    Rml::ObserverPtr<Rml::Element> element;
    std::string type,key;
    bool capture=false,stop=false,immediate=false;
    int modifiers=-1;
    void ProcessEvent(Rml::Event& event) override;
    ~RichListener() { if(element) element->RemoveEventListener(type,this,capture); }
};
struct DocumentState { uint64_t return_focus=0; bool popup=false; Rml::Vector2f position{}; };
struct State {
    std::unordered_map<std::string,std::unique_ptr<ScriptInstancer>> native_types;
    std::unordered_map<uint64_t,ScriptElement*> native_nodes;
    std::unordered_map<std::string,std::unique_ptr<ScriptDecoratorInstancer>> decorator_types;
    // Parsed RCSS can retain raw instancer/property-definition pointers.
    std::vector<std::unique_ptr<ScriptDecoratorInstancer>> retired_decorator_types;
    std::unordered_map<std::string,std::unique_ptr<GpuDefinition>> gpu_effects;
    std::vector<std::unique_ptr<GpuDefinition>> retired_gpu_effects;
    bool debugger_ready=false, debugger_key_down=false;
    SDL_Keycode debugger_key=SDLK_UNKNOWN;
    uint64_t debugger_revision=0, debugger_return_focus=0;
    std::unordered_map<uint64_t,std::unique_ptr<RichListener>> listeners;
    std::unordered_map<uint64_t,DocumentState> documents;
    std::vector<uint64_t> popups;
    uint32_t swallowed_buttons=0;
    float display_scale=1.f, ui_scale=1.f;
    uint64_t style_revision=0;
    std::string selected_theme;
    std::unordered_map<uint64_t,UiAnimation> animations;
    uint64_t animation_serial=0;
    std::unique_ptr<UiSystem> system;
    UiFiles files;
    std::string css;
    std::unordered_map<uint64_t,Rml::SharedPtr<Rml::StyleSheetContainer>> document_styles;
    TextInputMethodEditor_SDL ime;
    bool composing = false;
    RenderInterface_SDLRenderer render;
    std::unique_ptr<RenderInterface_Advanced> advanced;
    bool gl_loaded=false;
    bool gl_clear=true; // rui_render clears the GL frame unless the host draws its own scene first
    Rml::Context* context = nullptr;
    Rml::ElementDocument* document = nullptr;
    SDL_Window* window = nullptr;
    QueueListener listener;
    std::unordered_map<uint64_t, Rml::ObserverPtr<Rml::Element>> nodes;
    std::unordered_map<Rml::Element*, uint64_t> ids;
    std::deque<UiEvent> events;
    UiEvent current{};
    bool applying = false;
    bool stale = false; // rui_remove ran: sweep entries of elements RmlUi released by itself
    std::unordered_map<uint64_t, std::unordered_map<std::string,std::string>> properties;
};
std::unique_ptr<State> state;
uint64_t next_id = 1; // Never reused, including after restarting a UI context.
uint64_t next_listener = 1;
Rml::Element* node(uint64_t id) {
    if (!state) return nullptr;
    auto it = state->nodes.find(id);
    return it == state->nodes.end() ? nullptr : it->second.get();
}
uint64_t remember(Rml::Element* element) {
    if (!element) return 0;
    auto old=state->ids.find(element);
    if(old!=state->ids.end() && node(old->second)==element) return old->second;
    auto id = next_id++;
    state->nodes.emplace(id, element->GetObserverPtr());
    state->ids[element] = id;
    element->SetAttribute("data-rui-id", Rml::String(std::to_string(id)));
    return id;
}
#include "native_elements.inc"
#include "native_decorators.inc"
#include "gpu_effects.inc"
void listen_document(Rml::ElementDocument* document, bool attach) {
    for(const char* type : {"click","change","tabchange","dragdrop","dragover","dragout","keydown","blur","animationend","transitionend"}) {
        const bool capture=!strcmp(type,"keydown") || !strcmp(type,"blur");
        if(attach) document->AddEventListener(type,&state->listener,capture);
        else document->RemoveEventListener(type,&state->listener,capture);
    }
}
bool element_enabled(Rml::Element* element) {
    if (!element) return false;
    for (auto e = element; e; e = e->GetParentNode())
        if (e->HasAttribute("disabled")) return false;
    return true;
}
bool inside(Rml::Element* root,Rml::Element* child) {
    for(auto e=child;e;e=e->GetParentNode()) if(e==root) return true;
    return false;
}
bool debugger_element(Rml::Element* element) {
    auto document=element ? element->GetOwnerDocument() : nullptr;
    return document && document->GetId().compare(0,12,"rmlui-debug-")==0;
}
bool input_event(const std::string& type) {
    return type=="click" || type=="dblclick" || type=="change" || type=="submit" || type=="tabchange" ||
        type=="textinput" || type.compare(0,3,"key")==0 || type.compare(0,5,"mouse")==0 || type.compare(0,4,"drag")==0;
}
bool event_allowed(uint64_t id,const std::string& type) {
    auto e=node(id);
    if(!element_enabled(e)) return false;
    if(!input_event(type)) return true;
    if(!e->IsVisible(true)) return false;
    auto focus=state->context->GetFocusElement();
    auto modal=focus ? focus->GetOwnerDocument() : nullptr;
    return !modal || !modal->IsModal() || e->GetOwnerDocument()==modal;
}
std::string key_name(int key) {
    using namespace Rml::Input;
    if(key>=KI_A && key<=KI_Z) return std::string(1,char('A'+key-KI_A));
    if(key>=KI_0 && key<=KI_9) return std::string(1,char('0'+key-KI_0));
    if(key>=KI_F1 && key<=KI_F24) return "F"+std::to_string(key-KI_F1+1);
    switch(key) {
    case KI_RETURN: return "Enter"; case KI_NUMPADENTER: return "NumpadEnter";
    case KI_ESCAPE: return "Escape"; case KI_TAB:return "Tab"; case KI_SPACE:return "Space";
    case KI_LEFT:return "Left"; case KI_RIGHT:return "Right"; case KI_UP:return "Up"; case KI_DOWN:return "Down";
    case KI_BACK:return "Backspace"; case KI_DELETE:return "Delete"; case KI_HOME:return "Home";
    case KI_END:return "End"; case KI_PRIOR:return "PageUp"; case KI_NEXT:return "PageDown"; case KI_INSERT:return "Insert";
    default:return "";
    }
}
void RichListener::ProcessEvent(Rml::Event& event) {
    if(!state || state->applying || !event_allowed(host,event.GetType()) ||
       !event_allowed(remember(event.GetTargetElement()),event.GetType())) return;
    const int code=event.GetParameter<int>("key_identifier",0);
    int mods=0,bit=1;
    for(const char* name:{"ctrl_key","shift_key","alt_key","meta_key","caps_lock_key","num_lock_key","scroll_lock_key"}) {
        if(event.GetParameter<int>(name,0)) mods|=bit;
        bit<<=1;
    }
    if((!key.empty() && key_name(code)!=key) || (modifiers>=0 && (mods&15)!=modifiers)) return;
    UiEvent copy{host,event.GetType(),event.GetParameter<Rml::String>("value","")};
    copy.listener=token; copy.target=remember(event.GetTargetElement()); copy.phase=int(event.GetPhase());
    copy.key=code; copy.modifiers=mods; copy.interruptible=event.IsInterruptible();
    copy.mouse={event.GetParameter<float>("mouse_x",0),event.GetParameter<float>("mouse_y",0)};
    copy.screen=event.GetUnprojectedMouseScreenPos();
    copy.wheel={event.GetParameter<float>("wheel_delta_x",0),event.GetParameter<float>("wheel_delta_y",0)};
    copy.button=event.GetParameter<int>("button",-1);
    if(auto source=static_cast<Rml::Element*>(event.GetParameter<void*>("drag_element",nullptr))) copy.source=remember(source);
    for(const auto& parameter:event.GetParameters()) {
        // Never retain a native pointer (or a Variant owning native resources).
        const auto type=parameter.second.GetType();
        if(type==Rml::Variant::BOOL || type==Rml::Variant::BYTE || type==Rml::Variant::CHAR ||
           type==Rml::Variant::INT || type==Rml::Variant::INT64 || type==Rml::Variant::UINT || type==Rml::Variant::UINT64 ||
           type==Rml::Variant::FLOAT || type==Rml::Variant::DOUBLE || type==Rml::Variant::STRING ||
           type==Rml::Variant::VECTOR2 || type==Rml::Variant::VECTOR3 || type==Rml::Variant::VECTOR4 ||
           type==Rml::Variant::COLOURF || type==Rml::Variant::COLOURB) {
            Rml::String value;
            if(parameter.second.GetInto(value)) copy.parameters.emplace_back(parameter.first,std::move(value));
        }
    }
    state->events.push_back(std::move(copy));
    // RmlUi couples propagation and default actions. Cancellation must happen
    // during native dispatch, before the later daScript reconciliation pass.
    if(immediate) event.StopImmediatePropagation(); else if(stop) event.StopPropagation();
}
void focus_candidates(Rml::Element* root, std::vector<Rml::Element*>& out) {
    if (!root || !root->IsVisible(true) || !element_enabled(root)) return;
    if (root->GetComputedValues().tab_index() == Rml::Style::TabIndex::Auto &&
        root->GetComputedValues().focus() == Rml::Style::Focus::Auto) out.push_back(root);
    for (int i=0;i<root->GetNumChildren();++i) focus_candidates(root->GetChild(i),out);
}
void focus_cycle(Rml::Element* scope, bool reverse) {
    std::vector<Rml::Element*> candidates;
    focus_candidates(scope,candidates);
    if (candidates.empty()) return;
    auto it = std::find(candidates.begin(),candidates.end(),state->context->GetFocusElement());
    int index = it == candidates.end() ? (reverse ? 0 : -1) : int(it-candidates.begin());
    index = (index + (reverse ? -1 : 1) + int(candidates.size())) % int(candidates.size());
    candidates[index]->Focus();
    candidates[index]->ScrollIntoView();
}
void QueueListener::ProcessEvent(Rml::Event& event) {
    if (!state || state->applying) return;
    const auto type = event.GetType();
    if(type=="animationend") {
        auto id=state->ids.find(event.GetTargetElement());
        if(id==state->ids.end()) return;
        auto it=state->animations.find(id->second);
        if(it==state->animations.end() || it->second.status!=2) return;
        auto& animation=it->second;
        animation.remaining.erase(event.GetParameter<Rml::String>("property",""));
        if(animation.remaining.empty()) {
            animation.status=3;
            if(event.GetTargetElement()->HasAttribute("data-rui-watch-animation_done"))
                state->events.push_back({id->second,"animation_done",animation.name,animation.generation});
        }
        return;
    }
    if (!element_enabled(event.GetTargetElement())) return;
    if (type == "dragover" || type == "dragout" || type == "dragdrop") {
        for (auto e=event.GetTargetElement();e;e=e->GetParentNode()) {
            if (e->HasAttribute("data-rui-watch-dragdrop")) { e->SetPseudoClass("drop",type=="dragover"); break; }
        }
        if (type != "dragdrop") return;
    }
    for (auto e = event.GetTargetElement(); e; e = e->GetParentNode()) {
        if (e->HasAttribute("data-rui-watch-" + type)) {
            auto it = state->ids.find(e);
            Rml::String value = event.GetParameter<Rml::String>("value", "");
            if (type == "tabchange") value = std::to_string(event.GetParameter<int>("tab_index",0));
            if (type == "transitionend") value = event.GetParameter<Rml::String>("property", "");
            if (type == "dragdrop") {
                auto source=static_cast<Rml::Element*>(event.GetParameter<void*>("drag_element",nullptr));
                if (!element_enabled(source)) return;
                value=source->GetAttribute<Rml::String>("data-rui-payload","");
                if (value.empty()) return;
            }
            if (type == "change" && e->GetAttribute<Rml::String>("type","") == "checkbox") value = e->HasAttribute("checked") ? "true" : "false";
            if (type == "keydown") {
                const int key = event.GetParameter<int>("key_identifier",0);
                switch (key) {
                case Rml::Input::KI_RETURN: case Rml::Input::KI_NUMPADENTER: value="Enter"; break;
                case Rml::Input::KI_ESCAPE: value="Escape"; break;
                case Rml::Input::KI_TAB: value="Tab"; break;
                case Rml::Input::KI_UP: value="Up"; break;
                case Rml::Input::KI_DOWN: value="Down"; break;
                case Rml::Input::KI_SPACE: value="Space"; break;
                // on_key knows only the names above. Queuing any other key would
                // cost a dispatch pass and a reconcile and reach no handler.
                default: return;
                }
            }
            if (it != state->ids.end()) state->events.push_back({it->second, type, value});
            break;
        }
    }
}
char* str(const std::string& value, das::Context* ctx, das::LineInfoArg* at) {
    return ctx->allocateString(value.c_str(), uint64_t(value.size()), at);
}
#include "data_models.inc"
#include "hybrid.inc"
}
void rui_shutdown() { native_guard();
    if (!state) return;
    rui_hybrid_reset();
    data_shutdown();
    state->listeners.clear();
    state->nodes.clear();
    state->document_styles.clear();
    if(state->context) for(int i=0;i<state->context->GetNumDocuments();++i) listen_document(state->context->GetDocument(i),false);
    const bool gl_loaded=state->gl_loaded;
    Rml::Shutdown();
    // Release rooted daScript handlers only after every native element died.
    for(auto& type:state->native_types) type.second->Call(0,NativeRelease);
    for(auto& type:state->decorator_types) type.second->Call(nullptr,NativeRelease);
    state.reset();
    if (gl_loaded) RmlGL3::Shutdown();
}
const char* rui_last_native_error() { return native_error.empty() ? nullptr : native_error.c_str(); }
static bool rui_init_backend(SDL_Window* window, SDL_Renderer* renderer, int width, int height, bool advanced) { native_guard();
    if (state || !window || (!renderer && !advanced)) return false;
    native_error.clear();
    state = std::make_unique<State>(); state->window = window;
    state->system = std::make_unique<UiSystem>(window);
    state->render.r = renderer;
    if (advanced) {
        Rml::String message;
        if (!RmlGL3::Initialize(&message)) { SDL_Log("RmlUi GL3: %s",message.c_str()); state.reset(); return false; }
        state->gl_loaded=true;
        state->advanced=std::make_unique<RenderInterface_Advanced>();
        if (!*state->advanced) { state.reset(); RmlGL3::Shutdown(); return false; }
        state->advanced->SetViewport(width,height);
    }
    Rml::SetSystemInterface(state->system.get());
    Rml::SetFileInterface(&state->files);
    Rml::SetRenderInterface(advanced ? static_cast<Rml::RenderInterface*>(state->advanced.get()) : &state->render);
    Rml::SetTextInputHandler(&state->ime);
    if (!Rml::Initialise()) { state.reset(); if (advanced) RmlGL3::Shutdown(); return false; }
    state->context = Rml::CreateContext("dasrmlui", {width, height});
    if (!state->context) { rui_shutdown(); return false; }
    int pixel_width=0,pixel_height=0;
    if(SDL_GetWindowSizeInPixels(window,&pixel_width,&pixel_height) && pixel_width>0 && pixel_height>0)
        state->context->SetDimensions({pixel_width,pixel_height});
    state->display_scale=SDL_GetWindowDisplayScale(window);
    if(!std::isfinite(state->display_scale) || state->display_scale<=0) state->display_scale=1.f;
    state->context->SetDensityIndependentPixelRatio(state->display_scale);
    state->document = state->context->CreateDocument();
    listen_document(state->document,true);
    state->document->Show();
    remember(state->document);
    return true;
}
static bool rui_init(SDL_Window* window, SDL_Renderer* renderer, int width, int height) { return rui_init_backend(window,renderer,width,height,false); }
static bool rui_init_gl(SDL_Window* window, int width, int height) { return rui_init_backend(window,nullptr,width,height,true); }
static uint64_t rui_root() {
    if (!state) return 0;
    return state->ids.at(state->document);
}
static bool rui_debugger_init() { native_guard();
    if(!state) return false;
    if(state->debugger_ready) return true;
    if(!Rml::Debugger::Initialise(state->context)) return false;
    state->debugger_ready=true;
    ++state->debugger_revision;
    return true;
}
static bool rui_debugger_ready() { return state && state->debugger_ready; }
static bool rui_debugger_visible() { return rui_debugger_ready() && Rml::Debugger::IsVisible(); }
static uint64_t rui_debugger_revision() { return state ? state->debugger_revision : 0; }
static bool rui_debugger_show(bool visible) { native_guard();
    if(!state || (visible && !rui_debugger_init())) return false;
    if(!state->debugger_ready) return true;
    const bool was_visible=rui_debugger_visible();
    if(visible && !rui_debugger_visible()) {
        auto focus=state->context->GetFocusElement();
        if(!debugger_element(focus)) state->debugger_return_focus=remember(focus);
    }
    if(!visible) {
        // Upstream SetVisible hides only the toolbar. Our hide action also closes
        // inspector windows (which otherwise keep intercepting application clicks).
        auto menu=state->context->GetDocument("rmlui-debug-menu");
        auto outlines=menu ? menu->GetElementById("outlines-button") : nullptr;
        if(outlines && outlines->IsClassSet("open")) outlines->Click();
        const bool restore=debugger_element(state->context->GetFocusElement());
        for(int i=0;i<state->context->GetNumDocuments();++i) {
            auto doc=state->context->GetDocument(i);
            if(debugger_element(doc) && doc->GetId()!="rmlui-debug-hook" && doc->IsVisible()) doc->Hide();
        }
        if(restore) if(auto focus=node(state->debugger_return_focus))
            if(focus->IsVisible(true) && element_enabled(focus)) focus->Focus();
    }
    Rml::Debugger::SetVisible(visible);
    if(was_visible!=visible) ++state->debugger_revision;
    return true;
}
static void rui_debugger_shutdown() { native_guard();
    if(!state) return;
    state->debugger_key=SDLK_UNKNOWN;
    if(!state->debugger_ready) return;
    rui_debugger_show(false);
    Rml::Debugger::Shutdown();
    state->debugger_ready=false;
    ++state->debugger_revision;
}
static bool rui_debugger_hotkey(const char* name) { native_guard();
    if(!state) return false;
    const auto key=(!name || !*name) ? SDLK_UNKNOWN : SDL_GetKeyFromName(name);
    if(name && *name && key==SDLK_UNKNOWN) return false;
    state->debugger_key=key; return true;
}
// Test access to upstream UI, kept separate from the DSL's owned documents.
static uint64_t rui_test_debugger_document(const char* name) {
    if(!rui_debugger_ready()) return 0;
    return remember(state->context->GetDocument(std::string("rmlui-debug-")+name));
}
static bool rui_debugger_models() { native_guard();
    if(!rui_debugger_show(true)) return false;
    auto document=state->context->GetDocument("rmlui-debug-data-models");
    if(!document) return false;
    // Show directly: the Debugger's Show listener keeps its toolbar in sync.
    // A synthetic click can be intercepted by the element inspector.
    document->Show();
    return true;
}
static int rui_test_document_count() { return state ? state->context->GetNumDocuments() : 0; }
static bool rui_has_class(uint64_t id,const char* name) { auto e=node(id); return e && e->IsClassSet(name); }
static bool rui_font(const char* path) { native_guard(); return state && Rml::LoadFontFace(path); }
static bool rui_fallback_font(const char* path) { native_guard(); return state && Rml::LoadFontFace(path,true); }
static void rui_resource(const char* path,const char* content) { native_guard(); if(state) state->files.resources[path]=content; }
static void document_css(uint64_t id) {
    auto document=rmlui_dynamic_cast<Rml::ElementDocument*>(node(id));
    if(!document || state->css.empty()) return;
    auto sheet=Rml::Factory::InstanceStyleSheetString(state->css);
    const auto base=state->document_styles.find(id);
    if(base!=state->document_styles.end() && base->second) sheet=sheet->CombineStyleSheetContainer(*base->second);
    document->SetStyleSheetContainer(std::move(sheet));
}
static uint64_t rui_document_load(const char* markup,const char* source,bool visible) { native_guard();
    if(!state) return 0;
    auto document=state->context->LoadDocumentFromMemory(markup,source);
    if(!document) return 0;
    const auto id=remember(document);
    auto base=std::make_shared<Rml::StyleSheetContainer>();
    if(auto sheet=document->GetStyleSheetContainer()) base->MergeStyleSheetContainer(*sheet);
    state->document_styles[id]=std::move(base);
    document_css(id); listen_document(document,true);
    if(visible) document->Show();
    return id;
}
static uint64_t rui_document(const char* markup,const char* source) { return rui_document_load(markup,source,true); }
static uint64_t rui_document_file(const char* path,bool visible) { native_guard();
    if(!state) return 0;
    auto document=state->context->LoadDocument(path);
    if(!document) return 0;
    const auto id=remember(document);
    auto base=std::make_shared<Rml::StyleSheetContainer>();
    if(auto sheet=document->GetStyleSheetContainer()) base->MergeStyleSheetContainer(*sheet);
    state->document_styles[id]=std::move(base);
    document_css(id); listen_document(document,true);
    if(visible) document->Show();
    return id;
}
static void rui_show_document(uint64_t id,int modal,int focus,bool scroll) { native_guard();
    auto doc=rmlui_dynamic_cast<Rml::ElementDocument*>(node(id));
    if(!doc || modal<0 || modal>2 || focus<0 || focus>3) return;
    auto& entry=state->documents[id];
    if(!doc->IsVisible()) entry.return_focus=remember(state->context->GetFocusElement());
    doc->Show(Rml::ModalFlag(modal),Rml::FocusFlag(focus),scroll ? Rml::ScrollFlag::Auto : Rml::ScrollFlag::None);
}
static void rui_hide_document(uint64_t id) { native_guard();
    auto doc=rmlui_dynamic_cast<Rml::ElementDocument*>(node(id));
    if(!doc) return;
    const bool restore=inside(doc,state->context->GetFocusElement());
    doc->Hide();
    auto it=state->documents.find(id);
    if(it!=state->documents.end()) {
        it->second.popup=false;
        if(restore) if(auto previous=node(it->second.return_focus))
            if(previous->IsVisible(true) && element_enabled(previous)) previous->Focus();
    }
    auto& popups=state->popups;
    popups.erase(std::remove(popups.begin(),popups.end(),id),popups.end());
}
static bool rui_document_modal(uint64_t id) {
    auto doc=rmlui_dynamic_cast<Rml::ElementDocument*>(node(id)); return doc && doc->IsModal();
}
static void rui_document_front(uint64_t id,bool front) { native_guard();
    if(auto doc=rmlui_dynamic_cast<Rml::ElementDocument*>(node(id))) { if(front) doc->PullToFront(); else doc->PushToBack(); }
}
static void rui_focus_next(uint64_t id,bool reverse) { native_guard(); focus_cycle(node(id),reverse); }
static void rui_document_position(uint64_t id,float x,float y) { native_guard();
    if(auto doc=rmlui_dynamic_cast<Rml::ElementDocument*>(node(id))) {
        doc->SetProperty("left",std::to_string(x)+"px"); doc->SetProperty("top",std::to_string(y)+"px");
        state->properties[id].erase("left"); state->properties[id].erase("top");
    }
}
static void clamp_popups() {
    for(auto id:state->popups) {
        auto doc=rmlui_dynamic_cast<Rml::ElementDocument*>(node(id)); if(!doc) continue;
        const auto size=doc->GetBox().GetSize(Rml::BoxArea::Border);
        const auto viewport=state->context->GetDimensions();
        const auto position=state->documents[id].position;
        const auto actual=doc->GetAbsoluteOffset(Rml::BoxArea::Border);
        const Rml::Vector2f desired{std::clamp(position.x,0.f,std::max(0.f,float(viewport.x)-size.x)),
                                  std::clamp(position.y,0.f,std::max(0.f,float(viewport.y)-size.y))};
        if(actual!=desired) rui_document_position(id,desired.x,desired.y);
    }
}
static bool rui_show_popup(uint64_t id,float x,float y) { native_guard();
    auto doc=rmlui_dynamic_cast<Rml::ElementDocument*>(node(id)); if(!doc) return false;
    // A popup takes modal focus too, so it can be opened from a native dialog.
    auto& entry=state->documents[id]; entry.position={x,y}; entry.popup=true;
    if(std::find(state->popups.begin(),state->popups.end(),id)==state->popups.end()) state->popups.push_back(id);
    rui_document_position(id,x,y); rui_show_document(id,1,3,false); doc->PullToFront();
    state->context->Update(); clamp_popups(); state->context->Update(); return true;
}
static void dismiss_popup(uint64_t id,const char* reason) {
    rui_hide_document(id);
    if(auto doc=node(id)) { Rml::Dictionary parameters; parameters["reason"]=Rml::String(reason); doc->DispatchEvent("dismiss",parameters); }
}
static uint64_t rui_document_element(uint64_t id,const char* name) {
    auto document=rmlui_dynamic_cast<Rml::ElementDocument*>(node(id));
    return document ? remember(document->GetElementById(name)) : 0;
}
static void rui_close_document(uint64_t id) { native_guard();
    auto document=rmlui_dynamic_cast<Rml::ElementDocument*>(node(id));
    if(!document || document==state->document) return;
    rui_hide_document(id);
    state->documents.erase(id);
    for(auto it=state->listeners.begin();it!=state->listeners.end();) {
        if(inside(document,it->second->element.get())) it=state->listeners.erase(it); else ++it;
    }
    listen_document(document,false); state->document_styles.erase(id);
    for(auto it=state->nodes.begin();it!=state->nodes.end();) {
        auto element=it->second.get();
        if(!element || element==document || element->GetOwnerDocument()==document) {
            state->ids.erase(element); state->properties.erase(it->first); it=state->nodes.erase(it);
        } else ++it;
    }
    document->Close();
}
static void rui_translation(const char* language,const char* key,const char* value) { native_guard();
    if(!state) return;
    auto& catalog=state->system->translations[language];
    auto it=catalog.find(key);
    if(it!=catalog.end() && it->second==value) return;
    catalog[key]=value; ++state->system->revision;
}
static void rui_set_locale(const char* language) { native_guard();
    if(state && state->system->locale!=language) { state->system->locale=language; ++state->system->revision; }
}
static uint64_t rui_locale_revision() { return state ? state->system->revision : 0; }
static char* rui_locale(das::Context* ctx,das::LineInfoArg* at) { return str(state ? state->system->locale : "en",ctx,at); }
static char* rui_translate(const char* text,das::Context* ctx,das::LineInfoArg* at) {
    Rml::String output=text; if(state) state->system->TranslateString(output,text); return str(output,ctx,at);
}
static std::string live_extra_css, live_base_css;
static void rui_css(const char* css) { native_guard();
    if (state) {
        live_base_css=css;
        state->css=live_base_css+live_extra_css;
        state->document->SetStyleSheetContainer(Rml::Factory::InstanceStyleSheetString(state->css));
        for(const auto& entry : state->document_styles) document_css(entry.first);
    }
}
static uint64_t rui_create(uint64_t parent, const char* tag, const char* classes, const char* input_type) { native_guard();
    auto p = node(parent); if (!p) return 0;
    // Tabsets lazily create their structural groups. Adopt those elements rather
    // than appending a second tabs/panels pair that the native widget would ignore.
    if (rmlui_dynamic_cast<Rml::ElementTabSet*>(p) && (!strcmp(tag,"tabs") || !strcmp(tag,"panels"))) {
        for (int i=0;i<p->GetNumChildren();++i) {
            auto e=p->GetChild(i);
            if (e->GetTagName() == tag) {
                e->SetClassNames(classes ? classes : "");
                auto it=state->ids.find(e);
                return it == state->ids.end() ? remember(e) : it->second;
            }
        }
    }
    Rml::XMLAttributes attrs;
    if (input_type && *input_type) attrs["type"] = Rml::String(input_type);
    auto e = Rml::Factory::InstanceElement(p, tag, tag, attrs);
    if (!e) return 0;
    e->SetClassNames(classes ? classes : "");
    if (!strcmp(tag,"input") && input_type && *input_type) e->SetClass(input_type,true);
    if (strcmp(tag,"button") == 0 || strcmp(tag,"tab") == 0) e->SetProperty("tab-index","auto");
    auto raw = p->AppendChild(std::move(e));
    return remember(raw);
}
static bool rui_alive(uint64_t id) { return node(id) != nullptr; }
static bool rui_enabled(uint64_t id) { return element_enabled(node(id)); }
static void collect_ids(Rml::Element* e, std::vector<std::pair<Rml::Element*,uint64_t>>& out) {
    auto it = state->ids.find(e);
    if (it != state->ids.end()) out.emplace_back(e,it->second);
    for (int i=0;i<e->GetNumChildren(true);++i) collect_ids(e->GetChild(i),out);
}
// Entries of elements that RmlUi released without rui_remove: options of a
// select, the inside of a replaced document. One pass per update, not per node.
static void sweep_released() {
    for (auto it = state->nodes.begin(); it != state->nodes.end();) {
        if (!it->second) { state->properties.erase(it->first); it = state->nodes.erase(it); } else ++it;
    }
    for (auto it = state->ids.begin(); it != state->ids.end();) {
        if (!node(it->second)) it = state->ids.erase(it); else ++it;
    }
    state->stale = false;
}
static void rui_remove(uint64_t id) { native_guard();
    auto e = node(id); if (!e || e == state->document) return;
    hybrid_forget(e);
    // Forget exactly the subtree that goes away. Sweeping every table on each
    // call made clearing a list quadratic: a second for four thousand rows.
    std::vector<std::pair<Rml::Element*,uint64_t>> gone;
    collect_ids(e,gone);
    if (auto p = e->GetParentNode()) p->RemoveChild(e).reset();
    for (const auto& entry : gone) {
        auto it = state->nodes.find(entry.second);
        if (it == state->nodes.end() || it->second) continue; // still referenced elsewhere
        state->properties.erase(entry.second); state->nodes.erase(it); state->ids.erase(entry.first);
    }
    state->stale = true;
}
static void rui_before(uint64_t id, uint64_t before) { native_guard();
    auto e = node(id); if (!e) return;
    auto p = e->GetParentNode(); auto b = node(before);
    if (!p || (b && b->GetParentNode() != p) || e == b) return;
    if (e->GetNextSibling() == b) return;
    auto focus = state->context->GetFocusElement();
    bool restore = focus && (focus == e || e->Contains(focus));
    if (restore && state->composing) return; // Retry next frame after IME commit.
    auto observer = restore ? focus->GetObserverPtr() : Rml::ObserverPtr<Rml::Element>{};
    int selection_start = 0, selection_end = 0;
    auto input = restore ? rmlui_dynamic_cast<Rml::ElementFormControlInput*>(focus) : nullptr;
    if (input) input->GetSelection(&selection_start,&selection_end,nullptr);
    auto owned = p->RemoveChild(e);
    if (b) p->InsertBefore(std::move(owned), b); else p->AppendChild(std::move(owned));
    if (observer) observer->Focus();
    if (input && observer) input->SetSelectionRange(selection_start,selection_end);
}
static void rui_text(uint64_t id, const char* text) { native_guard();
    auto e = node(id); if (!e) return;
    const Rml::String value = text ? text : "";
    // The caption is the element's own text node. Never clear the element to
    // set it: a button also holds DSL children created after its caption.
    Rml::ElementText* caption = nullptr;
    for (int i=0;i<e->GetNumChildren() && !caption;++i) caption = rmlui_dynamic_cast<Rml::ElementText*>(e->GetChild(i));
    if (!caption) {
        auto created = e->GetOwnerDocument()->CreateTextNode(value);
        if (auto first = e->GetFirstChild()) e->InsertBefore(std::move(created),first);
        else e->AppendChild(std::move(created));
    } else if (caption->GetText() != value) caption->SetText(value);
}
static void rui_property(uint64_t id, const char* name, const char* value) { native_guard();
    if (auto e = node(id)) {
        auto& props = state->properties[id];
        auto it = props.find(name);
        if (it == props.end() || it->second != value) {
            // RmlUi reports the rejected declaration; name the element as well.
            // Remember the value either way so it is not retried every pass.
            if (!e->SetProperty(name, value)) {
                std::printf("  on <%s class=\"%s\">\n",e->GetTagName().c_str(),e->GetClassNames().c_str()); std::fflush(stdout);
            }
            props[name] = value;
        }
    }
}
static void rui_class(uint64_t id, const char* name, bool enabled) { native_guard(); if (auto e = node(id)) e->SetClass(name,enabled); }
static uint64_t rui_warning_count() { return state ? state->system->problems : 0; }
static void rui_attr(uint64_t id, const char* name, const char* value) { native_guard();
    if (auto e = node(id)) {
        const auto desired=Rml::String(value);
        if (e->HasAttribute(name) && e->GetAttribute<Rml::String>(name,"") == desired) return;
        const bool previous=state->applying;
        state->applying=true; e->SetAttribute(name,desired); state->applying=previous;
    }
}
static int rui_active_tab(uint64_t id) {
    auto e=rmlui_dynamic_cast<Rml::ElementTabSet*>(node(id)); return e ? e->GetActiveTab() : -1;
}
static void rui_set_tab(uint64_t id, int index) { native_guard();
    if (auto e=rmlui_dynamic_cast<Rml::ElementTabSet*>(node(id))) {
        if (index<0 || index>=e->GetNumTabs()) return;
        const bool previous=state->applying;
        state->applying=true; e->SetActiveTab(index); state->applying=previous;
    }
}
static bool rui_visible(uint64_t id) { auto e=node(id); return e && e->IsVisible(true); }
static char* rui_get_attr(uint64_t id, const char* name, das::Context* ctx, das::LineInfoArg* at) {
    auto e=node(id); return str(e ? e->GetAttribute<Rml::String>(name,"") : "",ctx,at);
}
static void rui_attr_if(uint64_t id, const char* name, bool enabled) { native_guard();
    if (auto e = node(id)) {
        const bool previous_applying = state->applying;
        state->applying = true;
        if (enabled) e->SetAttribute(name, Rml::String()); else e->RemoveAttribute(name);
        // DSL buttons can contain arbitrary child elements, so they are generic
        // RmlUi elements rather than <input type=button>. Mirror form-control
        // disabled behavior for those elements as well.
        if (std::string(name) == "disabled" && !rmlui_dynamic_cast<Rml::ElementFormControl*>(e)) {
            e->SetPseudoClass("disabled", enabled);
            if (enabled) {
                e->SetProperty("focus", "none");
                auto focused=state->context->GetFocusElement();
                for (auto ancestor=focused; ancestor; ancestor=ancestor->GetParentNode()) {
                    if (ancestor==e) { focused->Blur(); break; }
                }
            }
            else e->RemoveProperty("focus");
        }
        state->applying = previous_applying;
    }
}
static bool rui_has_attr(uint64_t id, const char* name) {
    auto e=node(id); return e && e->HasAttribute(name);
}
static int rui_vector_kind(uint64_t id) {
    auto e=node(id);
    return rmlui_dynamic_cast<Rml::ElementSVG*>(e) ? 1 : rmlui_dynamic_cast<Rml::ElementLottie*>(e) ? 2 : 0;
}
static das::float2 rui_intrinsic_size(uint64_t id) {
    Rml::Vector2f size{}; float ratio=0;
    if(auto e=node(id)) e->GetIntrinsicDimensions(size,ratio);
    return {size.x,size.y};
}
static void rui_svg_inline(uint64_t id,const char* fragment,float width,float height,bool crop) { native_guard();
    auto e=rmlui_dynamic_cast<Rml::ElementSVG*>(node(id)); if(!e) return;
    // Native SetInnerRML always invalidates the SVG cache. Reapply only when the
    // source or SVG viewport changes, not on unrelated component updates.
    Rml::String previous; e->GetInnerRML(previous);
    const bool changed=previous!=fragment || !e->GetAttribute<Rml::String>("src","").empty() ||
        e->GetAttribute<float>("width",0)!=width || e->GetAttribute<float>("height",0)!=height;
    rui_attr(id,"src",""); rui_attr_if(id,"crop-to-content",crop);
    if(!changed) return;
    rui_attr(id,"xmlns","http://www.w3.org/2000/svg");
    const auto w=std::to_string(width),h=std::to_string(height);
    rui_attr(id,"width",w.c_str()); rui_attr(id,"height",h.c_str());
    rui_attr(id,"viewBox",("0 0 "+w+" "+h).c_str());
    e->SetInnerRML(fragment);
    // Native SetInnerRML does not invalidate layout. SetAttribute notifies the
    // SVG element even when width is unchanged, invoking its layout invalidation.
    e->SetAttribute("width", width);
}
static void rui_value(uint64_t id, const char* value) { native_guard();
    if (!value) value = "";
    auto e = rmlui_dynamic_cast<Rml::ElementFormControl*>(node(id));
    if (!e || e->GetValue() == value) return;
    if (state->composing && state->context->GetFocusElement() == e) return;
    state->applying = true; e->SetValue(value); state->applying = false;
}
static char* rui_get_value(uint64_t id, das::Context* ctx, das::LineInfoArg* at) {
    auto e = rmlui_dynamic_cast<Rml::ElementFormControl*>(node(id));
    return str(e ? e->GetValue() : "", ctx, at);
}
static void rui_watch(uint64_t id, const char* type) { native_guard();
    auto e = node(id); if (!e) return;
    // Handlers declare their watch on every update pass, and setting an
    // attribute, even to the same value, dirties the element's style definition.
    const auto name = Rml::String("data-rui-watch-") + type;
    if (!e->HasAttribute(name)) e->SetAttribute(name, true);
}
static void rui_pseudo(uint64_t id, const char* name, bool value) { native_guard(); if (auto e=node(id)) e->SetPseudoClass(name,value); }
static bool rui_checked(uint64_t id) { auto e=node(id); return e && e->HasAttribute("checked"); }
static void rui_options_clear(uint64_t id) { native_guard();
    if (auto e=rmlui_dynamic_cast<Rml::ElementFormControlSelect*>(node(id))) {
        state->applying=true; e->RemoveAll(); state->applying=false;
    }
}
static void rui_option(uint64_t id, const char* caption, const char* value) { native_guard();
    if (auto e=rmlui_dynamic_cast<Rml::ElementFormControlSelect*>(node(id))) {
        state->applying=true; e->Add(Rml::StringUtilities::EncodeRml(caption),value); state->applying=false;
    }
}
static float rui_width() { return state ? float(state->context->GetDimensions().x) : 0.f; }
static float rui_height() { return state ? float(state->context->GetDimensions().y) : 0.f; }
static uint64_t rui_style_revision() { return state ? state->style_revision : 0; }
static float rui_dp_ratio() { return state ? state->context->GetDensityIndependentPixelRatio() : 1.f; }
static float rui_ui_scale() { return state ? state->ui_scale : 1.f; }
static void update_density(float display_scale) {
    if(!state || !std::isfinite(display_scale) || display_scale<=0) return;
    const float ratio=display_scale*state->ui_scale;
    if(!std::isfinite(ratio) || ratio<=0) return;
    state->display_scale=display_scale;
    if(state->context->GetDensityIndependentPixelRatio()!=ratio) {
        state->context->SetDensityIndependentPixelRatio(ratio); ++state->style_revision;
    }
}
static bool rui_set_ui_scale(float scale) { native_guard();
    if(!state || !std::isfinite(scale) || scale<=0 || !std::isfinite(scale*state->display_scale) || scale*state->display_scale<=0) return false;
    if(state->ui_scale!=scale) { state->ui_scale=scale; update_density(state->display_scale); }
    return true;
}
static bool rui_theme_active(const char* name) { return state && state->context->IsThemeActive(name); }
static void rui_activate_theme(const char* name,bool active) { native_guard();
    if(!state || !name || !*name || rui_theme_active(name)==active) return;
    state->context->ActivateTheme(name,active); ++state->style_revision;
}
static void rui_set_theme(const char* name) { native_guard();
    if(!state || !name) return;
    if(state->selected_theme!=name) {
        rui_activate_theme(state->selected_theme.c_str(),false);
        state->selected_theme=name;
        ++state->style_revision; // Selection can change even when the flag was already active.
    }
    rui_activate_theme(name,true);
}
static char* rui_theme(das::Context* ctx,das::LineInfoArg* at) { return str(state ? state->selected_theme : "",ctx,at); }
static void rui_test_display_scale(float scale) { native_guard(); update_density(scale); }
static float rui_scroll_top(uint64_t id) { auto e=node(id); return e ? e->GetScrollTop() : 0.f; }
static void rui_scroll_to(uint64_t id, float y) { native_guard(); if (auto e=node(id)) e->SetScrollTop(y); }
static void rui_test_resize(int width, int height) { if (state) { native_guard(); SDL_SetWindowSize(state->window,width,height); state->context->SetDimensions({width,height}); } }
static void rui_event(const SDL_Event& event) { native_guard();
    if (!state) return;
    SDL_Event ev = event;
    if((ev.type==SDL_EVENT_KEY_DOWN || ev.type==SDL_EVENT_KEY_UP) && state->debugger_key!=SDLK_UNKNOWN &&
       ev.key.key==state->debugger_key && ev.key.windowID==SDL_GetWindowID(state->window)) {
        if(ev.type==SDL_EVENT_KEY_DOWN) {
            if(!ev.key.repeat && !state->debugger_key_down) rui_debugger_show(!rui_debugger_visible());
            state->debugger_key_down=true;
        } else state->debugger_key_down=false;
        return; // Consume both halves, so F8 is not also delivered to the app.
    }
    if(ev.type==SDL_EVENT_WINDOW_FOCUS_LOST) state->debugger_key_down=false;
    // Keep the release paired with a consumed outside press from reaching a control.
    if(ev.type==SDL_EVENT_MOUSE_BUTTON_UP && (state->swallowed_buttons & SDL_BUTTON_MASK(ev.button.button))) {
        state->swallowed_buttons &= ~SDL_BUTTON_MASK(ev.button.button); return;
    }
    if(!state->popups.empty()) {
        const auto id=state->popups.back();
        if(ev.type==SDL_EVENT_KEY_DOWN && ev.key.key==SDLK_ESCAPE && !debugger_element(state->context->GetFocusElement())) { dismiss_popup(id,"escape"); return; }
        if(ev.type==SDL_EVENT_MOUSE_BUTTON_DOWN) {
            const float density=SDL_GetWindowPixelDensity(state->window);
            auto hit=state->context->GetElementAtPoint({ev.button.x*density,ev.button.y*density});
            if(!inside(node(id),hit) && !debugger_element(hit)) {
                state->swallowed_buttons |= SDL_BUTTON_MASK(ev.button.button);
                dismiss_popup(id,"outside"); return;
            }
        }
    }
    if(ev.type==SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED) {
        if(ev.window.windowID==SDL_GetWindowID(state->window)) update_density(SDL_GetWindowDisplayScale(state->window));
        return; // Keep the user scale multiplier; SDL's default handler sets only the display scale.
    }
    if (ev.type == SDL_EVENT_KEY_DOWN && ev.key.key == SDLK_TAB) {
        for (auto e=state->context->GetFocusElement(); e; e=e->GetParentNode()) {
            if (e->HasAttribute("data-rui-focus-scope")) { focus_cycle(e,(ev.key.mod & SDL_KMOD_SHIFT)!=0); return; }
        }
    }
    if (ev.type == SDL_EVENT_TEXT_EDITING) {
        state->composing = ev.edit.text && ev.edit.text[0];
        state->ime.HandleEdit(ev.edit);
        return;
    }
    if (ev.type == SDL_EVENT_TEXT_INPUT || ev.type == SDL_EVENT_WINDOW_FOCUS_LOST) state->composing = false;
    if (ev.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED) state->context->SetDimensions({ev.window.data1, ev.window.data2});
    RmlSDL::InputEventHandler(state->context, state->window, ev);
}
static bool rui_next_event() { native_guard();
    if (!state) return false;
    while (!state->events.empty()) {
        state->current = std::move(state->events.front()); state->events.pop_front();
        if(state->current.type=="animation_done") {
            auto it=state->animations.find(state->current.node);
            if(it==state->animations.end() || it->second.generation!=state->current.generation || it->second.status!=3) continue;
        }
        if(state->current.listener && (state->listeners.find(state->current.listener)==state->listeners.end() ||
            !event_allowed(state->current.target,state->current.type))) continue;
        if (event_allowed(state->current.node,state->current.type)) return true;
    }
    return false;
}
static uint64_t rui_event_node() { return state->current.node; }
static char* rui_event_type(das::Context* ctx, das::LineInfoArg* at) { return str(state->current.type,ctx,at); }
static char* rui_event_value(das::Context* ctx, das::LineInfoArg* at) { return str(state->current.value,ctx,at); }
static uint64_t rui_event_generation() { return state ? state->current.generation : 0; }
static uint64_t rui_listen(uint64_t id,const char* type,bool capture,bool stop,bool immediate,const char* key,int modifiers) { native_guard();
    auto element=node(id); if(!element) return 0;
    auto listener=std::make_unique<RichListener>();
    listener->token=next_listener++; listener->host=id; listener->element=element->GetObserverPtr();
    listener->type=type; listener->capture=capture; listener->stop=stop; listener->immediate=immediate;
    listener->key=key; listener->modifiers=modifiers;
    const auto token=listener->token;
    element->AddEventListener(type,listener.get(),capture);
    state->listeners.emplace(token,std::move(listener)); return token;
}
static void rui_unlisten(uint64_t token) { native_guard(); if(state) state->listeners.erase(token); }
static uint64_t rui_relisten(uint64_t token,uint64_t id,const char* type,bool capture,bool stop,bool immediate,const char* key,int modifiers) { native_guard();
    if(state) {
        auto it=state->listeners.find(token);
        if(it!=state->listeners.end()) {
            auto& listener=*it->second;
            if(listener.element && listener.host==id && listener.type==type && listener.capture==capture) {
                // Preserve same-node listener order when declarative options change.
                // A fresh token invalidates snapshots made with the old options.
                listener.stop=stop; listener.immediate=immediate; listener.key=key; listener.modifiers=modifiers;
                listener.token=next_listener++;
                const auto next=listener.token;
                auto entry=state->listeners.extract(it); entry.key()=next; state->listeners.insert(std::move(entry));
                return next;
            }
        }
    }
    rui_unlisten(token); return rui_listen(id,type,capture,stop,immediate,key,modifiers);
}
static bool rui_listener_alive(uint64_t token) {
    if(!state) return false;
    auto it=state->listeners.find(token); return it!=state->listeners.end() && it->second->element;
}
static int rui_listener_count() { return state ? int(state->listeners.size()) : 0; }
static bool rui_event_allowed(uint64_t id,const char* type) { return event_allowed(id,type); }
static uint64_t rui_event_listener() { return state->current.listener; }
static uint64_t rui_event_target() { return state->current.target; }
static uint64_t rui_event_source() { return state->current.source; }
static int rui_event_phase() { return state->current.phase; }
static int rui_event_key_code() { return state->current.key; }
static char* rui_event_key(das::Context* ctx,das::LineInfoArg* at) { return str(key_name(state->current.key),ctx,at); }
static int rui_event_modifiers() { return state->current.modifiers; }
static int rui_event_button() { return state->current.button; }
static bool rui_event_interruptible() { return state->current.interruptible; }
static das::float2 rui_event_mouse() { const auto p=state->current.mouse; return {p.x,p.y}; }
static das::float2 rui_event_screen() { const auto p=state->current.screen; return {p.x,p.y}; }
static das::float2 rui_event_wheel() { const auto p=state->current.wheel; return {p.x,p.y}; }
static int rui_event_parameter_count() { return int(state->current.parameters.size()); }
static char* rui_event_parameter_name(int index,das::Context* ctx,das::LineInfoArg* at) {
    return str(index>=0 && index<int(state->current.parameters.size()) ? state->current.parameters[index].first : "",ctx,at);
}
static char* rui_event_parameter_value(int index,das::Context* ctx,das::LineInfoArg* at) {
    return str(index>=0 && index<int(state->current.parameters.size()) ? state->current.parameters[index].second : "",ctx,at);
}
static uint64_t rui_animation_start(uint64_t id,const char* name,float seconds,const char* easing,int iterations,bool alternate) { native_guard();
    if(!node(id) || seconds<=0 || (iterations<1 && iterations!=-1)) return 0;
    UiAnimation animation;
    animation.generation=++state->animation_serial; animation.name=name; animation.duration=seconds;
    animation.easing=easing; animation.iterations=iterations; animation.alternate=alternate; animation.status=1;
    state->animations[id]=std::move(animation);
    return state->animation_serial;
}
static void rui_animation_cancel(uint64_t id) { native_guard();
    if(auto e=node(id)) {
        state->animations.erase(id);
        e->SetProperty("animation","none"); state->properties[id].erase("animation");
    }
}
static int rui_animation_status(uint64_t id) {
    if(!state || !node(id)) return 0;
    auto it=state->animations.find(id); return it==state->animations.end() ? 0 : it->second.status;
}
static uint64_t rui_animation_generation(uint64_t id) {
    if(!state) return 0;
    auto it=state->animations.find(id); return it==state->animations.end() ? 0 : it->second.generation;
}
static void rui_test_advance_time(double seconds) { native_guard();
    if(!state || seconds<0) return;
    auto& clock=*state->system;
    if(!clock.test_clock) { clock.test_time=clock.GetElapsedTime(); clock.test_clock=true; }
    clock.test_time+=seconds;
}
static void rui_update() { native_guard();
#ifdef DASRMLUI_BENCHMARK
    if(bench_defer_update) return;
#endif
    if(!state) return;
    if(state->stale) sweep_released();
    for(auto it=state->listeners.begin();it!=state->listeners.end();) {
        if(!it->second->element) it=state->listeners.erase(it); else ++it;
    }
    bool starting=false;
    for(auto it=state->animations.begin();it!=state->animations.end();) {
        auto e=node(it->first);
        if(!e) { it=state->animations.erase(it); continue; }
        if(it->second.status==1) {
            starting=true; e->SetProperty("animation","none"); state->properties[it->first].erase("animation");
        }
        ++it;
    }
    // Flush cancellation and compile the final stylesheet before resolving keys.
    // A second Update starts all queued animations together, including replays.
    state->context->Update();
    if(!state->popups.empty()) { clamp_popups(); state->context->Update(); }
    if(!starting) return;
    for(auto& entry : state->animations) {
        auto& animation=entry.second;
        auto e=node(entry.first);
        if(!e || animation.status!=1) continue;
        const auto sheet=e->GetStyleSheet();
        const auto keys=sheet ? sheet->GetKeyframes(animation.name) : nullptr;
        if(!keys || keys->property_ids.empty()) { animation.status=4; continue; }
        // A rejected native key never emits animationend. Reject unsupported
        // values before starting so an exiting subtree cannot wait forever.
        const auto units=Rml::Unit::NUMBER_LENGTH_PERCENT | Rml::Unit::ANGLE | Rml::Unit::COLOUR |
            Rml::Unit::TRANSFORM | Rml::Unit::KEYWORD | Rml::Unit::DECORATOR | Rml::Unit::FILTER;
        bool supported=true;
        for(const auto& block : keys->blocks)
            for(const auto& property : block.properties.GetProperties())
                supported = supported && Rml::Any(property.second.unit & units);
        if(!supported) { animation.status=4; continue; }
        animation.remaining.clear();
        for(auto property : keys->property_ids) animation.remaining.insert(Rml::StyleSheetSpecification::GetPropertyName(property));
        const auto iterations=animation.iterations==-1 ? "infinite" : std::to_string(animation.iterations);
        const auto value=std::to_string(animation.duration)+"s "+animation.easing+" "+iterations+
            (animation.alternate ? " alternate " : " ")+animation.name;
        animation.status=e->SetProperty("animation",value) ? 2 : 4;
        // Native interpolation starts on the next positive time step. Seed the
        // initial pose now, avoiding one frame of the base style on entry.
        if(animation.status==2 && keys->blocks.front().normalized_time==0.f)
            for(const auto& property : keys->blocks.front().properties.GetProperties())
                e->SetProperty(property.first,property.second);
    }
    state->context->Update();
}
static void rui_render(das::Context* context,das::LineInfoArg* at) { native_guard();
    if (!state) return;
    if (state->advanced) {
        const auto size=state->context->GetDimensions();
        state->advanced->SetViewport(size.x,size.y);
        if (state->gl_clear) { glClearColor(0.035f,0.05f,0.075f,1.f); glClear(GL_COLOR_BUFFER_BIT); }
        state->advanced->BeginFrame();
        state->context->Render();
        state->advanced->EndFrame();
        rui_native_check(context,at);
        return;
    }
    SDL_BlendMode old; SDL_GetRenderDrawBlendMode(state->render.r, &old);
    SDL_SetRenderDrawBlendMode(state->render.r, SDL_BLENDMODE_BLEND_PREMULTIPLIED);
    state->context->Render(); SDL_SetRenderClipRect(state->render.r, nullptr);
    SDL_SetRenderDrawBlendMode(state->render.r, old);
    rui_native_check(context,at);
}
static void rui_shutdown_checked(das::Context* context,das::LineInfoArg* at) {
    rui_shutdown(); rui_native_check(context,at);
}
#ifdef DASRMLUI_BENCHMARK
#include "benchmark.inc"
#endif
// With the clear off, the GL3 renderer composites the UI over what the host
// has already drawn into the frame. It has no effect on the SDL_Renderer path,
// where the host clears the frame itself.
static void rui_gl_clear(bool enabled) { native_guard(); if (state) state->gl_clear = enabled; }
// Test automation uses the same RmlUi event dispatcher as real controls.
static void rui_test_event(uint64_t id, const char* type, const char* value) { native_guard();
    if (auto e = node(id)) {
        if (!strcmp(type,"change")) rui_value(id,value);
        Rml::Dictionary args; args["value"] = Rml::String(value);
        e->DispatchEvent(type,args);
    }
}
// Exercise hit testing, focus and the actual SDL -> RmlUi mouse path.
static void rui_test_click(uint64_t id) { native_guard();
    auto e = node(id);
    if (!state || !e) return;
    state->context->Update();
    const auto p = e->GetAbsoluteOffset(Rml::BoxArea::Border);
    const auto size = e->GetBox().GetSize(Rml::BoxArea::Border);
    const float density = SDL_GetWindowPixelDensity(state->window);
    SDL_Event ev{};
    ev.type = SDL_EVENT_MOUSE_MOTION;
    ev.motion.windowID = SDL_GetWindowID(state->window);
    ev.motion.x = (p.x + size.x * 0.5f) / density;
    ev.motion.y = (p.y + size.y * 0.5f) / density;
    rui_event(ev);
    ev = {};
    ev.type = SDL_EVENT_MOUSE_BUTTON_DOWN;
    ev.button.windowID = SDL_GetWindowID(state->window);
    ev.button.button = SDL_BUTTON_LEFT;
    ev.button.x = (p.x + size.x * 0.5f) / density;
    ev.button.y = (p.y + size.y * 0.5f) / density;
    ev.button.down = true;
    rui_event(ev);
    ev.type = SDL_EVENT_MOUSE_BUTTON_UP;
    ev.button.down = false;
    rui_event(ev);
}
static void rui_test_key(const char* name, bool shift) { native_guard();
    if (!state) return;
    SDL_Event ev{}; ev.type=SDL_EVENT_KEY_DOWN;
    ev.key.windowID=SDL_GetWindowID(state->window);
    ev.key.key = !strcmp(name,"Enter") ? SDLK_RETURN : !strcmp(name,"Tab") ? SDLK_TAB :
        !strcmp(name,"Escape") ? SDLK_ESCAPE : !strcmp(name,"Up") ? SDLK_UP : !strcmp(name,"Down") ? SDLK_DOWN : SDLK_SPACE;
    ev.key.mod = shift ? SDL_KMOD_SHIFT : SDL_KMOD_NONE;
    auto previous=SDL_GetModState(); SDL_SetModState(ev.key.mod);
    rui_event(ev); ev.type=SDL_EVENT_KEY_UP; rui_event(ev);
    SDL_SetModState(previous);
}
static void rui_test_shortcut(const char* name,int modifiers) { native_guard();
    if(!state) return;
    SDL_Event ev{}; ev.type=SDL_EVENT_KEY_DOWN; ev.key.windowID=SDL_GetWindowID(state->window);
    ev.key.key=SDL_GetKeyFromName(name);
    ev.key.mod=SDL_Keymod((modifiers&1 ? SDL_KMOD_CTRL:0) | (modifiers&2 ? SDL_KMOD_SHIFT:0) |
        (modifiers&4 ? SDL_KMOD_ALT:0) | (modifiers&8 ? SDL_KMOD_GUI:0));
    const auto previous=SDL_GetModState(); SDL_SetModState(ev.key.mod);
    rui_event(ev); ev.type=SDL_EVENT_KEY_UP; rui_event(ev); SDL_SetModState(previous);
}
static void rui_test_pointer(float x,float y,int button,float wheel) { native_guard();
    if(!state) return;
    const auto density=SDL_GetWindowPixelDensity(state->window);
    SDL_Event ev{}; ev.type=SDL_EVENT_MOUSE_MOTION; ev.motion.windowID=SDL_GetWindowID(state->window);
    ev.motion.x=x/density; ev.motion.y=y/density; rui_event(ev);
    ev={};
    if(button>=0) {
        ev.type=SDL_EVENT_MOUSE_BUTTON_DOWN; ev.button.windowID=SDL_GetWindowID(state->window);
        ev.button.x=x/density; ev.button.y=y/density;
        ev.button.button=button==0 ? SDL_BUTTON_LEFT : button==1 ? SDL_BUTTON_RIGHT : SDL_BUTTON_MIDDLE;
        ev.button.down=true; rui_event(ev); ev.type=SDL_EVENT_MOUSE_BUTTON_UP; ev.button.down=false; rui_event(ev);
    } else {
        ev.type=SDL_EVENT_MOUSE_WHEEL; ev.wheel.windowID=SDL_GetWindowID(state->window); ev.wheel.y=wheel; rui_event(ev);
    }
}
static das::float4 rui_bounds(uint64_t id) {
    auto e=node(id); if (!e) return {0,0,0,0};
    const auto p=e->GetAbsoluteOffset(Rml::BoxArea::Border); const auto s=e->GetBox().GetSize(Rml::BoxArea::Border);
    return {p.x,p.y,s.x,s.y};
}
// Read-only native layout probes. Text line positions use the glyph baseline,
// unlike the union rectangle of an inline element that can span several lines.
static Rml::ElementText* first_text(Rml::Element* e) {
    if(!e) return nullptr;
    if(auto text=rmlui_dynamic_cast<Rml::ElementText*>(e)) return text;
    for(int i=0;i<e->GetNumChildren();++i) if(auto text=first_text(e->GetChild(i))) return text;
    return nullptr;
}
static int rui_text_line_count(uint64_t id) { auto t=first_text(node(id)); return t ? int(t->GetLines().size()) : 0; }
static das::float2 rui_text_line_position(uint64_t id,int index) {
    auto t=first_text(node(id));
    if(!t || index<0 || index>=int(t->GetLines().size())) return {0,0};
    auto p=t->GetAbsoluteOffset()+t->GetLines()[index].position;
    return {p.x,p.y};
}
static char* rui_text_line(uint64_t id,int index,das::Context* ctx,das::LineInfoArg* at) {
    auto t=first_text(node(id));
    return str(t && index>=0 && index<int(t->GetLines().size()) ? t->GetLines()[index].text : "",ctx,at);
}
static char* rui_computed_property(uint64_t id,const char* name,das::Context* ctx,das::LineInfoArg* at) {
    auto e=node(id); const auto p=e ? e->GetProperty(name) : nullptr;
    return str(p ? p->ToString() : "",ctx,at);
}
static void rui_test_drag_offset(uint64_t source, float dx, float dy) { native_guard();
    if (!state || !node(source)) return;
    state->context->Update(); const auto box=rui_bounds(source);
    const float density=SDL_GetWindowPixelDensity(state->window);
    SDL_Event event{}; event.type=SDL_EVENT_MOUSE_MOTION;
    event.motion.windowID=SDL_GetWindowID(state->window);
    const float x=(box.x+box.z*.5f)/density,y=(box.y+box.w*.5f)/density;
    event.motion.x=x; event.motion.y=y; rui_event(event);
    event={}; event.type=SDL_EVENT_MOUSE_BUTTON_DOWN; event.button.windowID=SDL_GetWindowID(state->window);
    event.button.button=SDL_BUTTON_LEFT; event.button.down=true; rui_event(event);
    for (int i=1;i<=10;++i) {
        event={}; event.type=SDL_EVENT_MOUSE_MOTION; event.motion.windowID=SDL_GetWindowID(state->window);
        event.motion.state=SDL_BUTTON_LMASK; event.motion.x=x+dx*float(i)/10.f/density; event.motion.y=y+dy*float(i)/10.f/density;
        rui_event(event);
    }
    event={}; event.type=SDL_EVENT_MOUSE_BUTTON_UP; event.button.windowID=SDL_GetWindowID(state->window);
    event.button.button=SDL_BUTTON_LEFT; event.button.down=false; rui_event(event);
}
static void rui_test_drag(uint64_t source, uint64_t destination) { native_guard();
    if (!state || !node(source) || !node(destination)) return;
    state->context->Update(); const auto a=rui_bounds(source),b=rui_bounds(destination);
    rui_test_drag_offset(source,b.x+b.z*.5f-a.x-a.z*.5f,b.y+b.w*.5f-a.y-a.w*.5f);
}
static int rui_child_count(uint64_t id) { auto e=node(id); return e ? e->GetNumChildren() : -1; }
static uint64_t rui_child(uint64_t id, int index) {
    auto e=node(id); if (!e || index<0 || index>=e->GetNumChildren()) return 0;
    return remember(e->GetChild(index));
}
static char* rui_markup(das::Context* ctx, das::LineInfoArg* at) { Rml::String s; if (state) state->document->GetInnerRML(s); return str(s,ctx,at); }
static char* rui_inner_markup(uint64_t id,das::Context* ctx,das::LineInfoArg* at) { Rml::String s; if(auto e=node(id)) e->GetInnerRML(s); return str(s,ctx,at); }
static char* rui_local_property(uint64_t id,const char* name,das::Context* ctx,das::LineInfoArg* at) {
    auto e=node(id); const auto p=e ? e->GetLocalProperty(name) : nullptr; return str(p ? p->ToString() : "",ctx,at);
}
static bool rui_screenshot(const char* path) {
    if (!state) return false;
    if (state->advanced) {
        const auto dims=state->context->GetDimensions();
        if (dims.x<=0 || dims.y<=0) return false;
        std::vector<unsigned char> pixels(size_t(dims.x)*dims.y*4);
        glReadBuffer(GL_BACK); glPixelStorei(GL_PACK_ALIGNMENT,1);
        glReadPixels(0,0,dims.x,dims.y,GL_RGBA,GL_UNSIGNED_BYTE,pixels.data());
        auto surface=SDL_CreateSurface(dims.x,dims.y,SDL_PIXELFORMAT_RGBA32);
        if (!surface) return false;
        for (int y=0;y<dims.y;++y) memcpy((char*)surface->pixels+y*surface->pitch,pixels.data()+size_t(dims.y-y-1)*dims.x*4,size_t(dims.x)*4);
        const bool ok=SDL_SavePNG(surface,path); SDL_DestroySurface(surface); return ok;
    }
    SDL_Surface* s = SDL_RenderReadPixels(state->render.r,nullptr);
    if (!s) return false;
    bool ok = SDL_SavePNG(s,path); SDL_DestroySurface(s); return ok;
}
static void rui_focus(uint64_t id) { native_guard(); if (auto e=node(id)) e->Focus(); }
static bool rui_focused(uint64_t id) { return state && node(id) && state->context->GetFocusElement()==node(id); }
static uint64_t rui_focus_node() {
    if (!state) return 0;
    auto it=state->ids.find(state->context->GetFocusElement());
    return it == state->ids.end() ? 0 : it->second;
}
static bool rui_contains(uint64_t parent, uint64_t child) {
    auto p=node(parent); auto c=node(child);
    return p && c && (p==c || p->Contains(c));
}
static void rui_select(uint64_t id, int begin, int end) { native_guard();
    if (auto e=rmlui_dynamic_cast<Rml::ElementFormControlInput*>(node(id))) e->SetSelectionRange(begin,end);
}
static das::int2 rui_selection(uint64_t id) {
    int begin=-1,end=-1;
    if (auto e=rmlui_dynamic_cast<Rml::ElementFormControlInput*>(node(id))) e->GetSelection(&begin,&end,nullptr);
    return {begin,end};
}
static void rui_test_text(const char* text) { native_guard(); if (state) state->context->ProcessTextInput(Rml::String(text)); }
// The host finds the bundled font at run time; no path is compiled in here.
static std::string default_font_path;
void rui_set_default_font(const char* path) { default_font_path = path ? path : ""; }
static bool rui_default_font() {
    if (default_font_path.empty()) {
        SDL_Log("dasrmlui: the bundled default font was not found; load a font with rui_font and name it with set_base_text");
        return false;
    }
    return rui_font(default_font_path.c_str());
}
static bool rui_default_font_styles() {
    if(!rui_default_font()) return false;
    const auto slash=default_font_path.find_last_of("/\\");
    const auto directory=slash==std::string::npos ? std::string() : default_font_path.substr(0,slash+1);
    for(const char* file:{"LatoLatin-Bold.ttf","LatoLatin-Italic.ttf","LatoLatin-BoldItalic.ttf"})
        if(!rui_font((directory+file).c_str())) return false;
    return true;
}
#include "live_adapter.inc"
#include "web_adapter.inc"
namespace das {
// RmlUi virtual callbacks can re-enter daScript and collect its heap. Preserve the
// source position of the suspended caller, also across nested calls and longjmp.
template<typename Function> struct RuiCallNode;
template<typename R,typename... Args>
struct RuiCallNode<R(*)(Args...)> : SimNode_ExtFuncCallRet<typename ext_ret_carrier<R>::type> {
    using Base=SimNode_ExtFuncCallRet<typename ext_ret_carrier<R>::type>;
    using Function=R(*)(Args...);
    enum { IS_CMRES=false };
    Function fn;
    RuiCallNode(const LineInfo& at,const char* name,Function fn):Base(at,name),fn(fn) {}
    DAS_EVAL_ABI vec4f eval(Context& context) override {
        if(live_isolated) context.throw_error_at(&this->debugInfo,"Live candidate globals and styles must not call RmlUi; move UI work to init/update");
        auto previous=native_entry_line; native_entry_line=&this->debugInfo;
        vec4f result=v_zero();
        bool ok=false;
        char error[2048];
        bool cpp_error=false;
        try {
            ok=context.runWithCatch([&] {
                if constexpr(std::is_void_v<R>) CallStaticFunction<R,Args...>(fn,context,this->arguments);
                else result=cast<R>::from(CallStaticFunction<R,Args...>(fn,context,this->arguments));
            });
        } catch(const std::exception& exception) {
            // Unwind C++ owners before entering daScript's recovery mechanism.
            std::snprintf(error,sizeof(error),"%s",exception.what());
            cpp_error=true;
        }
        native_entry_line=previous;
        if(cpp_error) context.throw_error_at(&this->debugInfo,"%s",error);
        if(!ok) context.rethrow();
        return result;
    }
};
class Module_dasRmlUi : public Module {
    bool initialized = false;
public:
    Module_dasRmlUi() : Module("rml_native") {}
    bool initDependencies() override {
        if (initialized) return true;
        auto sdl = Module::require("sdl3");
        if (!sdl || !sdl->initDependencies()) return false;
        ModuleLibrary lib(this); lib.addBuiltInModule(); addBuiltinDependency(lib,sdl);
        initialized = true;
#define B(F) addExtern<DAS_BIND_FUN(F),RuiCallNode>(*this,lib,#F,SideEffects::worstDefault,#F)->needCallerStackFrame=true
        B(rui_hybrid_reset); B(rui_hybrid_start); B(rui_hybrid_pending); B(rui_hybrid_invalidate); B(rui_hybrid_epoch); B(rui_hybrid_begin); B(rui_hybrid_end);
        B(rui_data_context_has); B(rui_data_context_count); B(rui_data_create); B(rui_data_alive); B(rui_data_remove);
        B(rui_data_mount); B(rui_data_find);
        B(rui_data_begin); B(rui_data_abort); B(rui_data_node); B(rui_data_string); B(rui_data_bool); B(rui_data_int); B(rui_data_number); B(rui_data_commit);
        B(rui_data_kind); B(rui_data_size); B(rui_data_get_string); B(rui_data_get_int); B(rui_data_get_number); B(rui_data_get_bool);
        B(rui_data_dirty); B(rui_data_dirty_all); B(rui_data_is_dirty); B(rui_data_on);
        B(rui_data_event_begin); B(rui_data_event_end); B(rui_data_event_next); B(rui_data_event_name); B(rui_data_event_type);
        B(rui_data_event_target); B(rui_data_event_count); B(rui_data_event_string); B(rui_data_event_number); B(rui_data_event_int); B(rui_data_event_bool);
        B(rui_document_file);
        B(rui_hybrid_watch); B(rui_hybrid_watch_as); B(rui_hybrid_bind_as); B(rui_hybrid_source); B(rui_hybrid_written); B(rui_hybrid_tracked); B(rui_hybrid_bind); B(rui_hybrid_flush); B(rui_hybrid_reads); B(rui_hybrid_live); B(rui_hybrid_capacity);
#ifdef DASRMLUI_BENCHMARK
        B(bench_config); B(bench_info); B(bench_begin); B(bench_end); B(bench_case); B(bench_save);
        B(bench_native_setup); B(bench_native_set); B(bench_native_rotate); B(bench_native_bind); B(bench_native_close);
        B(bench_update); B(bench_finish); B(bench_css); B(bench_verify); B(bench_identity);
#endif
#ifdef __EMSCRIPTEN__
        B(rui_web_run);
#endif
        B(rui_live_open); B(rui_live_window_id); B(rui_init); B(rui_init_gl); B(rui_root); B(rui_font); B(rui_css);
        addExtern<DAS_BIND_FUN(rui_shutdown_checked),RuiCallNode>(*this,lib,"rui_shutdown",SideEffects::worstDefault,"rui_shutdown_checked")->needCallerStackFrame=true;
        B(rui_debugger_init); B(rui_debugger_ready); B(rui_debugger_visible); B(rui_debugger_revision);
        B(rui_debugger_show); B(rui_debugger_shutdown); B(rui_debugger_hotkey);
        B(rui_debugger_models);
        B(rui_test_debugger_document); B(rui_test_document_count);
        B(rui_has_class);
        B(rui_vector_kind); B(rui_intrinsic_size); B(rui_svg_inline);
        B(rui_create); B(rui_alive); B(rui_enabled); B(rui_remove); B(rui_before); B(rui_text);
        B(rui_property); B(rui_attr); B(rui_attr_if); B(rui_value); B(rui_get_value); B(rui_watch);
        B(rui_event); B(rui_next_event); B(rui_event_node); B(rui_event_type); B(rui_event_value);
        B(rui_update); B(rui_render); B(rui_test_event); B(rui_test_click); B(rui_child_count); B(rui_child);
        B(rui_markup); B(rui_screenshot);
        B(rui_width); B(rui_height); B(rui_scroll_top); B(rui_scroll_to); B(rui_test_resize); B(rui_test_key);
        B(rui_dp_ratio); B(rui_ui_scale); B(rui_set_ui_scale); B(rui_style_revision); B(rui_test_display_scale);
        B(rui_theme_active); B(rui_activate_theme); B(rui_set_theme); B(rui_theme);
        B(rui_pseudo); B(rui_checked); B(rui_options_clear); B(rui_option);
        B(rui_focus); B(rui_focused); B(rui_select); B(rui_selection); B(rui_test_text); B(rui_default_font);
        B(rui_focus_node); B(rui_contains);
        B(rui_active_tab); B(rui_set_tab); B(rui_visible); B(rui_get_attr); B(rui_has_attr);
        B(rui_native_register); B(rui_native_registration); B(rui_native_unregister); B(rui_native_live); B(rui_is_native);
        B(rui_native_size); B(rui_native_time); B(rui_native_intrinsic); B(rui_native_invalidate);
        B(rui_native_mesh); B(rui_native_texture_load); B(rui_native_texture_rgba);
        B(rui_native_texture_size); B(rui_native_texture_release); B(rui_native_texture_resources);
        B(rui_native_error); B(rui_native_check);
        B(rui_decorator_register); B(rui_decorator_registration); B(rui_decorator_unregister); B(rui_decorator_live);
        B(rui_decorator_number); B(rui_decorator_length); B(rui_decorator_color); B(rui_decorator_string);
        B(rui_decorator_value);
        B(rui_gpu_register); B(rui_gpu_registered); B(rui_gpu_unregister); B(rui_gpu_value);
        B(rui_gpu_error); B(rui_gpu_counts); B(rui_gpu_available);
        B(rui_test_drag); B(rui_test_drag_offset); B(rui_bounds);
        B(rui_text_line_count); B(rui_text_line_position); B(rui_text_line); B(rui_computed_property); B(rui_default_font_styles);
        B(rui_inner_markup); B(rui_local_property);
        B(rui_animation_start); B(rui_animation_cancel); B(rui_animation_status); B(rui_animation_generation); B(rui_test_advance_time);
        B(rui_event_generation);
        B(rui_resource); B(rui_document); B(rui_document_element); B(rui_close_document);
        B(rui_document_load); B(rui_show_document); B(rui_hide_document); B(rui_document_modal);
        B(rui_document_front); B(rui_document_position); B(rui_show_popup); B(rui_focus_next);
        B(rui_listen); B(rui_relisten); B(rui_unlisten); B(rui_listener_alive); B(rui_listener_count); B(rui_event_allowed);
        B(rui_event_listener); B(rui_event_target); B(rui_event_source); B(rui_event_phase); B(rui_event_key_code);
        B(rui_event_key); B(rui_event_modifiers); B(rui_event_button); B(rui_event_interruptible);
        B(rui_event_mouse); B(rui_event_screen); B(rui_event_wheel);
        B(rui_event_parameter_count); B(rui_event_parameter_name); B(rui_event_parameter_value);
        B(rui_test_shortcut); B(rui_test_pointer);
        B(rui_translation); B(rui_set_locale); B(rui_locale); B(rui_locale_revision); B(rui_translate); B(rui_fallback_font);
        B(rui_class); B(rui_warning_count); B(rui_gl_clear);
#undef B
        return true;
    }
};
}
REGISTER_MODULE_IN_NAMESPACE(Module_dasRmlUi,das);
