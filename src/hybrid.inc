// Pinned RmlUi DataModel/DataView integration. No borrowed script pointer is ever
// dereferenced by Update/Render: values are copied at mount or a reported write.
struct HybridSlot {
    Rml::String name, target;
    Rml::Variant value;
    uint64_t element=0, seen=0;
    uintptr_t source=0;
    int kind=0;
    bool live=false;
};
struct HybridRuntime {
    Rml::DataModel* model=nullptr; // Owned by Context and visible in its Debugger.
    std::vector<std::unique_ptr<HybridSlot>> slots;
    std::vector<HybridSlot*> free;
    std::unordered_map<std::string,HybridSlot*> by_target;
    std::unordered_multimap<uintptr_t,HybridSlot*> sources;
    std::unordered_set<uintptr_t> watched;
    std::unordered_set<uintptr_t> owned_sources;
    uintptr_t root=0;
    uint64_t epoch=0, reads=0;
    bool structural=true;
};
std::unique_ptr<HybridRuntime> hybrid;
static Rml::Variant hybrid_read(void* p,int kind) {
    switch(kind) {
    case 1: { const auto s=*static_cast<char**>(p); return Rml::Variant(Rml::String(s ? s : "")); }
    case 2: return Rml::Variant(*static_cast<int*>(p));
    case 3: return Rml::Variant(*static_cast<float*>(p));
    case 4: return Rml::Variant(*static_cast<bool*>(p));
    case 5: return Rml::Variant(*static_cast<double*>(p));
    default: throw std::runtime_error("Unsupported hybrid scalar type");
    }
}
class HybridTextView final : public Rml::DataView {
    Rml::String name;
public:
    explicit HybridTextView(Rml::Element* e):DataView(e,0) {}
    bool Initialize(Rml::DataModel&,Rml::Element*,const Rml::String& expression,const Rml::String&) override { name=expression; return true; }
    Rml::StringList GetVariableNameList() const override { return {name}; }
    bool Update(Rml::DataModel& model) override {
        auto e=GetElement(); if(!e) return false;
        Rml::Variant value;
        if(!model.GetVariableInto({Rml::DataAddressEntry(name)},value)) return false;
        const auto text=value.Get<Rml::String>();
        auto caption=rmlui_dynamic_cast<Rml::ElementText*>(e->GetFirstChild());
        if(caption && caption->GetText()==text) return false;
        if(caption) caption->SetText(text);
        else e->InsertBefore(e->GetOwnerDocument()->CreateTextNode(text),e->GetFirstChild());
        return true;
    }
    void Release() override { delete this; }
};
static void rui_hybrid_reset() { native_guard();
    if(hybrid && state && state->context) {
        state->context->RemoveDataModel("dasrmlui");
    }
    hybrid.reset();
}
static void rui_hybrid_start(void* root) { native_guard();
    if(!hybrid) {
        if(!state || !state->context) throw std::runtime_error("ui_frame requires initialized RmlUi");
        auto constructor=state->context->CreateDataModel("dasrmlui");
        if(!constructor) throw std::runtime_error("Reserved dasrmlui model already exists");
        // Context exposes only a constructor, not its internal model pointer.
        // Resolve it through the normal attachment path, without assigning a
        // native data scope to the DSL's manually managed element tree.
        auto probe=state->document->CreateElement("div");
        probe->SetAttribute("data-model",Rml::String("dasrmlui"));
        auto attached=state->document->AppendChild(std::move(probe));
        auto model=attached->GetDataModel();
        state->document->RemoveChild(attached);
        if(!model) { state->context->RemoveDataModel("dasrmlui"); throw std::runtime_error("Cannot attach hybrid model to Context"); }
        hybrid=std::make_unique<HybridRuntime>(); hybrid->model=model;
    }
    if(hybrid->root!=uintptr_t(root)) { hybrid->root=uintptr_t(root); hybrid->structural=true; }
}
static bool rui_hybrid_pending() { return !hybrid || hybrid->structural || (state && !state->events.empty()); }
static void rui_hybrid_invalidate() { if(hybrid) hybrid->structural=true; }
static uint64_t rui_hybrid_epoch() { return hybrid ? hybrid->epoch : 0; }
static void rui_hybrid_begin() { native_guard();
    ++hybrid->epoch; hybrid->structural=false;
    hybrid->sources.clear(); hybrid->watched.clear(); hybrid->owned_sources.clear();
}
static void rui_hybrid_source(void* p) { native_guard(); if(hybrid) hybrid->owned_sources.insert(uintptr_t(p)); }
static void rui_hybrid_watch(void* p) { native_guard();
    if(hybrid) {
        hybrid->watched.insert(uintptr_t(p));
        if(!hybrid->owned_sources.count(uintptr_t(p))) hybrid->structural=true;
    }
}
// Bit 0: a component argument whose call site was analysed. Outside the model
// it is a copy that the caller rebuilds on every pass able to change it, so it
// is not by itself a reason for the next pass.
// Bit 1: storage handed to a callee by reference. The callee subscribes to what
// it reads; the caller only has to know that writes to it are reported.
static void rui_hybrid_watch_as(void* p,int mode) { native_guard();
    if(!hybrid) return;
    const auto address=uintptr_t(p);
    if(hybrid->owned_sources.count(address)) { if(!(mode&2)) hybrid->watched.insert(address); }
    else if(!(mode&1)) hybrid->structural=true;
}
static void rui_hybrid_written(void* p,int kind) { native_guard();
    if(!hybrid) return;
    const auto address=uintptr_t(p);
    auto range=hybrid->sources.equal_range(address);
    if(!kind || range.first==range.second || hybrid->watched.count(address)) hybrid->structural=true;
    if(!kind) return;
    for(auto it=range.first;it!=range.second;++it) {
        auto slot=it->second;
        if(!slot->live || slot->kind!=kind) { hybrid->structural=true; continue; }
        auto value=hybrid_read(p,kind);
        if(slot->value!=value) { slot->value=std::move(value); hybrid->model->DirtyVariable(slot->name); }
    }
}
static void rui_hybrid_tracked(void* p,int kind) {
    // Instrumented locals and loop counters are not UI writes. Actual aliases
    // to model fields share the registered address and still notify precisely.
    if(hybrid && hybrid->owned_sources.count(uintptr_t(p))) rui_hybrid_written(p,kind);
}
static void hybrid_forget(Rml::Element* e) {
    if(!hybrid || !e) return;
    for(int i=0;i<e->GetNumChildren();++i) hybrid_forget(e->GetChild(i));
    hybrid->model->OnElementRemove(e);
    auto id=state->ids.find(e); if(id==state->ids.end()) return;
    for(auto it=hybrid->by_target.begin();it!=hybrid->by_target.end();) {
        auto slot=it->second;
        if(slot->element!=id->second) { ++it; continue; }
        auto range=hybrid->sources.equal_range(slot->source);
        for(auto s=range.first;s!=range.second;) { if(s->second==slot) s=hybrid->sources.erase(s); else ++s; }
        slot->live=false; slot->value=Rml::Variant(); slot->source=0;
        hybrid->free.push_back(slot); it=hybrid->by_target.erase(it);
    }
}
static void hybrid_add_view(HybridSlot* slot) {
    Rml::DataViewPtr view;
    Rml::String modifier;
    const auto& t=slot->target;
    auto element=node(slot->element);
    if(t=="text") view.reset(new HybridTextView(element));
    else if(t=="value") view=Rml::Factory::InstanceDataView("value",element);
    else if(t=="checked") view=Rml::Factory::InstanceDataView("checked",element);
    else if(t.rfind("attr:",0)==0) { view=Rml::Factory::InstanceDataView("attr",element); modifier=t.substr(5); }
    else if(t.rfind("style:",0)==0) { view=Rml::Factory::InstanceDataView("style",element); modifier=t.substr(6); }
    else if(t.rfind("class:",0)==0) { view=Rml::Factory::InstanceDataView("class",element); modifier=t.substr(6); }
    if(!view || !view->Initialize(*hybrid->model,element,slot->name,modifier)) throw std::runtime_error("Hybrid view initialization failed");
    hybrid->model->AddView(std::move(view));
}
static void rui_hybrid_end() { native_guard();
    std::unordered_set<uint64_t> changed;
    for(auto it=hybrid->by_target.begin();it!=hybrid->by_target.end();) {
        auto slot=it->second;
        if(slot->seen==hybrid->epoch) { ++it; continue; }
        if(changed.insert(slot->element).second) hybrid->model->OnElementRemove(node(slot->element));
        slot->live=false; slot->value=Rml::Variant(); slot->source=0;
        hybrid->free.push_back(slot); it=hybrid->by_target.erase(it);
    }
    for(auto& entry:hybrid->by_target) if(changed.count(entry.second->element)) hybrid_add_view(entry.second);
}
static void hybrid_bind(uint64_t element,const char* target,void* source,int kind,bool covered) { native_guard();
    if(!hybrid || !node(element)) throw std::runtime_error("Hybrid binding requires ui_frame(state)");
    auto key=std::to_string(element)+":"+target;
    auto found=hybrid->by_target.find(key);
    HybridSlot* slot=nullptr;
    if(found!=hybrid->by_target.end()) slot=found->second;
    else {
        if(!hybrid->free.empty()) { slot=hybrid->free.back(); hybrid->free.pop_back(); }
        else {
            auto owned=std::make_unique<HybridSlot>(); slot=owned.get();
            slot->name="v"+std::to_string(hybrid->slots.size());
            hybrid->slots.push_back(std::move(owned));
            if(!hybrid->model->BindFunc(slot->name,[slot](Rml::Variant& out) {
                ++hybrid->reads; out=slot->value;
                // Native style views bypass rui_property's redundant-write cache.
                if(slot->target.rfind("style:",0)==0 && state) state->properties[slot->element].erase(slot->target.substr(6));
            },{})) throw std::runtime_error("Hybrid variable registration failed");
        }
        slot->live=true; slot->element=element; slot->target=target;
        hybrid->by_target.emplace(key,slot);
        hybrid_add_view(slot);
    }
    auto old=hybrid->sources.equal_range(slot->source);
    for(auto it=old.first;it!=old.second;) { if(it->second==slot) it=hybrid->sources.erase(it); else ++it; }
    slot->seen=hybrid->epoch;
    slot->source=uintptr_t(source); slot->kind=kind;
    auto value=hybrid_read(source,kind);
    if(slot->value!=value) { slot->value=std::move(value); hybrid->model->DirtyVariable(slot->name); }
    if(slot->target=="value" || slot->target=="checked") hybrid->model->DirtyVariable(slot->name); // restore rejected edits
    if(hybrid->owned_sources.count(slot->source)) hybrid->sources.emplace(slot->source,slot);
    // Temporary/computed/local values require fresh evaluation, unless the
    // caller of this component guarantees it (see rui_hybrid_watch_as): the
    // view then shows a copy and the address is never looked at again.
    else if(!covered) hybrid->structural=true;
}
static void rui_hybrid_bind(uint64_t element,const char* target,void* source,int kind) { hybrid_bind(element,target,source,kind,false); }
static void rui_hybrid_bind_as(uint64_t element,const char* target,void* source,int kind,bool covered) { hybrid_bind(element,target,source,kind,covered); }
static void rui_hybrid_flush() { native_guard();
    if(!hybrid) return;
    // Native checked/value views may dispatch change while applying model data.
    // Match rui_attr/rui_value: these are not new input commands for the DSL.
    struct RestoreApplying { bool& flag; bool previous; ~RestoreApplying() { flag=previous; } } restore{state->applying,state->applying};
    state->applying=true;
    hybrid->model->Update(true);
}
static uint64_t rui_hybrid_reads() { return hybrid ? hybrid->reads : 0; }
static int rui_hybrid_live() { return hybrid ? int(hybrid->by_target.size()) : 0; }
static int rui_hybrid_capacity() { return hybrid ? int(hybrid->slots.size()) : 0; }
