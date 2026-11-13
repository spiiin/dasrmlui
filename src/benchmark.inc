// Benchmark-only instrumentation. Production binaries do not expose these APIs.
struct BenchHeap { uint64_t count=0,bytes=0,live=0; };
static BenchHeap bench_heap(das::Context* c) {
    return {c->heap->getTotalAllocations()+c->stringHeap->getTotalAllocations(),
        c->heap->getTotalBytesAllocated()+c->stringHeap->getTotalBytesAllocated(),
        c->heap->bytesAllocated()+c->stringHeap->bytesAllocated()};
}
struct BenchSample { int mode,scenario,round,phase,frame; double us; uint64_t cpp_count,cpp_bytes,das_count,das_bytes; int64_t das_live_delta; };
std::vector<BenchSample> bench_samples;
int bench_mode=0,bench_scenario=0,bench_round=0,bench_frame=0,bench_phase=0;
bool bench_memory=false,bench_record=false;
BenchHeap bench_start_heap;
std::chrono::steady_clock::time_point bench_start_time;
static int bench_config(const char* key,int fallback) {
    const auto value=std::getenv(key);
    if(!value || !*value) return fallback;
    return std::max(1,std::min(100000,std::atoi(value)));
}
static bool bench_info() {
    std::printf("GL vendor: %s\nGL renderer: %s\nGL version: %s\n", glGetString(GL_VENDOR), glGetString(GL_RENDERER), glGetString(GL_VERSION));
    return rui_bench::allocation_selftest();
}
static void bench_case(int mode,int scenario,int round,bool memory) {
    bench_mode=mode; bench_scenario=scenario; bench_round=round; bench_memory=memory;
    bench_samples.reserve(bench_samples.size()+10000);
}
static void bench_begin(int phase,int frame,bool record,das::Context* c) {
    bench_phase=phase; bench_frame=frame; bench_record=record;
    bench_defer_update=phase==0;
    bench_start_heap=bench_heap(c);
    rui_bench::allocations={}; rui_bench::counting=bench_memory && record;
    bench_start_time=std::chrono::steady_clock::now();
}
static void bench_end(das::Context* c) {
    const auto end=std::chrono::steady_clock::now();
    rui_bench::counting=false; bench_defer_update=false;
    const auto heap=bench_heap(c);
    if(bench_record) bench_samples.push_back({bench_mode,bench_scenario,bench_round,bench_phase,bench_frame,
        std::chrono::duration<double,std::micro>(end-bench_start_time).count(),
        bench_memory ? rui_bench::allocations.count : UINT64_MAX,
        bench_memory ? rui_bench::allocations.bytes : UINT64_MAX,
        heap.count-bench_start_heap.count,heap.bytes-bench_start_heap.bytes,int64_t(heap.live)-int64_t(bench_start_heap.live)});
}
static void bench_save(const char* file) {
    std::ofstream out(file);
    out << "mode,scenario,round,phase,frame,us,cpp_allocs,cpp_bytes,das_allocs,das_bytes,das_live_delta\n";
    for(const auto& s:bench_samples) out << s.mode << ',' << s.scenario << ',' << s.round << ',' << s.phase << ',' << s.frame << ',' << s.us << ','
        << s.cpp_count << ',' << s.cpp_bytes << ',' << s.das_count << ',' << s.das_bytes << ',' << s.das_live_delta << '\n';
    out.close(); if(!out) throw std::runtime_error("Could not save benchmark CSV");
    bench_samples.clear();
}
struct BenchRow { int id; Rml::String text; };
std::vector<BenchRow> bench_rows;
Rml::DataModelHandle bench_model;
Rml::Element* bench_list=nullptr;
bool bench_dirty=false;
std::unordered_map<std::string,Rml::Element*> bench_initial_nodes;
static const char* bench_style=R"(body { font-family: LatoLatin; font-size: 14px; margin: 0px; width: 800px; height: 700px; overflow: hidden; color: #eeeeee; background-color: #101820; }
div { display: block; width: 700px; }
span { display: block; width: 700px; height: 20px; line-height: 20px; })";
static void bench_css() { rui_css(bench_style); }
static void bench_native_setup(const das::TArray<char*>& values) {
    bench_rows.clear(); bench_rows.reserve(values.size);
    for(uint32_t i=0;i<values.size;++i) bench_rows.push_back({int(i),values[i]});
    auto model=state->context->CreateDataModel("benchmark");
    if(!model) throw std::runtime_error("Benchmark data model creation failed");
    auto row=model.RegisterStruct<BenchRow>();
    if(!row || !row.RegisterMember("id",&BenchRow::id) || !row.RegisterMember("text",&BenchRow::text) ||
        !model.RegisterArray<std::vector<BenchRow>>() || !model.Bind("rows",&bench_rows))
        throw std::runtime_error("Benchmark data model registration failed");
    bench_model=model.GetModelHandle();
    state->document->SetInnerRML("<div id='bench-list' data-model='benchmark'><span data-for='row : rows'>{{row.text}}</span></div>");
    bench_list=state->document->GetElementById("bench-list");
    bench_dirty=true; bench_css();
}
static void bench_native_set(int index,const char* value) { bench_rows.at(size_t(index)).text=value; bench_dirty=true; }
static void bench_native_rotate() { std::rotate(bench_rows.begin(),bench_rows.end()-1,bench_rows.end()); bench_dirty=true; }
static void bench_native_bind() {
    if(bench_dirty) { bench_model.DirtyVariable("rows"); bench_dirty=false; }
    bench_list->GetDataModel()->Update(true);
}
static void bench_native_close() {
    state->document->SetInnerRML("");
    state->context->Update(); state->context->RemoveDataModel("benchmark");
    bench_model={}; bench_list=nullptr; bench_rows.clear(); bench_initial_nodes.clear();
}
static void bench_update() { state->context->Update(); }
static void bench_finish() { glFinish(); }
static std::vector<Rml::Element*> bench_visible_rows() {
    auto list=bench_list ? bench_list : state->document->GetFirstChild();
    std::vector<Rml::Element*> rows;
    for(int i=0;list && i<list->GetNumChildren();++i) {
        auto child=list->GetChild(i);
        if(child->GetTagName()=="span" && child->GetComputedValues().display()!=Rml::Style::Display::None) rows.push_back(child);
    }
    return rows;
}
static bool bench_verify(const das::TArray<char*>& values) {
    auto rows=bench_visible_rows();
    if(rows.size()!=values.size) { std::printf("row count: %zu != %llu\n",rows.size(),(unsigned long long)values.size); return false; }
    for(size_t i=0;i<rows.size();++i) {
        auto text=rmlui_dynamic_cast<Rml::ElementText*>(rows[i]->GetFirstChild());
        if(!text || text->GetText()!=values[uint32_t(i)]) { std::printf("row mismatch at %zu\n",i); return false; }
    }
    return true;
}
static int bench_identity(bool remember_nodes) {
    auto rows=bench_visible_rows(); int stable=0;
    if(remember_nodes) bench_initial_nodes.clear();
    for(auto row:rows) {
        auto text=rmlui_dynamic_cast<Rml::ElementText*>(row->GetFirstChild());
        if(!text) continue;
        if(remember_nodes) bench_initial_nodes[text->GetText()]=row;
        else { auto it=bench_initial_nodes.find(text->GetText()); if(it!=bench_initial_nodes.end() && it->second==row) ++stable; }
    }
    return stable;
}
