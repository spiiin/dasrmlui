// Included inside the bridge namespace, after State/node/remember. No script
// heap pointer or borrowed block is retained here. A rooted daScript registry
// owns lambdas; this side retains only its static dispatcher and live Context.
enum NativePhase { NativeCreate, NativeAttribute, NativeProperty, NativeResize,
    NativeUpdate, NativePaint, NativeDestroy, NativeRelease };
using NativeDispatch = das::TFunc<void,uint64_t,uint64_t,int32_t,const char*>;
das::Context* native_callback_context=nullptr;
// Real interpreter call-site position, required for GC to trace suspended callers.
das::LineInfo* native_entry_line=nullptr;
uint64_t native_callback_element=0;
int native_callback_phase=-1;
std::string native_error;
uint64_t next_native_type=1;
uint64_t next_native_texture=1;
int native_texture_resources=0;
struct NativeTexture {
    Rml::CallbackTexture owned;
    Rml::Texture view;
    NativeTexture() { ++native_texture_resources; }
    ~NativeTexture() { --native_texture_resources; }
};
struct NativeBatch {
    std::shared_ptr<NativeTexture> texture;
    Rml::Mesh mesh;
    Rml::Geometry geometry;
};
// Shared drawing storage for native elements and per-element decorator data.
struct NativeCanvas {
    Rml::Element* owner;
    std::unordered_map<uint64_t,std::shared_ptr<NativeTexture>> textures;
    std::vector<NativeBatch> batches;
    size_t paint_vertices=0,paint_indices=0;
    bool paint_dirty=true;
    explicit NativeCanvas(Rml::Element* element):owner(element) {}
    void BeginPaint() { paint_dirty=false; batches.clear(); paint_vertices=paint_indices=0; }
    void Compile() { for(auto& batch:batches) batch.geometry=owner->GetRenderManager()->MakeGeometry(std::move(batch.mesh)); }
    void Render(Rml::Vector2f offset) { for(auto& batch:batches) batch.geometry.Render(offset,batch.texture ? batch.texture->view : Rml::Texture{}); }
};
std::unordered_map<uint64_t,NativeCanvas*> decorator_canvases;

