options gen2
options persistent_heap
options gc
options stack=65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Cargo { name:string; quantity:int; notes:array<string> }
struct Form { name:string="Ada"; ready:bool=true }
struct Pane { id:int; model:UiDataModel }
struct App { model:UiDataModel; visible:bool=true; count:int; panes:array<Pane> }
[ui_style]
def sheet() {
    rule(part("scope")) { width(px(400)); padding(px(12)); background(rgb(240,240,230)) }
    rule(part("row")) { display("flex"); height(px(35)) }
    rule(with_class(part("row"),"priority")) { background(rgb(250,230,190)) }
    rule(part("name")) { color(rgb(20,80,110)); width(px(100)) }
    rule(part("edit")) { width(px(200)); height(px(28)) }
}
[ui_component]
def panel(model:UiDataModel) {
    use_style(@@sheet)
    native_data("scope",model) {
        column("fields") {
            text_input("edit") { data_value("form.name") }
            checkbox("ready") { data_checked("form.ready") }
            text("mirror") { data_text("form.name") }
            text("literal","<b> & \"plain\"")
            text("brackets","\{\{not_a_binding\}\}")
            button("choose","Choose") { data_event("click","choose(form.name)"); data_disabled("!form.ready") }
            data_if("notice","form.ready") { text("notice_text","Ready") }
            data_for("row","item","cargo") {
                data_class("priority","item.quantity > 2")
                text("name") { data_text("item.name"); data_attribute("title","item.name"); data_style("opacity","form.ready ? 1 : 0.5") }
                text("quantity") { data_text("item.quantity") }
                button("select","Select") { data_event("click","choose(item.name)") }
                data_for("note","note","item.notes") { text("note_text") { data_text("note") } }
            }
        }
    }
}
[ui_component]
def screen(var app:App) {
    text("managed",app.count)
    button("increment","+") { on_click() { app.count+=1 } }
    when(app.visible) { panel(app.model) }
    box("peers") {
        app.panes |> each_keyed($(item:Pane)=>item.id) $(item:Pane) { panel(item.model) }
    }
}
[ui_component(legacy=true)]
def legacy_panel(model:UiDataModel) {
    native_data("legacy_scope",model) { text("caption") { data_text("form.name") } }
}
def draw(var app:auto) { ui_frame(app) $(value:App) { screen(value) } }
def model(name:string):UiDataModel {
    let result=ui_data_model(name)
    ui_data_bind(result,"form",Form(),true)
    var rows:array<Cargo>
    rows |> push_clone(Cargo(name="First",quantity=2)); rows |> push_clone(Cargo(name="Second",quantity=4))
    rows[0].notes |> push("A"); rows[1].notes |> push("B")
    ui_data_bind(result,"cargo",rows)
    ui_data_on(result,"choose")
    return result
}
[export]
def main(smoke:bool):int {
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Native DSL",900,700,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,900,700)); verify(rui_default_font())
        let first=model("first"); let second=model("second")
        let external=rui_document("<rml><head/><body data-model='first'/></rml>","native-scope-test.rml")
        let nested=rui_create(external,"div","","")
        var rejected=false
        try { rui_data_mount(nested,second.handle,"") } recover { rejected=true }
        verify(rejected,"an inherited native scope must not be silently mixed with managed ownership")
        close_document(external)
        var app=ui_state(App(model=first))
        draw(app)
        let host=ui_find("scope")
        let edit=ui_data_find(host,"edit")
        let row=ui_data_find(host,"row",0)
        let second_row=ui_data_find(host,"row",1)
        verify(host!=0ul && edit!=0ul && row!=0ul && second_row!=0ul && row!=second_row)
        verify(ui_data_find(host,"row",2)==0ul,"data-for template excluded")
        verify(ui_data_find(host,"note_text",1)!=0ul && ui_data_find(host,"note_text",2)==0ul,"nested native aliases")
        verify(!rui_has_attr(row,"id") && !rui_has_attr(second_row,"id"),"native lists have no duplicate IDs")
        verify(rui_computed_property(second_row,"background-color")=="#fae6be","data_class uses scoped state classes")
        verify(rui_get_attr(ui_data_find(host,"name"),"title")=="First")
        verify(rui_get_value(edit)=="Ada")
        verify(find(rui_inner_markup(host),"&lt;b&gt;")>=0,"literal text escaped")
        verify(find(rui_inner_markup(ui_data_find(host,"brackets")),"not_a_binding")>=0,"literal braces are not native expressions")
        ui_clear_stats(); draw(app); draw(app)
        verify(ui_stats().updates==0 && ui_stats().mounts==0,"idle skips component")
        ui_data_set(first,"form.name","Grace"); draw(app)
        verify(rui_get_value(edit)=="Grace" && ui_stats().updates==0,"native write does not traverse component")
        rui_test_event(edit,"change","Lin"); draw(app)
        verify(ui_data_text(first,"form.name")=="Lin")
        rui_test_click(ui_data_find(host,"select",1))
        var calls=0
        ui_data_events(first) $(event:UiDataEvent) { verify(event.arguments[0].text=="Second"); calls+=1 }
        verify(calls==1)
        ui_data_set(first,"form.ready",false); draw(app)
        verify(!rui_visible(ui_data_find(host,"notice")) && rui_has_attr(ui_data_find(host,"choose"),"disabled"))
        var replacement:array<Cargo>; replacement |> push_clone(Cargo(name="Changed",quantity=7))
        ui_data_set(first,"cargo",replacement); unsafe { heap_collect(true,false) }; draw(app)
        verify(ui_data_find(host,"row",1)==0ul && find(rui_inner_markup(host),"Changed")>=0)
        verify(ui_data_find(host,"note_text")==0ul,"nested native rows removed")
        rui_test_click(ui_find("increment")); draw(app)
        verify(ui_data_find(host,"edit")==edit && rui_get_value(edit)=="Lin","managed update preserves native DOM")
        ui_edit(app) $(var value:App) { value.model=second }
        draw(app)
        verify(ui_find("scope")==host && !rui_alive(edit),"model change replaces native subtree only")
        verify(rui_get_value(ui_data_find(host,"edit"))=="Ada")
        ui_data_set(first,"form.name","Old"); draw(app)
        verify(rui_get_value(ui_data_find(host,"edit"))=="Ada","old model detached")
        ui_edit(app) $(var value:App) { value.visible=false }; draw(app)
        verify(!rui_alive(host) && ui_data_alive(second),"unmount does not own public model")
        ui_edit(app) $(var value:App) { value.visible=true }; draw(app)
        verify(ui_find("scope")!=host && ui_data_find(ui_find("scope"),"edit")!=0ul)
        ui_edit(app) $(var value:App) {
            value.panes |> push(Pane(id=10,model=first)); value.panes |> push(Pane(id=20,model=second))
        }; draw(app)
        let peer1=ui_find("scope",10); let peer2=ui_find("scope",20)
        let peer_edit=ui_data_find(peer2,"edit")
        rui_focus(peer_edit); rui_select(peer_edit,1,2)
        verify(peer1!=0ul && peer2!=0ul && peer1!=peer2)
        verify(rui_get_value(ui_data_find(peer1,"edit"))=="Old" && rui_get_value(ui_data_find(peer2,"edit"))=="Ada")
        ui_edit(app) $(var value:App) { let temporary=value.panes[0]; value.panes[0]=value.panes[1]; value.panes[1]=temporary }; draw(app)
        verify(ui_find("scope",10)==peer1 && ui_find("scope",20)==peer2)
        verify(ui_data_find(peer2,"edit")==peer_edit,"keyed reorder preserves native input identity")
        verify(rui_focused(peer_edit) && rui_selection(peer_edit)==int2(1,2),"keyed reorder preserves focus and selection")
        verify(ui_data_find(peer1,"row",1)==0ul && ui_data_find(peer2,"row",2)==0ul,"reorder does not duplicate native rows")
        ui_data_set(second,"form.name","Shared"); draw(app)
        verify(rui_get_value(ui_data_find(peer2,"edit"))=="Shared")
        verify(ui_data_close(second)); draw(app) // No script traversal required for native detach.
        ui_edit(app) $(var value:App) { value.count+=1 }; draw(app)
        verify(rui_alive(peer2),"closed model leaves an inert scope safe to revisit")
        ui_reset(); verify(ui_data_alive(first))
        var legacy_state=ui_state(App(model=first))
        ui_frame(legacy_state) $(value:App) { legacy_panel(value.model) }
        let legacy_host=ui_find("legacy_scope")
        ui_data_set(first,"form.name","Legacy")
        ui_frame(legacy_state) $(value:App) { legacy_panel(value.model) }
        verify(ui_find("legacy_scope")==legacy_host && find(rui_inner_markup(legacy_host),"Legacy")>=0)
        ui_reset()
        verify(rui_warning_count()==0ul)
        rui_shutdown()
        print("PASS: native DataModel DSL, granular updates, input, expressions, lists, events, lifecycle and GC\n")
        return sdl_ok()
    }
    return is_err(result) ? 1 : 0
}
