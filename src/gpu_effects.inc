// Native RCSS instancers + immutable GL3 programs. No borrowed script heap data.
uint64_t next_gpu_type=1;
std::string gpu_error;
struct GpuDefinition {
    virtual ~GpuDefinition()=default;
    uint64_t id=0;
    std::string key;
    std::vector<DecoratorParameter> parameters;
    const Rml::PropertySpecification* specification=nullptr;
    bool filter=false,active=true;
    int definitions=0;
    float overflow=0;
    Rml::Dictionary Values(const Rml::PropertyDictionary& properties,Rml::Element* element,Rml::Vector2f size) const {
        Rml::Dictionary values{{"dimensions",Rml::Variant(size)}};
        for(const auto& p:parameters) {
            std::string name="p_"+p.name; std::replace(name.begin(),name.end(),'-','_');
            auto value=properties.GetProperty(p.id);
            if(p.parser=="color") {
                auto color=value->Get<Rml::Colourb>();
                values.emplace(name,Rml::Vector4f(color.red/255.f,color.green/255.f,color.blue/255.f,color.alpha/255.f));
            } else if(p.parser=="number") values.emplace(name,value->Get<float>());
            else values.emplace(name,element->ResolveNumericValue(value->GetNumericValue(),size.x));
        }
        return values;
    }
};
template<class Base> struct GpuInstancer : Base,GpuDefinition {
    bool Configure(const das::TArray<char*>& names,const das::TArray<char*>& parsers,const das::TArray<char*>& defaults) {
        Rml::String shorthand;
        for(uint32_t i=0;i<names.size;++i) {
            auto& definition=this->RegisterProperty(names[i],defaults[i]).AddParser(parsers[i]);
            if(definition.GetDefaultValue()->unit==Rml::Unit::UNKNOWN) return false;
            parameters.push_back({names[i],parsers[i],definition.GetId()});
            if(i) shorthand+=", "; shorthand+=Rml::String(names[i])+"?";
        }
        if(!shorthand.empty()) this->RegisterShorthand(filter ? "filter" : "decorator",shorthand,Rml::ShorthandType::RecursiveCommaSeparated);
        specification=&this->GetPropertySpecification(); return true;
    }
};
struct GpuShaderData { Rml::Geometry geometry; Rml::CompiledShader shader; };
class GpuShader final : public Rml::Decorator {
    GpuDefinition& type;
    Rml::PropertyDictionary properties;
public:
    GpuShader(GpuDefinition& type,const Rml::PropertyDictionary& properties):type(type),properties(properties) { ++type.definitions; }
    ~GpuShader() override { --type.definitions; }
    Rml::DecoratorDataHandle GenerateElementData(Rml::Element* element,Rml::BoxArea area) const override {
        const auto box=element->GetRenderBox(area); const auto size=box.GetFillSize();
        auto manager=element->GetRenderManager();
        auto shader=manager->CompileShader(type.key,type.Values(properties,element,size));
        if(!shader) return INVALID_DECORATORDATAHANDLE;
        Rml::Mesh mesh;
        const auto alpha=Rml::byte(element->GetComputedValues().opacity()*255.f);
        Rml::MeshUtilities::GenerateBackground(mesh,box,Rml::ColourbPremultiplied(alpha,alpha));
        const auto offset=box.GetFillOffset();
        for(auto& vertex:mesh.vertices) vertex.tex_coord={(vertex.position.x-offset.x)/std::max(size.x,1.f),(vertex.position.y-offset.y)/std::max(size.y,1.f)};
        auto data=new GpuShaderData{manager->MakeGeometry(std::move(mesh)),std::move(shader)};
        return reinterpret_cast<Rml::DecoratorDataHandle>(data);
    }
    void ReleaseElementData(Rml::DecoratorDataHandle data) const override { delete reinterpret_cast<GpuShaderData*>(data); }
    void RenderElement(Rml::Element* element,Rml::DecoratorDataHandle handle) const override {
        auto data=reinterpret_cast<GpuShaderData*>(handle);
        data->geometry.Render(element->GetAbsoluteOffset(Rml::BoxArea::Border),{},data->shader);
    }
};
class GpuShaderInstancer final : public GpuInstancer<Rml::DecoratorInstancer> {
    Rml::SharedPtr<Rml::Decorator> InstanceDecorator(const Rml::String&,const Rml::PropertyDictionary& values,const Rml::DecoratorInstancerInterface&) override {
        return active ? Rml::MakeShared<GpuShader>(*this,values) : nullptr;
    }
};
class GpuFilter final : public Rml::Filter {
    GpuDefinition& type;
    Rml::PropertyDictionary properties;
public:
    GpuFilter(GpuDefinition& type,const Rml::PropertyDictionary& properties):type(type),properties(properties) { ++type.definitions; }
    ~GpuFilter() override { --type.definitions; }
    Rml::CompiledFilter CompileFilter(Rml::Element* element) const override {
        return element->GetRenderManager()->CompileFilter(type.key,type.Values(properties,element,element->GetBox().GetSize(Rml::BoxArea::Border)));
    }
    void ExtendInkOverflow(Rml::Element* element,Rml::Rectanglef& bounds) const override {
        const float pad=type.overflow*Rml::ElementUtilities::GetDensityIndependentPixelRatio(element);
        bounds=Rml::Rectanglef::FromPositionSize(bounds.Position()-Rml::Vector2f(pad),bounds.Size()+Rml::Vector2f(2*pad));
    }
};
class GpuFilterInstancer final : public GpuInstancer<Rml::FilterInstancer> {
    Rml::SharedPtr<Rml::Filter> InstanceFilter(const Rml::String&,const Rml::PropertyDictionary& values) override {
        return active ? Rml::MakeShared<GpuFilter>(*this,values) : nullptr;
    }
};
static bool rui_gpu_available() { return state && bool(state->advanced); }
static char* rui_gpu_error(das::Context* context) { return context->allocateString(gpu_error.c_str(),uint32_t(gpu_error.size()),nullptr); }
static das::int2 rui_gpu_counts() {
    auto counts=rui_gpu_available() ? state->advanced->EffectCounts() : Rml::Vector2i{}; return {counts.x,counts.y};
}
static uint64_t rui_gpu_register(const char* name,bool filter,const char* source,const das::TArray<char*>& names,
    const das::TArray<char*>& parsers,const das::TArray<char*>& defaults,float overflow) {
    native_guard(); gpu_error.clear();
    if(!rui_gpu_available()) { gpu_error="Custom GPU effects require the GL3 renderer"; return 0; }
    if(!decorator_name(name,true) || !source || !*source || strlen(source)>1024*1024 || names.size!=parsers.size || names.size!=defaults.size || names.size>32 ||
        !std::isfinite(overflow) || overflow<0 || overflow>4096) { gpu_error="Invalid GPU effect name, source, parameters or overflow"; return 0; }
    if(state->gpu_effects.count(name)) { gpu_error="Duplicate GPU effect registration"; return 0; }
    const auto existing=filter ? static_cast<Rml::EffectSpecification*>(Rml::Factory::GetFilterInstancer(name)) :
        static_cast<Rml::EffectSpecification*>(Rml::Factory::GetDecoratorInstancer(name));
    bool retired=!existing;
    if(existing) for(auto& type:state->retired_gpu_effects) if(type->specification==&existing->GetPropertySpecification()) retired=true;
    if(!retired) { gpu_error="Cannot override an existing RmlUi effect"; return 0; }
    for(uint32_t i=0;i<names.size;++i) {
        if(!decorator_name(names[i]) || !parsers[i] || !defaults[i] || strcmp(names[i],"decorator")==0 || strcmp(names[i],"filter")==0) { gpu_error="Invalid GPU parameter"; return 0; }
        for(uint32_t j=0;j<i;++j) if(strcmp(names[i],names[j])==0) { gpu_error="Duplicate GPU parameter"; return 0; }
        const std::string parser=parsers[i];
        if(parser!="number" && parser!="length_percent" && parser!="color") { gpu_error="GPU parameters support only number, length/percent and color"; return 0; }
    }
    std::unique_ptr<GpuDefinition> type;
    if(filter) {
        auto value=std::make_unique<GpuFilterInstancer>(); value->filter=true;
        if(!value->Configure(names,parsers,defaults)) { gpu_error="Invalid GPU parameter default"; return 0; }
        type=std::move(value);
    } else {
        auto value=std::make_unique<GpuShaderInstancer>();
        if(!value->Configure(names,parsers,defaults)) { gpu_error="Invalid GPU parameter default"; return 0; }
        type=std::move(value);
    }
    #if defined(__EMSCRIPTEN__) || defined(DASRMLUI_IOS)
    std::string fragment="#version 300 es\nprecision highp float;\n";
#else
    std::string fragment="#version 330\n";
#endif
    fragment+="uniform float u_time;\nuniform vec2 u_size;\nuniform vec2 u_texel;\n";
    for(const auto& p:type->parameters) {
        auto uniform=p.name; std::replace(uniform.begin(),uniform.end(),'-','_');
        fragment+="uniform "+std::string(p.parser=="color" ? "vec4" : "float")+" p_"+uniform+";\n";
    }
    if(filter) fragment+=R"(
uniform sampler2D _source;
uniform vec4 _source_bounds;
uniform vec2 _viewport;
out vec4 finalColor;
vec4 sample_source(vec2 uv) {
    if(any(lessThan(uv,vec2(0))) || any(greaterThan(uv,vec2(1)))) return vec4(0);
    vec2 pixel=clamp(_source_bounds.xy+uv*_source_bounds.zw,_source_bounds.xy+vec2(0.5),_source_bounds.xy+_source_bounds.zw-vec2(0.5));
    vec4 color=texture(_source,vec2(pixel.x/_viewport.x,1.-pixel.y/_viewport.y));
    return color.a>0. ? vec4(color.rgb/color.a,color.a) : vec4(0);
}
)";
    else fragment+="in vec2 fragTexCoord;\nin vec4 fragColor;\nout vec4 finalColor;\n";
    fragment+="#line 1\n"; fragment+=source;
    fragment+=filter ? R"(