void native_guard() {
    if(native_callback_context)
        native_callback_context->throw_error("RmlUi DOM/context mutation inside a native callback is forbidden; use a DSL event handler");
}
class ScriptElement;
class ScriptInstancer final : public Rml::ElementInstancer {
public:
    uint64_t id=0;
    das::Context* context=nullptr;
    NativeDispatch dispatch;
    Rml::Vector2f intrinsic{};
    bool continuous=false;
    int live=0;
    bool Call(uint64_t element,NativePhase phase,const Rml::String& detail="") {
        if(!context || !dispatch || context->getException()) return false;
        // No nested virtual callbacks: native-specific setters only mark dirtiness.
        if(native_callback_context) return false;
        native_callback_context=context; native_callback_element=element; native_callback_phase=phase;
        const bool ok=context->runWithCatch([&] {
            vec4f args[]={das::cast<uint64_t>::from(id),das::cast<uint64_t>::from(element),
                das::cast<int32_t>::from(phase),das::cast<char*>::from(context->allocateString(detail.c_str(),uint32_t(detail.size()),nullptr))};
            context->call(dispatch.PTR,args,native_entry_line);
        });
        if(!ok) {
            const auto error=context->getException();
            if(native_error.empty()) native_error="Native element callback: "+std::string(error);
            context->clearException();
        }
        native_callback_context=nullptr; native_callback_element=0; native_callback_phase=-1;
        return ok;
    }
    Rml::ElementPtr InstanceElement(Rml::Element*,const Rml::String& tag,const Rml::XMLAttributes&) override;
    void ReleaseElement(Rml::Element* element) override { delete element; }
};
class ScriptElement final : public Rml::Element, public NativeCanvas {
public:
    ScriptInstancer& type;
    uint64_t id=0;
    Rml::Vector2f intrinsic;
    bool failed=false;
    ScriptElement(const Rml::String& tag,ScriptInstancer& instancer):Element(tag),NativeCanvas(this),type(instancer),intrinsic(type.intrinsic) { ++type.live; }
    ~ScriptElement() override {
        // Invalidate the public handle before notifying script destruction.
        if(state) { state->native_nodes.erase(id); state->nodes.erase(id); state->ids.erase(this); state->properties.erase(id); }
        type.Call(id,NativeDestroy);
        --type.live;
    }
    void Notify(NativePhase phase,const Rml::String& name="") {
        if(!id || failed) return;
        if(!type.Call(id,phase,name)) failed=true;
    }
    bool GetIntrinsicDimensions(Rml::Vector2f& size,float& ratio) override {
        if(intrinsic.x<=0 || intrinsic.y<=0) return false;
        size=intrinsic*Rml::ElementUtilities::GetDensityIndependentPixelRatio(this);
        ratio=intrinsic.x/intrinsic.y; return true;
    }
    void SetIntrinsic(Rml::Vector2f size) { if(size!=intrinsic) { intrinsic=size; DirtyLayout(); paint_dirty=true; } }
    void OnAttributeChange(const Rml::ElementAttributes& attributes) override {
        Element::OnAttributeChange(attributes);
        paint_dirty=true;
        for(const auto& entry:attributes) if(entry.first!="data-rui-id") Notify(NativeAttribute,entry.first);
    }
    void OnPropertyChange(const Rml::PropertyIdSet& properties) override {
        Element::OnPropertyChange(properties); paint_dirty=true;
        for(auto property:properties) Notify(NativeProperty,Rml::StyleSheetSpecification::GetPropertyName(property));
    }
    void OnResize() override { Element::OnResize(); paint_dirty=true; Notify(NativeResize); }
    void OnDpRatioChange() override { Element::OnDpRatioChange(); DirtyLayout(); paint_dirty=true; }
    void OnUpdate() override { if(type.continuous) Notify(NativeUpdate); }
    void OnRender() override {
        if(paint_dirty) {
            BeginPaint();
            Notify(NativePaint);
            if(failed) batches.clear();
            else Compile();
        }
        NativeCanvas::Render(GetAbsoluteOffset(Rml::BoxArea::Content));
    }
};
Rml::ElementPtr ScriptInstancer::InstanceElement(Rml::Element*,const Rml::String& tag,const Rml::XMLAttributes&) {
    auto element=new ScriptElement(tag,*this);
    element->id=remember(element);
    state->native_nodes[element->id]=element;
    element->Notify(NativeCreate);
    return Rml::ElementPtr(element);
}
ScriptElement* native_element(uint64_t id) {
    if(!node(id)) return nullptr;
    auto found=state->native_nodes.find(id);
    return found==state->native_nodes.end() ? nullptr : found->second;
}
NativeCanvas* native_canvas(uint64_t id) {
    if(auto element=native_element(id)) return element;
    auto it=decorator_canvases.find(id); return it==decorator_canvases.end() ? nullptr : it->second;
}
static uint64_t rui_native_register(const char* tag,NativeDispatch dispatch,das::float2 intrinsic,bool continuous,das::Context* context) {
    native_guard();
    if(!state || !dispatch || !tag || !*tag) return 0;
    const std::string name(tag);
    // Namespaced, lower-case names avoid overriding built-ins and XML handlers.
    if(name.find('-')==std::string::npos || name.front()<'a' || name.front()>'z') return 0;
    for(char c:name) if(!((c>='a' && c<='z') || (c>='0' && c<='9') || c=='-')) return 0;
    if(state->native_types.count(name) || Rml::Factory::GetElementInstancer(name)!=Rml::Factory::GetElementInstancer("*")) return 0;
    if(!std::isfinite(intrinsic.x) || !std::isfinite(intrinsic.y) || intrinsic.x<0 || intrinsic.y<0 || ((intrinsic.x==0)!=(intrinsic.y==0))) return 0;
    auto type=std::make_unique<ScriptInstancer>();
    type->id=next_native_type++; type->dispatch=dispatch; type->context=context;
    type->intrinsic={intrinsic.x,intrinsic.y}; type->continuous=continuous;
    const auto id=type->id;
    Rml::Factory::RegisterElementInstancer(name,type.get());
    state->native_types.emplace(name,std::move(type));
    return id;
}
static uint64_t rui_native_registration(const char* tag) {
    if(!state) return 0;
    auto it=state->native_types.find(tag); return it==state->native_types.end() ? 0 : it->second->id;
}
static bool rui_native_unregister(const char* tag) {
    native_guard();
    if(!state) return false;
    auto it=state->native_types.find(tag);
    if(it==state->native_types.end() || it->second->live) return false;
    Rml::Factory::RegisterElementInstancer(tag,Rml::Factory::GetElementInstancer("*"));
    it->second->Call(0,NativeRelease); state->native_types.erase(it); return true;
}
static int rui_native_live(const char* tag) {
    if(!state) return 0;
    auto it=state->native_types.find(tag); return it==state->native_types.end() ? 0 : it->second->live;
}
static bool rui_is_native(uint64_t id) { return native_element(id)!=nullptr; }
static das::float2 rui_native_size(uint64_t id) {
    auto e=native_element(id); const auto size=e ? e->GetBox().GetSize(Rml::BoxArea::Content) : Rml::Vector2f{};
    return {size.x,size.y};
}
static double rui_native_time() { return state ? state->system->GetElapsedTime() : 0.; }
static void rui_native_invalidate(uint64_t id) { if(auto e=native_canvas(id)) e->paint_dirty=true; }
static bool rui_native_intrinsic(uint64_t id,das::float2 size) {
    if(native_callback_context && (native_callback_phase==NativePaint || native_callback_phase==NativeDestroy))
        native_callback_context->throw_error("Native intrinsic size cannot change during paint or destroy");
    auto e=native_element(id);
    if(!e || !std::isfinite(size.x) || !std::isfinite(size.y) || size.x<=0 || size.y<=0) return false;
    e->SetIntrinsic({size.x,size.y}); return true;
}
NativeCanvas* native_painter(uint64_t id,das::Context* context) {
    if(native_callback_phase!=NativePaint || native_callback_element!=id || !native_callback_context)
        context->throw_error("Native drawing is only valid inside this element's Paint callback");
    return native_canvas(id);
}
Rml::ColourbPremultiplied native_color(NativeCanvas* e,das::uint4 color) {
    const float alpha=std::min(color.w,255u)/255.f*e->owner->GetComputedValues().opacity();
    return {Rml::byte(std::min(color.x,255u)*alpha),Rml::byte(std::min(color.y,255u)*alpha),
        Rml::byte(std::min(color.z,255u)*alpha),Rml::byte(255*alpha)};
}
static void rui_native_mesh(uint64_t id,const das::TArray<das::float4>& vertices,const das::TArray<das::uint4>& colors,
    const das::TArray<int32_t>& indices,uint64_t texture,das::Context* context) {
    auto e=native_painter(id,context);
    if(!e) context->throw_error("Native mesh requires a live element");
    // Validate everything before changing a batch. No script pointer survives this call.
    if(vertices.size!=colors.size || indices.size%3) context->throw_error("Native mesh requires one color per vertex and triangle indices");
    if(vertices.size>1000000-e->paint_vertices || indices.size>3000000-e->paint_indices)
        context->throw_error("Native geometry exceeds per-paint vertex/index limit");
    for(uint32_t i=0;i<vertices.size;++i) { const auto v=vertices[i];
        if(!std::isfinite(v.x) || !std::isfinite(v.y) || !std::isfinite(v.z) || !std::isfinite(v.w))
            context->throw_error("Native mesh positions and UV must be finite");
    }
    for(uint32_t i=0;i<indices.size;++i) if(indices[i]<0 || uint32_t(indices[i])>=vertices.size) context->throw_error("Native mesh index out of bounds");
    // Validate before acquiring shared_ptrs: daScript errors can use longjmp.
    if(texture && !e->textures.count(texture)) context->throw_error("Native texture is stale or belongs to another element");
    if(!indices.size) return;
    auto resource=texture ? e->textures.at(texture) : std::shared_ptr<NativeTexture>{};
    if(e->batches.empty() || e->batches.back().texture!=resource) e->batches.push_back({resource,{},{}});
    auto& mesh=e->batches.back().mesh;
    const auto offset=int(mesh.vertices.size());
    for(uint32_t i=0;i<vertices.size;++i) {
        const auto v=vertices[i];
        mesh.vertices.push_back({{v.x,v.y},native_color(e,colors[i]),{v.z,v.w}});
    }
    for(uint32_t i=0;i<indices.size;++i) mesh.indices.push_back(offset+indices[i]);
    e->paint_vertices+=vertices.size; e->paint_indices+=indices.size;
}
NativeCanvas* native_texture_owner(uint64_t id,das::Context* context) {
    if(native_callback_context && (native_callback_element!=id || native_callback_phase==NativeDestroy))
        context->throw_error("Native texture access requires the current live element");
    auto e=native_canvas(id);
    if(!e || !e->owner->GetRenderManager()) context->throw_error("Native textures require an attached element; initialize them in Paint");
    return e;
}
static uint64_t rui_native_texture_load(uint64_t id,const char* source,das::Context* context) {
    auto e=native_texture_owner(id,context);
    if(!source || !*source) return 0;
    auto view=e->owner->GetRenderManager()->LoadTexture(source,e->owner->GetOwnerDocument()->GetSourceURL());
    auto size=view.GetDimensions();
    if(size.x<=0 || size.y<=0) return 0;
    auto resource=std::make_shared<NativeTexture>(); resource->view=view;
    const auto handle=next_native_texture++; e->textures.emplace(handle,std::move(resource)); return handle;
}
static uint64_t rui_native_texture_rgba(uint64_t id,das::int2 size,const das::TArray<das::uint4>& pixels,das::Context* context) {
    auto e=native_texture_owner(id,context);
    if(size.x<=0 || size.y<=0 || size.x>4096 || size.y>4096 || uint64_t(size.x)*size.y!=pixels.size)
        context->throw_error("Native texture requires dimensions 1..4096 and exactly width*height RGBA pixels");
    std::vector<Rml::byte> bytes; bytes.reserve(size_t(pixels.size)*4);
    for(uint32_t i=0;i<pixels.size;++i) { const auto color=pixels[i];
        const auto a=std::min(color.w,255u);
        for(auto c:{color.x,color.y,color.z}) bytes.push_back(Rml::byte(std::min(c,255u)*a/255u));
        bytes.push_back(Rml::byte(a));
    }
    auto resource=std::make_shared<NativeTexture>();
    resource->owned=e->owner->GetRenderManager()->MakeCallbackTexture([bytes=std::move(bytes),size](const Rml::CallbackTextureInterface& target) {
        return target.GenerateTexture({bytes.data(),bytes.size()},{size.x,size.y});
    });
    resource->view=resource->owned;
    auto dimensions=resource->view.GetDimensions();
    if(dimensions.x<=0 || dimensions.y<=0) return 0;
    const auto handle=next_native_texture++; e->textures.emplace(handle,std::move(resource)); return handle;
}
static das::int2 rui_native_texture_size(uint64_t id,uint64_t texture) {
    auto e=native_canvas(id);
    if(!e || !e->textures.count(texture)) return {};
    auto size=e->textures.at(texture)->view.GetDimensions(); return {size.x,size.y};
}
static bool rui_native_texture_release(uint64_t id,uint64_t texture,das::Context* context) {
    if(native_callback_context && native_callback_element!=id) context->throw_error("Cannot release another element's texture inside a native callback");
    auto e=native_canvas(id); return e && e->textures.erase(texture)!=0;
}
static int rui_native_texture_resources() { return native_texture_resources; }
static char* rui_native_error(das::Context* context,das::LineInfoArg* at) {
    return context->allocateString(native_error.c_str(),uint32_t(native_error.size()),at);
}
static void rui_native_check(das::Context* context,das::LineInfoArg* at) {
    if(!native_error.empty()) { auto error=std::move(native_error); native_error.clear(); context->throw_error_at(at,"%s",error.c_str()); }
}
