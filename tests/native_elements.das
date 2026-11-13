options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require daslib/algorithm
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Memory { name:string; samples:array<float>; paints:int }
struct Item { id:int; value:string="25" }
struct Model { items:array<Item>; shown:bool=true }
var instances:table<uint64;Memory>
var created,destroyed,attributes,resizes,paints,updates,reads,clicks:int
def source(value:string):string { reads+=1; return value }
def install(seed:string) {
    // The captured string outlives this stack frame; the registry must root it.
    register_native_element("test-meter",@(event:UiNativeEvent) {
        let id=event.element
        if (event.kind==UiNativeKind.Create) {
            var memory=Memory(name="{seed}:{id}")
            for (i in range(40)) { memory.samples |> push(float(i)) }
            instances[id] <- memory
            created+=1
        } elif (event.kind==UiNativeKind.Attribute) {
            if (event.name=="value") { attributes+=1 }
            if (event.name=="wide") { native_set_intrinsic(id,float2(120.,30.)) }
        } elif (event.kind==UiNativeKind.Resize) { resizes+=1 }
        elif (event.kind==UiNativeKind.Paint) {
            verify(key_exists(instances,id)); verify(instances[id].samples[39]==39.)
            verify(find(instances[id].name,seed)==0,"captured string and instance arrays survive GC")
            unsafe { heap_collect(true,false) }
            native_rect(id,float4(0.,0.,event.size.x,event.size.y),rgb(50,180,130))
            native_line(id,float2(0.,0.),event.size,3.,rgb(250,220,90))
            instances[id].paints+=1; paints+=1
        } elif (event.kind==UiNativeKind.Destroy) {
            verify(!rui_alive(id),"destroy receives an invalidated stable ID")
            verify(key_exists(instances,id)); instances |> erase(id); destroyed+=1
        }
    },float2(80.,30.))
    if (!native_registered("test-clock")) { register_native_element("test-clock",@(event:UiNativeEvent) {
        if (event.kind==UiNativeKind.Update) { updates+=1; native_invalidate(event.element) }
        elif (event.kind==UiNativeKind.Paint) { native_rect(event.element,float4(0.,0.,20.,20.),rgb(200,90,100)) }
    },float2(20.,20.),true) }
}
[ui_template]
def native_frame() {
    window_frame("frame") {
        width(px(240)); height(px(150))
        native_element("static_meter","test-meter") { attribute("value","60"); width(px(100)); height(px(40)) }
        slot("body")
    }
}
[ui_component(legacy=true)]
def row_view(item:Item) {
    native_element("meter","test-meter") {
        attribute("value",source(item.value))
        on_click() { clicks+=1 }
    }
}
[ui_component(legacy=true)]
def screen(var model:Model) {
    column("root") {
        when($()=>model.shown) {
            model.items |> each_keyed($(item:Item)=>item.id) $(item:Item) { row_view(item) }
        }
        native_element("clock","test-clock")
    }
}
[export]
def main(smoke:bool):int {
    var model=Model()
    model.items |> push <| Item(id=1)
    model.items |> push <| Item(id=2)
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Native element lifecycle",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480)); verify(rui_default_font()); rui_test_display_scale(1.)
        install("captured-{17}")
        unsafe { heap_collect(true,false) }
        ui_legacy_frame() { screen(model) }; rui_render(); rui_native_check()
        let first=ui_find("meter",1); let second=ui_find("meter",2)
        verify(rui_is_native(first) && rui_is_native(second)); verify(created==2 && destroyed==0)
        verify(native_instance_count("test-meter")==2 && length(instances)==2)
        verify(rui_intrinsic_size(first)==float2(80.,30.) && resizes>=2 && paints==2)
        verify(!unregister_native_element("test-meter"),"cannot unregister an instancer with live elements")
        let old_updates=updates; let old_paints=paints
        ui_clear_stats(); ui_legacy_frame() { screen(model) }; rui_render()
        verify(ui_stats().binding_updates==0 && reads==2 && paints==old_paints,"native geometry remains cached on idle frames")
        verify(updates>old_updates,"native update works while DSL component is cached")
        model.items[0].value="75"; ui_legacy_frame() { screen(model) }; rui_render()
        verify(reads==3 && paints==old_paints+1 && attributes==3,"only changed attribute/binding/geometry updates")
        let saved_paints=instances[first].paints
        reverse(model.items); ui_legacy_frame() { screen(model) }
        verify(ui_find("meter",1)==first && instances[first].paints==saved_paints && created==2 && destroyed==0)
        unsafe { heap_collect(true,false) }
        rui_test_click(first); ui_legacy_frame() { screen(model) }; verify(clicks==1,"normal native hit testing and DSL event listener")
        rui_attr(first,"wide","yes"); rui_update(); verify(rui_intrinsic_size(first)==float2(120.,30.))
        set_ui_scale(2.); ui_legacy_frame() { screen(model) }
        verify(rui_intrinsic_size(first)==float2(240.,60.)); set_ui_scale(1.)
        let doc=open_template(@@native_frame,"Native template",float2(300.,0.)); rui_update(); rui_render()
        let static_meter=rui_document_element(doc,"static_meter")
        verify(rui_is_native(static_meter) && native_instance_count("test-meter")==3 && created==3)
        close_document(doc); rui_update()
        verify(!rui_alive(static_meter) && destroyed==1 && length(instances)==2)
        model.shown=false; ui_legacy_frame() { screen(model) }
        verify(!rui_alive(first) && !rui_alive(second) && destroyed==3 && empty(instances))
        verify(unregister_native_element("test-meter"))
        var rejected=false
        try { open_template(@@native_frame,"Missing registration",float2(0.)) } recover { rejected=true }
        verify(rejected,"cached templates cannot silently instantiate a generic element after unregister")
        install("renewed-{19}")
        native_invalidate(first); verify(!rui_native_intrinsic(first,float2(1.,1.)),"stale IDs cannot address new elements")
        model.shown=true; ui_legacy_frame() { screen(model) }; rui_render()
        verify(ui_find("meter",1)!=first && created==5)
        ui_reset(); verify(destroyed==5 && empty(instances) && native_instance_count("test-meter")==0)
        verify(native_registered("test-meter"),"reset keeps type registrations")
        verify(unregister_native_element("test-meter") && !native_registered("test-meter"))
        verify(native_handler_count()==1)
        rui_shutdown(); verify(native_handler_count()==0,"shutdown releases GC roots")
        verify(rui_init(window,renderer,640,480)); verify(rui_default_font())
        install("restart-{23}"); ui_legacy_frame() { screen(model) }; rui_render()
        verify(native_instance_count("test-meter")==2)
        // Direct native shutdown must release live objects and callbacks exactly once.
        rui_shutdown(); verify(destroyed==7 && empty(instances) && native_handler_count()==0)
        rui_native_check(); ui_reset(); rui_shutdown()
        unsafe { heap_collect(true,false) }
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    print("PASS: native instancing, captured callbacks, GC, paint cache, keyed lifetime, template, unregister and shutdown\n")
    return 0
}
