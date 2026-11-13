// Public Context-owned RmlUi models. The script bridge copies values synchronously;
// RmlUi and its debugger never retain pointers into the daScript heap.
struct PublicDataNode;
struct PublicDataDefinition final : Rml::VariableDefinition {
    int kind;
    Rml::StringList members;
    std::vector<std::shared_ptr<PublicDataDefinition>> member_types;
    std::shared_ptr<PublicDataDefinition> element_type;
    explicit PublicDataDefinition(int k):VariableDefinition(k==4 ? Rml::DataVariableType::Array :
        k==5 ? Rml::DataVariableType::Struct : Rml::DataVariableType::Scalar),kind(k) {}
    bool Get(void*,Rml::Variant&) override;
    bool Set(void*,const Rml::Variant&) override;
    int Size(void*) override;
    Rml::DataVariable Child(void*,const Rml::DataAddressEntry&) override;
    Rml::StringList ReflectMemberNames() override { return members; }
};
struct PublicDataNode {
    std::shared_ptr<PublicDataDefinition> definition;
    Rml::Variant value;
    std::vector<std::unique_ptr<PublicDataNode>> children;
    bool writable=false;
};
bool PublicDataDefinition::Get(void* p,Rml::Variant& out) { if(kind>=4) return false; out=static_cast<PublicDataNode*>(p)->value; return true; }
bool PublicDataDefinition::Set(void* p,const Rml::Variant& in) {
    auto& n=*static_cast<PublicDataNode*>(p);
    if(!n.writable || kind>=4) return false;
    switch(kind) {
    case 0: { Rml::String v; if(!in.GetInto(v)) return false; n.value=std::move(v); break; }
    case 1: { bool v; if(!in.GetInto(v)) return false; n.value=v; break; }
    case 2: { int64_t v; if(!in.GetInto(v)) return false; n.value=v; break; }
    case 3: { double v; if(!in.GetInto(v) || !std::isfinite(v)) return false; n.value=v; break; }
    }
    return true;
}
int PublicDataDefinition::Size(void* p) { return int(static_cast<PublicDataNode*>(p)->children.size()); }
Rml::DataVariable PublicDataDefinition::Child(void* p,const Rml::DataAddressEntry& address) {
    auto& n=*static_cast<PublicDataNode*>(p); int index=address.index;
    if(kind==4 && address.name=="size") return Rml::MakeLiteralIntVariable(int(n.children.size()));
    if(kind==5) { auto it=std::find(members.begin(),members.end(),address.name); index=int(it-members.begin()); }
    if(index<0 || size_t(index)>=n.children.size()) return {};
    auto child=n.children[size_t(index)].get(); return {child->definition.get(),child};
}
struct PublicDataEvent { std::string name,type; uint64_t target=0; Rml::VariantList arguments; };
struct PublicDataModel {
    std::string name;
    Rml::DataModelConstructor constructor;
    Rml::DataModelHandle handle;
    std::unordered_map<std::string,std::unique_ptr<PublicDataNode>> variables;
    std::unordered_set<std::string> callbacks;
    std::deque<PublicDataEvent> events;
    PublicDataEvent current;
    bool draining=false;
};
struct PublicDataStage {
    uint64_t model=0; std::string path; bool binding=false,writable=false;
    std::unique_ptr<PublicDataNode> root;
    std::unordered_map<uint64_t,PublicDataNode*> nodes;
};
static std::unordered_map<uint64_t,std::unique_ptr<PublicDataModel>> public_models;
static std::unordered_map<uint64_t,PublicDataStage> public_stages;
static uint64_t data_serial=1;
static bool data_identifier(const std::string& s,bool reserved=true) {
    auto alpha=[](char c){ return (c>='a'&&c<='z') || (c>='A'&&c<='Z'); };
    if(s.empty() || !alpha(s[0])) return false;
    for(char c:s) if(!alpha(c) && !(c>='0'&&c<='9') && c!='_') return false;
    auto lower=Rml::StringUtilities::ToLower(s);
    return !reserved || (lower!="it" && lower!="it_index" && lower!="ev" && lower!="true" && lower!="false" && lower!="size" && lower!="literal");
}
static PublicDataModel& data_model(uint64_t id) {
    auto it=public_models.find(id);
    if(!state || it==public_models.end()) throw std::runtime_error("DataModel: stale or foreign model handle");
    return *it->second;
}
static PublicDataStage& data_stage(uint64_t id) {
    auto it=public_stages.find(id); if(it==public_stages.end()) throw std::runtime_error("DataModel: invalid write stage");
    data_model(it->second.model); return it->second;
}
static PublicDataNode& data_path(PublicDataModel& m,const std::string& path,std::string* root_name=nullptr) {
    auto end=path.find_first_of(".["); auto root=path.substr(0,end);
    auto it=m.variables.find(root); if(it==m.variables.end()) throw std::runtime_error("DataModel: unknown variable/path "+path);
    if(root_name) *root_name=root;
    auto n=it->second.get(); size_t at=root.size();
    while(at<path.size()) {
        if(path[at]=='.') {
            auto begin=++at; at=path.find_first_of(".[",at); if(at==std::string::npos) at=path.size();
            auto name=path.substr(begin,at-begin); auto& members=n->definition->members;
            auto field=std::find(members.begin(),members.end(),name);
            if(n->definition->kind!=5 || field==members.end()) throw std::runtime_error("DataModel: unknown member "+path);
            n=n->children[size_t(field-members.begin())].get();
        } else if(path[at]=='[') {
            size_t index=0; auto begin=++at;
            while(at<path.size() && path[at]>='0' && path[at]<='9') {
                index=index*10+size_t(path[at++]-'0');
                if(index>10000000) throw std::runtime_error("DataModel: index out of range");
            }
            if(at==begin || at>=path.size() || path[at++]!=']' || n->definition->kind!=4 || index>=n->children.size())
                throw std::runtime_error("DataModel: index out of range");
            n=n->children[index].get();
        } else throw std::runtime_error("DataModel: malformed path");
    }
    return *n;
}
static bool data_compatible(const PublicDataDefinition& a,const PublicDataDefinition& b) {
    if(a.kind!=b.kind || a.members!=b.members) return false;
    for(size_t i=0;i<a.member_types.size();++i) if(!data_compatible(*a.member_types[i],*b.member_types[i])) return false;
    if(a.element_type && b.element_type) return data_compatible(*a.element_type,*b.element_type);
    return true;
}
static void data_merge_schema(PublicDataDefinition& a,PublicDataDefinition& b) {
    for(size_t i=0;i<a.member_types.size();++i) data_merge_schema(*a.member_types[i],*b.member_types[i]);
    if(a.element_type && b.element_type) data_merge_schema(*a.element_type,*b.element_type);
    else if(a.element_type) b.element_type=a.element_type;
    else a.element_type=b.element_type;
}
static void data_writable(PublicDataNode& n,bool writable) { n.writable=writable; for(auto& c:n.children) data_writable(*c,writable); }
static bool rui_data_context_has(const char* name) { return state && state->context && state->context->GetDataModels().count(name)!=0; }
static int rui_data_context_count() { return state && state->context ? int(state->context->GetDataModels().size()) : 0; }
static uint64_t rui_data_create(const char* name) { native_guard();
    if(!state || !state->context) throw std::runtime_error("DataModel: initialize RmlUi first");
    if(!data_identifier(name) || !strcmp(name,"dasrmlui") || rui_data_context_has(name)) throw std::runtime_error("DataModel: invalid, reserved or duplicate name");
    auto m=std::make_unique<PublicDataModel>(); m->name=name;
    m->constructor=state->context->CreateDataModel(name); m->handle=m->constructor.GetModelHandle();
    const auto id=data_serial++; public_models.emplace(id,std::move(m)); return id;
}
static bool rui_data_alive(uint64_t id) { return state && public_models.count(id)!=0; }
static void rui_data_mount(uint64_t host_id,uint64_t model_id,const char* markup) { native_guard();
    auto& model=data_model(model_id);
    auto host=node(host_id);
    if(!host || !host->GetOwnerDocument()) throw std::runtime_error("native_data: host must be attached");
    if(host->GetDataModel()) throw std::runtime_error("native_data: host must be outside an existing native data scope");
    // Keep the managed host outside any data model. Moving this boundary with
    // each_keyed must not detach/reinitialise native views and loop aliases.
    // A child root gets its model on initial attachment and remains attached
    // inside that boundary across managed sibling reorders.
    host->SetInnerRML("");
    auto scope=host->GetOwnerDocument()->CreateElement("div");
    scope->SetAttribute("data-model",model.name);
    scope->SetClassNames("ru-box");
    auto root=host->AppendChild(std::move(scope));
    root->SetInnerRML(markup);
}
static uint64_t rui_data_find(uint64_t scope,const char* part,int occurrence) {
    if(occurrence<0) return 0;
    auto root=node(scope); if(!root) return 0;
    std::function<Rml::Element*(Rml::Element*)> visit=[&](Rml::Element* element)->Rml::Element* {
        // data-for retains an unrendered template alongside generated elements.
        if(element->HasAttribute("data-for")) return nullptr;
        if(element->GetAttribute<Rml::String>("data-rui-part","")==part && occurrence--==0) return element;
        for(int i=0;i<element->GetNumChildren();++i) if(auto found=visit(element->GetChild(i))) return found;
        return nullptr;
    };
    return remember(visit(root));
}
static bool rui_data_remove(uint64_t id) { native_guard();
    auto it=public_models.find(id); if(it==public_models.end()) return false;
    // Remove native controllers/views before their copied values and definitions.
    state->context->RemoveDataModel(it->second->name);
    for(auto s=public_stages.begin();s!=public_stages.end();) { if(s->second.model==id) s=public_stages.erase(s); else ++s; }
    public_models.erase(it); return true;
}
static void data_shutdown() { while(!public_models.empty()) rui_data_remove(public_models.begin()->first); public_stages.clear(); }
static uint64_t rui_data_begin(uint64_t model,const char* path,bool binding,bool writable) { native_guard();
    auto& m=data_model(model);
    if(binding) { if(!data_identifier(path) || m.variables.count(path)) throw std::runtime_error("DataModel: invalid or duplicate variable"); }
    else data_path(m,path);
    auto id=data_serial++; auto& s=public_stages[id]; s.model=model; s.path=path; s.binding=binding; s.writable=writable; return id;
}
static void rui_data_abort(uint64_t stage) { native_guard(); public_stages.erase(stage); }
static uint64_t rui_data_node(uint64_t stage,uint64_t parent,const char* name,int kind) { native_guard();
    auto& s=data_stage(stage); if(kind<0 || kind>5) throw std::runtime_error("DataModel: unsupported value kind");
    auto owned=std::make_unique<PublicDataNode>(); auto n=owned.get(); n->definition=std::make_shared<PublicDataDefinition>(kind); n->writable=s.writable;
    if(!parent) { if(s.root) throw std::runtime_error("DataModel: duplicate root"); s.root=std::move(owned); }
    else {
        auto it=s.nodes.find(parent); if(it==s.nodes.end()) throw std::runtime_error("DataModel: foreign parent");
        auto p=it->second;
        if(p->definition->kind==5) {
            if(!data_identifier(name,false)) throw std::runtime_error("DataModel: invalid member");
            p->definition->members.push_back(name); p->definition->member_types.push_back(n->definition);
        }
        else if(p->definition->kind!=4) throw std::runtime_error("DataModel: scalar cannot have children");
        else if(!p->definition->element_type) p->definition->element_type=n->definition;
        p->children.push_back(std::move(owned));
    }
    auto id=data_serial++; s.nodes.emplace(id,n); return id;
}
static PublicDataNode& data_build_node(uint64_t stage,uint64_t id,int kind) {
    auto& s=data_stage(stage); auto it=s.nodes.find(id);
    if(it==s.nodes.end() || it->second->definition->kind!=kind) throw std::runtime_error("DataModel: invalid scalar node");
    return *it->second;
}
static void rui_data_string(uint64_t s,uint64_t n,const char* v) { data_build_node(s,n,0).value=Rml::String(v ? v : ""); }
static void rui_data_bool(uint64_t s,uint64_t n,bool v) { data_build_node(s,n,1).value=v; }
static void rui_data_int(uint64_t s,uint64_t n,int64_t v) { data_build_node(s,n,2).value=v; }
static void rui_data_number(uint64_t s,uint64_t n,double v) { if(!std::isfinite(v)) throw std::runtime_error("DataModel: non-finite number"); data_build_node(s,n,3).value=v; }
static void rui_data_commit(uint64_t stage) { native_guard();
    auto& s=data_stage(stage); auto& m=data_model(s.model); if(!s.root) throw std::runtime_error("DataModel: empty write stage");
    if(s.binding) {
        auto n=s.root.get();
        if(!m.constructor.BindCustomDataVariable(s.path,{n->definition.get(),n})) throw std::runtime_error("DataModel: binding failed");
        m.variables.emplace(s.path,std::move(s.root)); m.handle.DirtyVariable(s.path);
    } else {
        std::string root; auto& n=data_path(m,s.path,&root);
        if(!data_compatible(*n.definition,*s.root->definition)) throw std::runtime_error("DataModel: changing bound value type is not allowed");
        data_merge_schema(*n.definition,*s.root->definition);
        // Keep the bound root address and definition stable; RmlUi resolves child
        // addresses afresh (controllers retain paths, never array element pointers).
        data_writable(*s.root,n.writable); n.value=std::move(s.root->value); n.children=std::move(s.root->children);
        m.handle.DirtyVariable(root);
    }
    public_stages.erase(stage);
}
static int rui_data_kind(uint64_t id,const char* path) { return data_path(data_model(id),path).definition->kind; }
static int rui_data_size(uint64_t id,const char* path) { return int(data_path(data_model(id),path).children.size()); }
static char* rui_data_get_string(uint64_t id,const char* path,das::Context* ctx,das::LineInfoArg* at) { return str(data_path(data_model(id),path).value.Get<Rml::String>(),ctx,at); }
static int64_t rui_data_get_int(uint64_t id,const char* path) { return data_path(data_model(id),path).value.Get<int64_t>(); }
static double rui_data_get_number(uint64_t id,const char* path) { return data_path(data_model(id),path).value.Get<double>(); }
static bool rui_data_get_bool(uint64_t id,const char* path) { return data_path(data_model(id),path).value.Get<bool>(); }
static void rui_data_dirty(uint64_t id,const char* name) { native_guard(); auto& m=data_model(id); if(!m.variables.count(name)) throw std::runtime_error("DataModel: dirty requires a bound root name"); m.handle.DirtyVariable(name); }
static void rui_data_dirty_all(uint64_t id) { native_guard(); data_model(id).handle.DirtyAllVariables(); }
static bool rui_data_is_dirty(uint64_t id,const char* name) { auto& m=data_model(id); if(!m.variables.count(name)) throw std::runtime_error("DataModel: unknown variable"); return m.handle.IsVariableDirty(name); }
static void rui_data_on(uint64_t id,const char* name) { native_guard();
    auto& m=data_model(id); if(!data_identifier(name) || !m.callbacks.insert(name).second) throw std::runtime_error("DataModel: invalid or duplicate callback");
    if(!m.constructor.BindEventCallback(name,[id,label=std::string(name)](Rml::DataModelHandle,Rml::Event& event,const Rml::VariantList& args) {
        auto& model=data_model(id); PublicDataEvent e; e.name=label; e.type=event.GetType(); e.target=remember(event.GetTargetElement()); e.arguments=args;
        model.events.push_back(std::move(e));
    })) throw std::runtime_error("DataModel: callback registration failed");
}
static int rui_data_event_begin(uint64_t id) { auto& m=data_model(id); if(m.draining) throw std::runtime_error("DataModel: recursive event drain"); m.draining=true; return int(m.events.size()); }
static void rui_data_event_end(uint64_t id) { auto it=public_models.find(id); if(it!=public_models.end()) { it->second->draining=false; it->second->current={}; } }
static bool rui_data_event_next(uint64_t id) { auto& m=data_model(id); if(!m.draining || m.events.empty()) return false; m.current=std::move(m.events.front()); m.events.pop_front(); return true; }
static char* rui_data_event_name(uint64_t id,das::Context* ctx,das::LineInfoArg* at) { return str(data_model(id).current.name,ctx,at); }
static char* rui_data_event_type(uint64_t id,das::Context* ctx,das::LineInfoArg* at) { return str(data_model(id).current.type,ctx,at); }
static uint64_t rui_data_event_target(uint64_t id) { return data_model(id).current.target; }
static int rui_data_event_count(uint64_t id) { return int(data_model(id).current.arguments.size()); }
static const Rml::Variant& data_event_arg(uint64_t id,int index) { auto& a=data_model(id).current.arguments; if(index<0 || size_t(index)>=a.size()) throw std::runtime_error("DataModel: event argument out of range"); return a[size_t(index)]; }
static char* rui_data_event_string(uint64_t id,int i,das::Context* ctx,das::LineInfoArg* at) { return str(data_event_arg(id,i).Get<Rml::String>(),ctx,at); }
static double rui_data_event_number(uint64_t id,int i) { return data_event_arg(id,i).Get<double>(); }
static int64_t rui_data_event_int(uint64_t id,int i) { return data_event_arg(id,i).Get<int64_t>(); }
static bool rui_data_event_bool(uint64_t id,int i) { return data_event_arg(id,i).Get<bool>(); }
