options gen2
options persistent_heap
options gc
options stack=65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Row { title:string; amount:int }
struct Person { name:string="Ada"; enabled:bool=true }
struct Overlay { caption:string="Hybrid" }
[ui_component]
def overlay(model:Overlay) { text("hybrid_caption",model.caption) }
def rejected(body:block) {
    var caught=false
    try { invoke(body) } recover { caught=true }
    verify(caught,"invalid public model operation must fail")
}
[export]
def main(smoke:bool):int {
    var old=UiDataModel()
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Data models",1000,700,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        // rejected() below recovers from panics, and after a recovered panic the
        // scope's own handle no longer reads back. The restart at the end used to
        // pass whatever was there, which happened to be non-null. Keep a copy.
        let kept_renderer=renderer
        verify(rui_init(window,renderer,1000,700)); verify(rui_default_font())
        let model=ui_data_model("manifest"); old=model
        let second=ui_data_model("secondary")
        verify(ui_data_exists("manifest") && ui_data_model_count()==2)
        ui_data_bind(model,"person",Person(),true)
        ui_data_bind(model,"headline","Manifest")
        ui_data_bind(model,"shade","#44aaff")
        var rows:array<Row>
        ui_data_bind(model,"rows",rows,true)
        ui_data_on(model,"choose")
        ui_data_bind(second,"headline","Other model")
        rows |> push(Row(title="first",amount=2)); rows |> push(Row(title="second",amount=4))
        ui_data_set(model,"rows",rows)
        rows[0].title="outside"
        verify(ui_data_text(model,"rows[0].title")=="first","deep copy")
        rui_resource("data-test.rml","<rml><head><style>body \{ font-family:LatoLatin; font-size:18px; \} .row \{ display:block; \}</style></head><body style=\"font-family:LatoLatin; font-size:18px\" data-model='manifest'><h1 id='headline'>\{\{headline\}\}</h1><input id='name' data-value='person.name'/><span id='mirror'>\{\{person.name\}\}</span><input id='enabled' type='checkbox' data-checked='person.enabled'/><div id='conditional' data-if='person.enabled'>Enabled</div><div id='styled' data-class-active='person.enabled' data-attr-title='person.name' data-style-color='shade'>Styled</div><div id='rows'><div class='row' data-for='entry : rows'><span>\{\{entry.title\}\} / \{\{entry.amount\}\}</span><button data-event-click='choose(entry.title, entry.amount, person.enabled)'>Choose</button></div></div><button id='rename' data-event-click=\"person.name = 'Native assignment'\">Rename</button></body></rml>")
        let doc=ui_load_rml("data-test.rml")
        let other=rui_document("<rml><head/><body style=\"font-family:LatoLatin; font-size:18px\" data-model='secondary'><span id='headline'>\{\{headline\}\}</span></body></rml>","secondary.rml")
        verify(doc!=0ul && other!=0ul)
        rui_update()
        verify(!ui_data_is_dirty(model,"rows"))
        let name=rui_document_element(doc,"name")
        verify(rui_get_value(name)=="Ada" && find(rui_inner_markup(doc),"first / 2")>=0)
        verify(find(rui_inner_markup(other),"Other model")>=0)
        rui_test_event(name,"change","Grace")
        rui_update()
        verify(ui_data_text(model,"person.name")=="Grace" && find(rui_inner_markup(rui_document_element(doc,"mirror")),"Grace")>=0)
        verify(rui_get_attr(rui_document_element(doc,"styled"),"title")=="Grace")
        rui_test_click(rui_document_element(doc,"rename")); rui_update()
        verify(ui_data_text(model,"person.name")=="Native assignment")
        let list=rui_document_element(doc,"rows")
        // data-for retains a hidden template beside its generated rows.
        var chosen=0ul
        for (i in range(rui_child_count(list))) {
            let row=rui_child(list,i)
            if (rui_child_count(row)==2 && rui_visible(row)) { chosen=rui_child(row,1); break }
        }
        verify(chosen!=0ul); rui_test_click(chosen)
        var callbacks=0
        ui_data_events(model) $(event:UiDataEvent) {
            verify(event.name=="choose" && event.kind=="click" && event.target==chosen)
            verify(length(event.arguments)==3 && event.arguments[0].text=="first" && event.arguments[1].integer==2 && event.arguments[2].boolean)
            unsafe { heap_collect(true,false) }
            verify(event.arguments[0].text=="first","callback snapshots survive GC")
            ui_data_set(model,"headline","Selected first"); callbacks+=1
        }
        verify(callbacks==1); rui_update()
        verify(find(rui_inner_markup(doc),"Selected first")>=0)
        rui_test_click(chosen); rui_test_click(chosen)
        rejected() { ui_data_events(model) $(event:UiDataEvent) { panic("callback failure") } }
        var remaining=0
        ui_data_events(model) $(event:UiDataEvent) { remaining+=1 }
        verify(remaining==1,"failed callback consumes its event and releases the drain guard")
        rui_test_click(chosen)
        ui_data_events(model) $(event:UiDataEvent) { rui_test_click(chosen) }
        remaining=0; ui_data_events(model) $(event:UiDataEvent) { remaining+=1 }
        verify(remaining==1,"new events wait for the next drain")
        ui_data_set(model,"person.enabled",false); rui_update()
        verify(!rui_checked(rui_document_element(doc,"enabled")) && !rui_has_class(rui_document_element(doc,"styled"),"active"))
        rui_test_click(rui_document_element(doc,"enabled")); rui_update()
        verify(ui_data_bool(model,"person.enabled"),"native checkbox controller writes back")
        ui_data_set(model,"rows[0].amount",7)
        verify(ui_data_is_dirty(model,"rows")); ui_data_dirty_all(model); rui_update()
        verify(find(rui_inner_markup(doc),"first / 7")>=0)
        rows |> clear(); ui_data_set(model,"rows",rows); rui_update(); verify(ui_data_size(model,"rows")==0)
        var wrong:array<int>; wrong |> push(1)
        rejected() { ui_data_set(model,"rows",wrong) }
        rows |> push(Row(title="rebuilt",amount=9)); ui_data_set(model,"rows",rows)
        unsafe { heap_collect(true,false) }; rui_update(); verify(find(rui_inner_markup(doc),"rebuilt / 9")>=0)
        rejected() { ui_data_set(model,"rows[0].amount","wrong type") }
        verify(ui_data_int(model,"rows[0].amount")==9,"failed write is atomic")
        rejected() { ui_data_set(model,"rows[99].amount",1) }
        rejected() { ui_data_bind(model,"headline","duplicate") }
        rejected() { let duplicate=ui_data_model("manifest") }
        rejected() { let reserved=ui_data_model("dasrmlui") }
        rejected() { ui_data_dirty(model,"person.name") }
        rejected() { ui_data_on(model,"choose") }
        var state=ui_state(Overlay())
        ui_frame(state) $(value:Overlay) { overlay(value) }
        verify(ui_data_exists("dasrmlui") && ui_data_model_count()==3,"hybrid is a Context model")
        verify(ui_data_debugger()); verify(ui_data_debugger(),"opening twice keeps panel visible")
        rui_test_advance_time(2.0lf); rui_update()
        let panel=rui_test_debugger_document("data-models")
        verify(panel!=0ul && rui_visible(panel),"native Data Models panel")
        let markup=rui_inner_markup(panel)
        verify(find(markup,"manifest")>=0 && find(markup,"dasrmlui")>=0 && find(markup,"rebuilt")>=0,"Debugger reflects native structs, arrays and hybrid")
        ui_reset(); verify(!ui_data_exists("dasrmlui") && ui_data_exists("manifest"),"DSL reset preserves external models")
        verify(ui_data_close(model) && !ui_data_close(model) && !ui_data_alive(model))
        rui_test_advance_time(3.0lf); rui_update()
        verify(find(rui_inner_markup(panel),"manifest")<0 && find(rui_inner_markup(panel),"secondary")>=0,"Debugger follows model removal")
        debugger_shutdown()
        rejected() { ui_data_set(model,"headline","stale") }
        rui_update(); verify(rui_alive(doc),"model removal detaches a live document safely")
        close_document(doc); close_document(other)
        verify(ui_data_close(second) && ui_data_model_count()==0)
        verify(rui_warning_count()==0ul)
        let disposable=ui_data_model("disposable")
        ui_data_bind(disposable,"caption","Close me"); ui_data_on(disposable,"close")
        let disposable_doc=rui_document("<rml><head/><body style='font-family:LatoLatin' data-model='disposable'><button id='close' data-event-click='close()'>Close</button></body></rml>","disposable.rml")
        rui_update(); rui_test_click(rui_document_element(disposable_doc,"close"))
        ui_data_events(disposable) $(event:UiDataEvent) { verify(ui_data_close(disposable)); unsafe { heap_collect(true,false) } }
        close_document(disposable_doc); verify(!ui_data_alive(disposable))
        rui_shutdown()
        verify(rui_init(window,kept_renderer,1000,700)); verify(rui_default_font())
        let fresh=ui_data_model("manifest"); verify(fresh.handle!=old.handle && !ui_data_alive(old))
        ui_data_bind(fresh,"headline","after restart")
        let live=rui_document("<rml><head/><body style=\"font-family:LatoLatin; font-size:18px\" data-model='manifest'>\{\{headline\}\}</body></rml>","restart.rml")
        rui_update(); verify(rui_alive(live))
        rui_shutdown(); verify(!ui_data_alive(fresh))
        unsafe { heap_collect(true,false) }
        print("PASS: public DataModel, external RML, native data views/controllers, callbacks, Context/Debugger, GC and restart\n")
        return sdl_ok()
    }
    return is_err(result) ? 1 : 0
}
