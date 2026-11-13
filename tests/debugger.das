options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

var clicks,hotkeys,status_reads,stable_reads:int
struct Model { popup:uint64; show_action:bool=true }
[ui_component(legacy=true)]
def status() { text("status") { status_reads+=1; return debugger_visible() ? "visible" : "hidden" } }
[ui_component(legacy=true)]
def stable() { text("stable") { stable_reads+=1; return "unchanged" } }
[ui_template]
def popup_frame() {
    window_frame("frame") { width(px(200)); height(px(80)); property("position","absolute"); property("z-index","1"); slot("items") }
}
[ui_component(legacy=true)]
def scene(model:Model) {
    status(); stable()
    when(model.show_action) { button("action","Application button") {
        attribute("id","application-button")
        property("position","absolute"); property("left","30px"); property("top","220px"); width(px(200)); height(px(50))
        on_click() { clicks+=1 }
    } }
    document_events(rui_root()) {
        on_event("keydown",UiEventOptions(key="F8")) $(event:UiEvent) { hotkeys+=1 }
        on_event("keyup",UiEventOptions(key="F8")) $(event:UiEvent) { hotkeys+=1 }
    }
    document_content(model.popup,"items") { button("popup_item","Popup item") {} }
}
def debug_button(name:string):uint64 { return rui_document_element(rui_test_debugger_document("menu"),name) }
[export]
def main(smoke:bool):int {
    var model=Model()
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Native debugger",1000,700,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,1000,700)); verify(rui_default_font())
        model.popup=open_template(@@popup_frame,"Popup",float2(100.,400.),UiDocumentOptions(visible=false))
        ui_legacy_frame() { scene(model) }
        let action=ui_find("action"); let base_documents=rui_test_document_count()
        verify(!debugger_ready() && !debugger_visible(),"plugin opt-in")
        debugger_hotkey(); verify(!debugger_ready(),"hotkey registration is lazy")
        rui_focus(action); rui_test_shortcut("F8",0); ui_legacy_frame() { scene(model) }
        verify(debugger_ready() && debugger_visible() && hotkeys==0,"F8 starts plugin and consumes key down/up")
        verify(status_reads==2 && stable_reads==1,"debugger visibility invalidates only readers")
        let debug_documents=rui_test_document_count()
        debugger_init(); verify(rui_test_document_count()==debug_documents && debug_documents>base_documents,"init is idempotent")
        let menu=rui_test_debugger_document("menu")
        let info=rui_test_debugger_document("info")
        let font=rui_local_property(menu,"font-family")
        verify(find(font,"rmlui-debugger-font")>=0,"native embedded debugger font is present")
        rui_css("body \{ font-family: LatoLatin; font-size: 57px; color: red; \}")
        rui_update()
        verify(rui_local_property(menu,"font-family")==font,"application stylesheet cannot replace debugger styles")
        // Restore DSL styles by rebuilding its owned tree; the plugin must remain alive.
        ui_reset(); ui_legacy_frame() { scene(model) }
        var inspected=ui_find("action")
        rui_test_click(debug_button("debug-info-button")); rui_update()
        verify(rui_visible(info),"native Element Info panel opens")
        rui_test_click(inspected); ui_legacy_frame() { scene(model) }
        verify(clicks==0,"first inspector pick must not invoke app callback")
        verify(find(rui_inner_markup(info),"application-button")>=0,"inspector shows the picked native element")
        unsafe { heap_collect(true,false) }
        model.show_action=false; ui_legacy_frame() { scene(model) }
        verify(!rui_alive(inspected) && rui_alive(info),"destroying selected element leaves inspector alive")
        model.show_action=true; ui_legacy_frame() { scene(model) }
        inspected=ui_find("action")
        rui_test_click(debug_button("outlines-button")); rui_update()
        verify(rui_has_class(debug_button("outlines-button"),"open"),"native outlines toggled")
        debugger_show(false); ui_legacy_frame() { scene(model) }
        verify(!debugger_visible() && !rui_visible(info),"hide closes inspector as well as toolbar")
        verify(rui_inner_markup(ui_find("status"))=="hidden","hide invalidates debugger readers")
        verify(!rui_has_class(debug_button("outlines-button"),"open"),"hide turns off outlines")
        rui_test_click(inspected); ui_legacy_frame() { scene(model) }
        verify(clicks==1,"hidden inspector no longer captures clicks")
        show_popup(model.popup,float2(100.,400.)); rui_focus(ui_find("popup_item"))
        debugger_show(); rui_update()
        rui_test_click(debug_button("debug-info-button")); rui_update()
        verify(document_visible(model.popup),"debugger UI clicks cannot dismiss a popup")
        debugger_show(false)
        verify(rui_focused(ui_find("popup_item")),"closing tools restores modal popup focus")
        hide_document(model.popup)
        debugger_shutdown(); rui_update()
        verify(!debugger_ready() && rui_test_document_count()==base_documents && !rui_alive(menu),"shutdown removes native debug documents")
        rui_test_shortcut("F8",0); ui_legacy_frame() { scene(model) }
        verify(!debugger_ready(),"shutdown disables shortcut")
        debugger_show(); verify(debugger_ready(),"plugin can restart")
        close_document(model.popup); ui_reset(); rui_shutdown()
        // Automatic plugin teardown must also support an entirely new context.
        verify(rui_init(window,renderer,1000,700)); verify(rui_default_font())
        debugger_show(); verify(debugger_visible()); debugger_shutdown(); rui_update()
        verify(rui_test_document_count()==1,"context restart cleans debugger state")
        rui_shutdown()
        print("PASS: native debugger startup, hotkey, reactive status, inspection, styles, popup focus, hide/shutdown, GC and restart\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
