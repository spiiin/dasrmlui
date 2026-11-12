// Included inside the bridge namespace, after State/node/remember. No script
// heap pointer or borrowed block is retained here. A rooted daScript registry
// owns lambdas; this side retains only its static dispatcher and live Context.
enum NativePhase { NativeCreate, NativeAttribute, NativeProperty, NativeResize,
    NativeUpdate, NativePaint, NativeDestroy, NativeRelease };
using NativeDispatch = das::TFunc<void,uint64_t,uint64_t,int32_t,const char*>;
das::Context* native_callback_context=nullptr;
uint64_t native_callback_element=0;
int native_callback_phase=-1;
std::string native_error;
uint64_t next_native_type=1;

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
            context->call(dispatch.PTR,args,nullptr);
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
class ScriptElement final : public Rml::Element {
public:
    ScriptInstancer& type;
    uint64_t id=0;
    Rml::Vector2f intrinsic;
    Rml::Geometry geometry;
    Rml::Mesh paint_mesh;
    bool paint_dirty=true,failed=false;
    ScriptElement(const Rml::String& tag,ScriptInstancer& instancer):Element(tag),type(instancer),intrinsic(type.intrinsic) { ++type.live; }
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
            paint_dirty=false; paint_mesh={};
            Notify(NativePaint);
            geometry={};
            if(!failed && !paint_mesh.indices.empty()) geometry=GetRenderManager()->MakeGeometry(std::move(paint_mesh));
        }
        if(geometry) geometry.Render(GetAbsoluteOffset(Rml::BoxArea::Content));
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
static void rui_native_invalidate(uint64_t id) { if(auto e=native_element(id)) e->paint_dirty=true; }
static bool rui_native_intrinsic(uint64_t id,das::float2 size) {
    if(native_callback_context && (native_callback_phase==NativePaint || native_callback_phase==NativeDestroy))
        native_callback_context->throw_error("Native intrinsic size cannot change during paint or destroy");
    auto e=native_element(id);
    if(!e || !std::isfinite(size.x) || !std::isfinite(size.y) || size.x<=0 || size.y<=0) return false;
    e->SetIntrinsic({size.x,size.y}); return true;
}
ScriptElement* native_painter(uint64_t id,das::Context* context) {
    if(native_callback_phase!=NativePaint || native_callback_element!=id || !native_callback_context)
        context->throw_error("Native drawing is only valid inside this element's Paint callback");
    return native_element(id);
}
Rml::ColourbPremultiplied native_color(ScriptElement* e,das::uint4 color) {
    const float alpha=std::min(color.w,255u)/255.f*e->GetComputedValues().opacity();
    return {Rml::byte(std::min(color.x,255u)*alpha),Rml::byte(std::min(color.y,255u)*alpha),
        Rml::byte(std::min(color.z,255u)*alpha),Rml::byte(255*alpha)};
}
static void rui_native_rect(uint64_t id,das::float4 rect,das::uint4 color,das::Context* context) {
    auto e=native_painter(id,context);
    if(!e || !std::isfinite(rect.x) || !std::isfinite(rect.y) || !std::isfinite(rect.z) || !std::isfinite(rect.w) || rect.z<=0 || rect.w<=0) return;
    if(e->paint_mesh.vertices.size()>1000000) context->throw_error("Native geometry exceeds vertex limit");
    Rml::MeshUtilities::GenerateQuad(e->paint_mesh,{rect.x,rect.y},{rect.z,rect.w},native_color(e,color));
}
static void rui_native_triangle(uint64_t id,das::float2 a,das::float2 b,das::float2 c,das::uint4 color,das::Context* context) {
    auto e=native_painter(id,context);
    if(!e || !std::isfinite(a.x) || !std::isfinite(a.y) || !std::isfinite(b.x) || !std::isfinite(b.y) || !std::isfinite(c.x) || !std::isfinite(c.y)) return;
    if(e->paint_mesh.vertices.size()>1000000) context->throw_error("Native geometry exceeds vertex limit");
    const auto index=int(e->paint_mesh.vertices.size()); const auto col=native_color(e,color);
    for(auto p:{a,b,c}) e->paint_mesh.vertices.push_back({{p.x,p.y},col,{}});
    for(int i=0;i<3;++i) e->paint_mesh.indices.push_back(index+i);
}
static char* rui_native_error(das::Context* context,das::LineInfoArg* at) {
    return context->allocateString(native_error.c_str(),uint32_t(native_error.size()),at);
}
static void rui_native_check(das::Context* context,das::LineInfoArg* at) {
    if(!native_error.empty()) { auto error=std::move(native_error); native_error.clear(); context->throw_error_at(at,"%s",error.c_str()); }
}