void main() {
    vec2 uv=(vec2(gl_FragCoord.x,_viewport.y-gl_FragCoord.y)-_source_bounds.xy)/max(u_size,vec2(1));
    vec4 c=clamp(effect(uv),0.,1.); finalColor=vec4(c.rgb*c.a,c.a);
})" : R"(
void main() { vec4 c=clamp(effect(fragTexCoord),0.,1.); finalColor=vec4(c.rgb*c.a,c.a)*fragColor; }
)";
    type->id=next_gpu_type++; type->key="dasrml-gpu-"+std::to_string(type->id); type->overflow=overflow;
    if(!state->advanced->RegisterEffect(type->key,filter,fragment,gpu_error)) return 0;
    const auto id=type->id;
    if(filter) Rml::Factory::RegisterFilterInstancer(name,static_cast<GpuFilterInstancer*>(type.get()));
    else Rml::Factory::RegisterDecoratorInstancer(name,static_cast<GpuShaderInstancer*>(type.get()));
    state->gpu_effects.emplace(name,std::move(type)); return id;
}
static bool rui_gpu_registered(const char* name,bool filter) {
    if(!state || !name || !*name) return false;
    auto it=state->gpu_effects.find(name); return it!=state->gpu_effects.end() && it->second->filter==filter;
}
static bool rui_gpu_unregister(const char* name,bool filter) {
    native_guard();
    if(!rui_gpu_registered(name,filter)) return false;
    auto it=state->gpu_effects.find(name); auto& type=*it->second;
    if(type.definitions || state->advanced->EffectInUse(type.key)) return false;
    state->advanced->UnregisterEffect(type.key); type.active=false;
    state->retired_gpu_effects.push_back(std::move(it->second)); state->gpu_effects.erase(it); return true;
}
static char* rui_gpu_value(const char* name,bool filter,const das::TArray<char*>& names,const das::TArray<char*>& values,das::Context* context) {
    if(!rui_gpu_registered(name,filter)) context->throw_error("GPU effect must be registered with the matching kind before evaluating styles");
    if(names.size!=values.size) context->throw_error("GPU argument arrays differ in length");
    auto& type=*state->gpu_effects.at(name);
    for(uint32_t i=0;i<names.size;++i) {
        if(!names[i] || !values[i]) context->throw_error("GPU arguments require a name and value");
        bool found=false; for(const auto& p:type.parameters) if(p.name==names[i]) found=true;
        if(!found) context->throw_error("Unknown GPU effect argument");
        for(uint32_t j=0;j<i;++j) if(strcmp(names[i],names[j])==0) context->throw_error("Duplicate GPU effect argument");
    }
    Rml::String declaration=Rml::String(name)+"(";
    bool valid=true;
    for(const auto& p:type.parameters) {
        const auto definition=type.specification->GetProperty(p.id); Rml::Property property=*definition->GetDefaultValue();
        for(uint32_t i=0;i<names.size;++i) if(p.name==names[i]) valid=definition->ParseValue(property,values[i]) && valid;
        if(&p!=&type.parameters.front()) declaration+=", "; declaration+=property.ToString();
    }
    declaration+=")";
    return valid ? context->allocateString(declaration.c_str(),uint32_t(declaration.size()),nullptr) : nullptr;
}
