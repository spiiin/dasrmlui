options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope
require dassdl3/sdl3_gl_egl

struct Row { id:int; text:string }
struct Model { rows:array<Row> }
[ui_component(legacy=true)]
def view(model:Model) {
    box("list") {
        model.rows |> each_keyed($(row:Row)=>row.id) $(row:Row) { text("row",row.text) }
    }
}
[ui_component]
def hybrid_view(model:Model) {
    box("list") {
        model.rows |> each_keyed($(row:Row)=>row.id) $(row:Row) { text("row",row.text) }
    }
}
def mutate(var model:Model; a,b:array<string>; native:bool; scenario,frame,count:int) {
        if (scenario==1) {
            let i=(frame*17)%count; let id=model.rows[i].id
            model.rows[i].text=model.rows[i].text==a[id] ? b[id] : a[id]
            if (native) { bench_native_set(i,model.rows[i].text) }
        } elif (scenario==2) {
            for (i in range(count)) {
                let id=model.rows[i].id
                model.rows[i].text=frame%2==0 ? b[id] : a[id]
                if (native) { bench_native_set(i,model.rows[i].text) }
            }
        } elif (scenario==3) {
            let last=model.rows[count-1]
            for (offset in range(count-1)) { let i=count-1-offset; model.rows[i]=model.rows[i-1] }
            model.rows[0]=last
            if (native) { bench_native_rotate() }
        }
}
[ui_action]
def mutate_tracked(var model:Model; a,b:array<string>; scenario,frame,count:int) {
        if (scenario==1) {
            let i=(frame*17)%count; let id=model.rows[i].id
            model.rows[i].text=model.rows[i].text==a[id] ? b[id] : a[id]
        } elif (scenario==2) {
            for (i in range(count)) {
                let id=model.rows[i].id
                model.rows[i].text=frame%2==0 ? b[id] : a[id]
                }
        } elif (scenario==3) {
            let last=model.rows[count-1]
            for (offset in range(count-1)) { let i=count-1-offset; model.rows[i]=model.rows[i-1] }
            model.rows[0]=last
        }
}
def render_model(mode:int; model:Model; state:$UiState<Model>?) {
    if (mode==2) { ui_frame(state) $(owned:Model) { hybrid_view(owned) } }
    else { ui_legacy_frame() { view(model) } }
}
def collect() { unsafe { heap_collect(true,false) } }
def run_case(mode:int; scenario,round,count,warmup,samples:int; memory,smoke:bool) {
    let native=mode==1
    var inscope model=Model()
    var inscope a,b,expected:array<string>
    for (i in range(count)) {
        a |> push("A{1000000+i}"); b |> push("B{1000000+i}")
        expected |> push(a[i]); model.rows |> push(Row(id=i,text=a[i]))
    }
    var state:$UiState<Model>?
    if (mode==2) { state=ui_state(model); clear(model.rows) }
    bench_case(mode,scenario,round,memory)
    if (native) { bench_native_setup(expected); bench_native_bind(); bench_update() }
    else { render_model(mode,model,state); bench_css(); bench_update() }
    rui_render(); bench_finish(); collect()
    verify(bench_verify(expected),"identical initial DOM contents")
    bench_identity(true)
    // First rotate has a visible identity difference: keyed DSL vs positional data-for.
    if (scenario==3) {
        if (mode==2) { ui_edit(state) $(var owned:Model) { mutate_tracked(owned,a,b,3,0,count) } }
        else { mutate(model,a,b,native,3,0,count) }
        for (row,i in model.rows,count()) { expected[i]=row.text }
        if (mode==2) { ui_read(state) $(owned:Model) { for (row,i in owned.rows,count()) { expected[i]=row.text } } }
        if (native) { bench_native_bind() } else { render_model(mode,model,state) }
        bench_update()
        verify(bench_verify(expected))
        verify(bench_identity(false)==(native ? 0 : count),"reorder semantics must be reported, not assumed equal")
    }
    for (frame in range(warmup+samples)) {
        let record=frame>=warmup
        bench_begin(6,frame,record)
        if (mode==2) { ui_edit(state) $(var owned:Model) { mutate_tracked(owned,a,b,scenario,frame,count) } }
        else { mutate(model,a,b,native,scenario,frame,count) }
        bench_end()
        if (smoke && mode==0) { ui_clear_stats() }
        let reads=rui_hybrid_reads()
        bench_begin(0,frame,record)
        if (native) { bench_native_bind() } else { render_model(mode,model,state) }
        bench_end()
        if (smoke && mode==0) {
            verify(ui_stats().binding_updates==(scenario==1 ? 1 : scenario==2 ? count : 0),
                "only changed keyed text bindings must evaluate")
        }
        if (smoke && mode==2) {
            verify(rui_hybrid_reads()-reads==uint64(scenario==1 ? 1 : scenario==2 ? count : 0),"native scheduler visits changed leaves only")
        }
        bench_begin(1,frame,record); bench_update(); bench_end()
        bench_begin(2,frame,record); rui_render(); bench_end()
        bench_begin(3,frame,record); bench_finish(); bench_end()
        // Explicit, equally placed GC bounds memory in the persistent interpreter.
        // Recorded separately, not hidden inside Update or thrown out of the CSV.
        bench_begin(4,frame,record); collect(); bench_end()
        if (smoke || frame==warmup+samples-1) {
            for (row,i in model.rows,count()) { expected[i]=row.text }
            if (mode==2) { ui_read(state) $(owned:Model) { for (row,i in owned.rows,count()) { expected[i]=row.text } } }
            verify(bench_verify(expected),"binding output/order after update")
        }
    }
    if (smoke) { verify(rui_screenshot("logs/bench_{native ? "native" : mode==2 ? "hybrid" : "dsl"}_{scenario}.png")) }
    verify(rui_warning_count()==0ul)
    if (native) { bench_native_close() } else { ui_reset() }
    collect()
}
[export]
def main(smoke:bool):int {
    let count=smoke ? 32 : bench_config("RUI_BENCH_ROWS",1000)
    verify(count>=2,"at least two rows required for reordering")
    let samples=smoke ? 4 : bench_config("RUI_BENCH_SAMPLES",120)
    let warmup=smoke ? 2 : bench_config("RUI_BENCH_WARMUP",30)
    let rounds=smoke ? 1 : bench_config("RUI_BENCH_ROUNDS",4)
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        set_gl_attribute(SDL_GLAttr.GL_CONTEXT_MAJOR_VERSION,3) |> sdl_try
        set_gl_attribute(SDL_GLAttr.GL_CONTEXT_MINOR_VERSION,3) |> sdl_try
        set_gl_attribute(SDL_GLAttr.GL_CONTEXT_PROFILE_MASK,int(SDL_GL_CONTEXT_PROFILE_CORE)) |> sdl_try
        set_gl_attribute(SDL_GLAttr.GL_STENCIL_SIZE,8) |> sdl_try
        let window:SDL_Window?=with_window("Data binding benchmark",800,700,SDL_WINDOW_OPENGL | SDL_WINDOW_HIDDEN) |> sdl_use
        let context:SDL_GLContextState?=window |> with_gl_context() |> sdl_use
        // Timing runs have C++ allocation counting disabled. One separate memory run.
        for (round in range(rounds+1)) {
            for (scenario in range(4)) {
                for (turn in range(3)) {
                    let mode=(round+scenario+turn)%3
                    verify(rui_init_gl(window,800,700)); verify(rui_default_font()); rui_test_display_scale(1.)
                    if (round==0 && scenario==0 && turn==0) {
                        verify(bench_info(),"C++ allocation counters preserve the runtime allocator")
                        bench_case(0,0,-1,false)
                        for (sample in range(200)) { bench_begin(5,sample,true); bench_end() }
                    }
                    run_case(mode,scenario,round,count,warmup,samples,round==rounds,smoke)
                    ui_reset(); rui_shutdown(); collect()
                }
            }
            print("benchmark: round {round+1}/{rounds+1}, rows={count}, samples={samples}\n")
        }
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    bench_save(smoke ? "logs/binding-benchmark-smoke.csv" : "logs/binding-benchmark-{count}.csv")
    print("PASS: binding benchmark, DOM equality, reorder identity, separated stages and memory pass\n")
    return 0
}
