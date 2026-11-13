// Included after native_elements.inc. Uses the same validated, owned drawing API.
using DecoratorDispatch=das::TFunc<void,uint64_t,uint64_t,uint64_t,int32_t,das::float2,float,const char*>;
uint64_t next_decorator_type=1, next_decorator_canvas=uint64_t(1)<<63;
struct DecoratorParameter { std::string name,parser; Rml::PropertyId id; };
struct ScriptDecoratorData;
class ScriptDecorator;
class ScriptDecoratorInstancer final : public Rml::DecoratorInstancer {
public:
    uint64_t id=0;
    das::Context* context=nullptr;
    DecoratorDispatch dispatch;
    std::vector<DecoratorParameter> parameters;
    int definitions=0,live=0;
    bool active=true;
    bool Configure(const das::TArray<char*>& names,const das::TArray<char*>& parsers,const das::TArray<char*>& defaults) {
        Rml::String shorthand;
        for(uint32_t i=0;i<names.size;++i) {
            auto& definition=RegisterProperty(names[i],defaults[i]).AddParser(parsers[i]);
            if(definition.GetDefaultValue()->unit==Rml::Unit::UNKNOWN) return false;
            parameters.push_back({names[i],parsers[i],definition.GetId()});
            if(i) shorthand+=", ";
            shorthand+=Rml::String(names[i])+"?";
        }
        if(!shorthand.empty()) RegisterShorthand("decorator",shorthand,Rml::ShorthandType::RecursiveCommaSeparated);
        return true;
    }
    bool Call(ScriptDecoratorData* data,NativePhase phase);
    Rml::SharedPtr<Rml::Decorator> InstanceDecorator(const Rml::String&,const Rml::PropertyDictionary& properties,
        const Rml::DecoratorInstancerInterface&) override;
};
struct ScriptDecoratorData : NativeCanvas {
    const ScriptDecorator& decorator;
    uint64_t id,element;
    Rml::Vector2f size,offset;
    float dpi;
    const char* area;
    bool failed=false;
    ScriptDecoratorData(const ScriptDecorator& value,Rml::Element* owner,Rml::BoxArea paint_area):NativeCanvas(owner),decorator(value) {
        id=next_decorator_canvas++; element=remember(owner);
        const auto box=owner->GetRenderBox(paint_area);
        size=box.GetFillSize(); offset=box.GetBorderOffset()+box.GetFillOffset();
        dpi=Rml::ElementUtilities::GetDensityIndependentPixelRatio(owner);
        area=paint_area==Rml::BoxArea::Border ? "border-box" : paint_area==Rml::BoxArea::Content ? "content-box" : "padding-box";
    }
};
bool ScriptDecoratorInstancer::Call(ScriptDecoratorData* data,NativePhase phase) {
    if(!context || !dispatch || context->getException() || native_callback_context) return false;
    native_callback_context=context; native_callback_element=data ? data->id : 0; native_callback_phase=phase;
    const bool ok=context->runWithCatch([&] {
        const char* area=data ? data->area : "";
        vec4f args[]={das::cast<uint64_t>::from(id),das::cast<uint64_t>::from(data ? data->id : 0),
            das::cast<uint64_t>::from(data ? data->element : 0),das::cast<int32_t>::from(phase),
            das::cast<das::float2>::from(data ? das::float2{data->size.x,data->size.y} : das::float2{}),
            das::cast<float>::from(data ? data->dpi : 1.f),
            das::cast<char*>::from(context->allocateString(area,uint32_t(strlen(area)),nullptr))};
        context->call(dispatch.PTR,args,native_entry_line);
    });
    if(!ok) {
        if(native_error.empty()) native_error="Decorator callback: "+std::string(context->getException());
        context->clearException();
    }
    native_callback_context=nullptr; native_callback_element=0; native_callback_phase=-1;
    return ok;
}
class ScriptDecorator final : public Rml::Decorator {
public:
    ScriptDecoratorInstancer& type;
    Rml::PropertyDictionary properties;
    ScriptDecorator(ScriptDecoratorInstancer& type,const Rml::PropertyDictionary& values):type(type),properties(values) { ++type.definitions; }
    ~ScriptDecorator() override { --type.definitions; }
    Rml::DecoratorDataHandle GenerateElementData(Rml::Element* element,Rml::BoxArea area) const override {
        auto data=new ScriptDecoratorData(*this,element,area);
        decorator_canvases.emplace(data->id,data); ++type.live;
        data->failed=!type.Call(data,NativeCreate);
        return reinterpret_cast<Rml::DecoratorDataHandle>(data);
    }
    void ReleaseElementData(Rml::DecoratorDataHandle handle) const override {
        auto data=reinterpret_cast<ScriptDecoratorData*>(handle);
        decorator_canvases.erase(data->id); // No stale resource/property access in Destroy.
        type.Call(data,NativeDestroy); --type.live; delete data;
    }
    void RenderElement(Rml::Element* element,Rml::DecoratorDataHandle handle) const override {
        auto data=reinterpret_cast<ScriptDecoratorData*>(handle);
        if(data->paint_dirty) {
            data->BeginPaint();
            if(!data->failed) data->failed=!type.Call(data,NativePaint);
            if(data->failed) data->batches.clear(); else data->Compile();
        }
        data->Render(element->GetAbsoluteOffset(Rml::BoxArea::Border)+data->offset);
    }
};
Rml::SharedPtr<Rml::Decorator> ScriptDecoratorInstancer::InstanceDecorator(const Rml::String&,const Rml::PropertyDictionary& values,
    const Rml::DecoratorInstancerInterface&) {
    return active ? Rml::MakeShared<ScriptDecorator>(*this,values) : nullptr;
}
bool decorator_name(const char* name,bool namespaced=false) {
    if(!name || *name<'a' || *name>'z') return false;
    bool dash=false;
    for(const char* c=name;*c;++c) { if(*c=='-') dash=true; else if(!(*c>='a' && *c<='z') && !(*c>='0' && *c<='9')) return false; }
    return !namespaced || dash;
}
static uint64_t rui_decorator_register(const char* name,const das::TArray<char*>& names,const das::TArray<char*>& parsers,
    const das::TArray<char*>& defaults,DecoratorDispatch dispatch,das::Context* context) {
    native_guard();
    if(!state || !dispatch || !decorator_name(name,true) || names.size!=parsers.size || names.size!=defaults.size || names.size>32 || state->decorator_types.count(name)) return 0;
    if(auto current=Rml::Factory::GetDecoratorInstancer(name)) {
        bool retired=false;
        for(auto& type:state->retired_decorator_types) if(type.get()==current) retired=true;
        if(!retired) return 0;
    }
    for(uint32_t i=0;i<names.size;++i) {
        if(!decorator_name(names[i]) || strcmp(names[i],"decorator")==0 || !defaults[i] || !parsers[i]) return 0;
        for(uint32_t j=0;j<i;++j) if(strcmp(names[i],names[j])==0) return 0;
        const std::string parser=parsers[i];
        if(parser!="number" && parser!="length_percent" && parser!="color" && parser!="string") return 0;
    }
    auto type=std::make_unique<ScriptDecoratorInstancer>();
    if(!type->Configure(names,parsers,defaults)) return 0;
    type->id=next_decorator_type++; type->context=context; type->dispatch=dispatch;
    const auto id=type->id;
    Rml::Factory::RegisterDecoratorInstancer(name,type.get()); state->decorator_types.emplace(name,std::move(type)); return id;
}
static uint64_t rui_decorator_registration(const char* name) {
    if(!state) return 0;
    auto it=state->decorator_types.find(name); return it==state->decorator_types.end() ? 0 : it->second->id;
}
static bool rui_decorator_unregister(const char* name) {
    native_guard(); if(!state) return false;
    auto it=state->decorator_types.find(name);
    if(it==state->decorator_types.end() || it->second->live || it->second->definitions) return false;
    it->second->Call(nullptr,NativeRelease); it->second->active=false;
    // Factory/parsed declarations retain raw pointers. Tombstones live until shutdown.
    state->retired_decorator_types.push_back(std::move(it->second)); state->decorator_types.erase(it); return true;
}
static int rui_decorator_live(const char* name) {
    if(!state) return 0;
    auto it=state->decorator_types.find(name); return it==state->decorator_types.end() ? 0 : it->second->live;
}
const Rml::Property* decorator_property(uint64_t canvas,const char* name,const char* parser,das::Context* context) {
    auto it=decorator_canvases.find(canvas);
    if(it==decorator_canvases.end()) context->throw_error("Decorator parameter requires a live decorator canvas");
    auto data=static_cast<ScriptDecoratorData*>(it->second);
    for(const auto& p:data->decorator.type.parameters) if(p.name==name) {
        if(parser && p.parser!=parser) context->throw_error("Decorator parameter has a different type");
        return data->decorator.properties.GetProperty(p.id);
    }
    context->throw_error("Unknown decorator parameter"); return nullptr;
}
static float rui_decorator_number(uint64_t canvas,const char* name,das::Context* context) {
    return decorator_property(canvas,name,"number",context)->Get<float>();
}
static float rui_decorator_length(uint64_t canvas,const char* name,float base,das::Context* context) {
    if(!std::isfinite(base)) context->throw_error("Decorator percentage base must be finite");
    auto value=decorator_property(canvas,name,"length_percent",context)->GetNumericValue();
    return decorator_canvases.at(canvas)->owner->ResolveNumericValue(value,base);
}
static das::uint4 rui_decorator_color(uint64_t canvas,const char* name,das::Context* context) {
    auto value=decorator_property(canvas,name,"color",context)->Get<Rml::Colourb>();
    return {value.red,value.green,value.blue,value.alpha};
}
static char* rui_decorator_string(uint64_t canvas,const char* name,das::Context* context) {
    auto value=decorator_property(canvas,name,"string",context)->Get<Rml::String>();
    return context->allocateString(value.c_str(),uint32_t(value.size()),nullptr);
}
// Canonical, typed named arguments for the style DSL; no raw RCSS interpolation.
static char* rui_decorator_value(const char* type_name,const das::TArray<char*>& names,const das::TArray<char*>& values,
    das::Context* context) {
    if(!state || !state->decorator_types.count(type_name)) context->throw_error("Decorator must be registered before its styles are evaluated");
    if(names.size!=values.size) context->throw_error("Decorator argument arrays differ in length");
    auto& type=*state->decorator_types.at(type_name);
    // No owning C++ locals across script throw_error (which may longjmp).
    for(uint32_t i=0;i<names.size;++i) {
        bool found=false;
        for(const auto& p:type.parameters) if(p.name==names[i]) found=true;
        if(!found) context->throw_error("Unknown decorator argument");
        for(uint32_t j=0;j<i;++j) if(strcmp(names[i],names[j])==0) context->throw_error("Duplicate decorator argument");
    }
    Rml::String result=Rml::String(type_name)+"(";
    bool valid=true;
    for(const auto& p:type.parameters) {
        const auto definition=type.GetPropertySpecification().GetProperty(p.id);
        Rml::Property property=*definition->GetDefaultValue();
        for(uint32_t i=0;i<names.size;++i) if(p.name==names[i]) valid=definition->ParseValue(property,values[i]) && valid;
        if(&p!=&type.parameters.front()) result+=", ";
        if(p.parser=="string") {
            auto value=property.Get<Rml::String>();
            // RCSS string tokens cannot safely contain these delimiters here.
            if(value.find_first_of("\"\\\n\r;{}")!=Rml::String::npos) valid=false;
            result+='"'; result+=value; result+='"';
        } else result+=property.ToString();
    }
    result+=")";
    if(!valid) { result.clear(); /* free before raising outside this scope below */ }
    char* output=valid ? context->allocateString(result.c_str(),uint32_t(result.size()),nullptr) : nullptr;
    // The wrapper raises after this function returns, so temporary strings are destroyed.
    return output;
}
