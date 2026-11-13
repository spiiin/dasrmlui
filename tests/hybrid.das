options gen2
options persistent_heap
options gc
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope
struct Item { id:int; title:string }
struct Model { title:string="First"; css:string="0.5"; visible:bool=true; enabled:bool=true; number:int=1; rows:array<Item> }
var bodies=0
var external_value="outside"
var changed=ui_signal()
def external_caption(title:string):string { return "{title}: {external_value}" }
def opaque_ui(title:string) { text("opaque-site","opaque",title) }
[ui_component]
def signal_view(model:Model) {
    ui_watch(changed)
    text("external") { return external_caption(model.title) }
}
[ui_component]
def helper_view(model:Model) {
    text("direct",model.title)
    opaque_ui(model.title)
}
[ui_component]
def temporary_getter(model:Model) {
    let temporary="getter: {model.title}"
    text("temporary") { return temporary }
    text("direct",model.title)
}
[ui_action]
def rename(var model:Model; value:string) { model.title=value }
[ui_action]
def row_title(var model:Model; index:int; value:string) { model.rows[index].title=value }
[ui_action]
def rotate(var model:Model) { let last=model.rows[1]; model.rows[1]=model.rows[0]; model.rows[0]=last }
[ui_action]
def show(var model:Model; flag:bool) { model.visible=flag }
[ui_action]
def enable(var model:Model; flag:bool) { model.enabled=flag }
[ui_action]
def increment(var model:Model) { model.number+=1 }
[ui_action]
def rekey(var model:Model; index,key:int) { model.rows[index].id=key }
[ui_action]
def style_value(var model:Model; value:string) { model.css=value }
[ui_action]
def add(var model:Model; id:int) { model.rows |> push(Item(id=id,title="new")) }
[ui_action]
def remove(var model:Model) { model.rows |> erase(length(model.rows)-1) }
[ui_component]
def conditional_attribute(var model:Model) {
    box("owner") {
        when(model.visible) { attribute("title",model.title) }
        when(model.visible) { property("opacity",model.css) }
        when(!model.visible) { property("opacity","0.8") }
        text("mirror",model.title)
        button("toggle","Toggle") { on_click() { model.visible=!model.visible } }
    }
}
[ui_component]
def temporary_values(model:Model) {
    let temporary="copy: {model.title}"
    text("temporary",temporary)
    text("real",model.title)
}
[ui_component]
def ordinary_if(model:Model) {
    text("flag",model.visible)
    if (model.visible) { text("branch","present") }
}
[ui_component]
def screen(var model:Model) {
    bodies+=1
    column("screen") {
        text("title",model.title)
        text("number",model.number)
        text("visible",model.visible)
        text_input("input") { bind_value(model.title) $(value:string) { if (!empty(value)) { model.title=value } } }
        checkbox("check") { bind_checked(model.enabled) $(value:bool) { model.enabled=value } }
        box("conditional") {
            class_if("active",model.enabled)
            when(model.visible) { text("inside","Shown") }
        }
        model.rows |> each_keyed($(item:Item)=>item.id) $(item:Item) { text("item",item.title); text("key",item.id) }
    }
}
[export]
def main(smoke:bool):int {
    var model=Model()
    add(model,1); add(model,2)
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("hybrid test",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480)); verify(rui_default_font())
        rt_hybrid_frame(model) { screen(model) }
        let initial=bodies; let reads=rui_hybrid_reads(); let first=ui_find("item",1)
        verify(find(rui_markup(),"First")>=0 && rui_get_value(ui_find("input"))=="First")
        for (i in range(10)) { rt_hybrid_frame(model) { screen(model) } }
        verify(bodies==initial && rui_hybrid_reads()==reads,"idle must not visit components or native getters")
        rename(model,"Second <&>")
        rt_hybrid_frame(model) { screen(model) }
        verify(bodies==initial && rui_hybrid_reads()==reads+2,"one scalar updates its two native views only")
        let same_reads=rui_hybrid_reads()
        rename(model,"Second <&>"); rt_hybrid_frame(model) { screen(model) }
        verify(rui_hybrid_reads()==same_reads,"equal writes do not dirty native variables")
        increment(model); rt_hybrid_frame(model) { screen(model) }
        verify(model.number==2 && bodies==initial,"compound assignment is tracked")
        verify(rui_get_value(ui_find("input"))=="Second <&>")
        row_title(model,0,"row changed")
        rt_hybrid_frame(model) { screen(model) }
        verify(bodies==initial && ui_find("item",1)==first)
        rotate(model)
        rt_hybrid_frame(model) { screen(model) }
        verify(ui_find("item",1)==first,"keyed identity survives native scheduling")
        row_title(model,1,"after reorder")
        let before=bodies
        rt_hybrid_frame(model) { screen(model) }
        verify(bodies==before && find(rui_markup(),"after reorder")>=0,"subscriptions follow moved rows")
        rui_test_event(ui_find("input"),"change","Edited")
        rt_hybrid_frame(model) { screen(model) }
        verify(model.title=="Edited" && rui_get_value(ui_find("input"))=="Edited")
        rui_test_event(ui_find("input"),"change","")
        rt_hybrid_frame(model) { screen(model) }
        verify(model.title=="Edited" && rui_get_value(ui_find("input"))=="Edited","native input restores rejected edit")
        verify(rui_checked(ui_find("check")))
        let before_check=bodies
        enable(model,false); rt_hybrid_frame(model) { screen(model) }
        verify(!rui_checked(ui_find("check")) && bodies==before_check,"checked view updates without component traversal")
        rui_test_click(ui_find("check")); rt_hybrid_frame(model) { screen(model) }
        verify(model.enabled && rui_checked(ui_find("check")),"native checked view and tracked input setter agree")
        let hidden=ui_find("inside")
        show(model,false); rt_hybrid_frame(model) { screen(model) }
        verify(!rui_alive(hidden))
        show(model,true); rt_hybrid_frame(model) { screen(model) }
        verify(ui_find("inside")!=hidden)
        let old_key=ui_find("item",2)
        rekey(model,0,7); rt_hybrid_frame(model) { screen(model) }
        verify(!rui_alive(old_key) && ui_find("item",7)!=0ul,"key reads invalidate structure even if also native-bound")
        add(model,3); rt_hybrid_frame(model) { screen(model) }
        remove(model); rt_hybrid_frame(model) { screen(model) }
        let capacity=rui_hybrid_capacity()
        for (i in range(10)) {
            add(model,3); rt_hybrid_frame(model) { screen(model) }
            remove(model); rt_hybrid_frame(model) { screen(model) }
            unsafe { heap_collect(true,false) }
        }
        verify(rui_hybrid_capacity()==capacity,"retired native variables must be reused")
        verify(rui_warning_count()==0ul)
        ui_reset(); verify(rui_hybrid_live()==0)
        rt_hybrid_frame(model) { screen(model) }
        verify(rui_get_value(ui_find("input"))=="Edited")
        ui_reset()
        show(model,true)
        rt_hybrid_frame(model) { conditional_attribute(model) }
        let owner=ui_find("owner")
        verify(rui_get_attr(owner,"title")=="Edited" && rui_hybrid_live()==3)
        verify(rui_local_property(owner,"opacity")=="0.5")
        rui_test_click(ui_find("toggle")); rui_test_click(ui_find("toggle"))
        rt_hybrid_frame(model) { conditional_attribute(model) }
        verify(model.visible && rui_hybrid_live()==3 && rui_get_attr(owner,"title")=="Edited",
            "several event reconciles retire and remount native bindings independently")
        show(model,false); rt_hybrid_frame(model) { conditional_attribute(model) }
        verify(rui_hybrid_live()==1,"conditional native binding retires even when its element survives")
        verify(rui_local_property(owner,"opacity")=="0.8","fallback style overrides retired native style")
        style_value(model,"0.2"); rt_hybrid_frame(model) { conditional_attribute(model) }
        verify(rui_local_property(owner,"opacity")=="0.8")
        rename(model,"Only mirror"); rt_hybrid_frame(model) { conditional_attribute(model) }
        verify(rui_get_attr(owner,"title")=="Edited" && find(rui_markup(),"Only mirror")>=0)
        show(model,true); rt_hybrid_frame(model) { conditional_attribute(model) }
        verify(rui_get_attr(owner,"title")=="Only mirror" && rui_hybrid_live()==3)
        verify(rui_local_property(owner,"opacity")=="0.2")
        ui_reset()
        rt_hybrid_frame(model) { temporary_values(model) }
        unsafe { heap_collect(true,false) }
        rename(model,"Temporary safe")
        rt_hybrid_frame(model) { temporary_values(model) }
        verify(find(rui_markup(),"copy: Temporary safe")>=0,"temporary source uses fallback, never a retained stack address")
        ui_reset()
        show(model,true); rt_hybrid_frame(model) { ordinary_if(model) }
        let branch=ui_find("branch")
        show(model,false); rt_hybrid_frame(model) { ordinary_if(model) }
        verify(!rui_alive(branch),"ordinary if reads also invalidate structure")
        ui_reset()
        rt_hybrid_frame(model) { signal_view(model) }
        external_value="signal delivered"; ui_touch(changed)
        rt_hybrid_frame(model) { signal_view(model) }
        verify(find(rui_markup(),"signal delivered")>=0,"ui_watch forces opaque getter even with unchanged explicit argument")
        ui_reset()
        rt_hybrid_frame(model) { helper_view(model) }
        rename(model,"helper refreshed"); rt_hybrid_frame(model) { helper_view(model) }
        verify(rui_inner_markup(ui_find("opaque"))=="helper refreshed","opaque UI helpers use conservative structural traversal")
        ui_reset()
        rt_hybrid_frame(model) { temporary_getter(model) }
        rename(model,"getter refreshed"); rt_hybrid_frame(model) { temporary_getter(model) }
        verify(find(rui_markup(),"getter: getter refreshed")>=0,"dependency on temporary also uses fallback")
        ui_reset(); rui_shutdown()
        print("PASS: hybrid native views, tracked writes, idle, input, keyed identity, structural fallback and GC\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
