options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Model { editor,dialog,menu:uint64; note:string="persistent draft" }
var edits,background_clicks,menu_clicks,shows,hides:int
var dismiss_reason=""
var modal_target:uint64

[ui_template]
def frame() {
    window_frame("window") {
        property("position","absolute"); property("z-index","1")
        width(px(240)); height(px(180)); property("margin","0px"); padding(px(0))
        background(rgb(40,50,65))
        slot("body")
    }
}
[ui_component(legacy=true)]
def screen(var model:Model) {
    button("background","Background") {
        width(px(120)); height(px(35))
        on_click() { background_clicks+=1 }
    }
    button("open_modal","Open modal") {
        width(px(120)); height(px(35))
        on_click() { show_document(modal_target,UiDocumentOptions(modal=UiModal.Modal)) }
    }
    document_events(model.editor) {
        on_event("show") $(event:UiEvent) { shows+=1 }
        on_event("hide") $(event:UiEvent) { hides+=1 }
    }
    document_content(model.editor,"body") {
        text_input("draft") {
            width(px(200)); height(px(30))
            bind_value(model.note) $(value:string) { model.note=value; edits+=1 }
        }
        button("editor_button","Editor") { width(px(180)); height(px(40)); on_click() { edits+=1 } }
    }
    document_content(model.dialog,"body") {
        button("dialog_button","Dialog") { width(px(180)); height(px(40)); on_click() { edits+=100 } }
    }
    document_events(model.menu) {
        on_event("dismiss") $(event:UiEvent) { dismiss_reason=event_parameter(event,"reason") }
    }
    document_content(model.menu,"body") {
        button("menu_item","Menu item") {
            width(px(180)); height(px(40))
            on_click() { menu_clicks+=1; hide_document(model.menu) }
        }
    }
}
[export]
def main(smoke:bool):int {
    var model=Model()
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Documents",800,600,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,800,600)); verify(rui_default_font())
        let previous=rui_focus_node()
        model.editor=open_template(@@frame,"Editor",float2(150.,100.),UiDocumentOptions(visible=false))
        model.dialog=open_template(@@frame,"Dialog",float2(150.,100.),UiDocumentOptions(visible=false))
        model.menu=open_template(@@frame,"Menu",float2(0.),UiDocumentOptions(visible=false))
        modal_target=model.dialog
        verify(rui_focus_node()==previous && !document_visible(model.editor),"hidden load cannot steal focus")
        ui_legacy_frame() { screen(model) }
        let draft=ui_find("draft")
        rui_focus(ui_find("background"))
        show_document(model.editor,UiDocumentOptions(focus=UiDocumentFocus.None))
        ui_legacy_frame() { screen(model) }
        verify(rui_focus_node()==ui_find("background") && shows==1,"show without focus")
        show_document(model.editor,UiDocumentOptions(focus=UiDocumentFocus.Auto))
        rui_focus(draft); rui_test_event(draft,"change","saved while hidden")
        ui_legacy_frame() { screen(model) }
        hide_document(model.editor); ui_legacy_frame() { screen(model) }
        verify(hides==1 && rui_focus_node()==ui_find("background"),"hide returns previous focus")
        verify(ui_find("draft")==draft && model.note=="saved while hidden" && rui_alive(draft),"hide retains DOM and draft")
        show_document(model.editor); ui_legacy_frame() { screen(model) }
        verify(ui_find("draft")==draft && shows==3,"show retains incarnation and native show fires on each call")
        // Both are native documents at the same explicit z-index.
        show_document(model.dialog,UiDocumentOptions(focus=UiDocumentFocus.None))
        bring_to_front(model.editor); rui_update()
        rui_test_click(ui_find("draft")); ui_legacy_frame() { screen(model) }
        verify(rui_focus_node()==draft,"front document receives hit-tested input")
        send_to_back(model.editor); rui_update()
        rui_test_click(ui_find("dialog_button")); ui_legacy_frame() { screen(model) }
        if (edits!=101) { panic("back overlap edits={edits}, dialog={rui_bounds(ui_find("dialog_button"))}, editor={rui_bounds(draft)}") }
        hide_document(model.dialog)
        rui_focus(draft)
        show_document(model.dialog,UiDocumentOptions(modal=UiModal.Modal,focus=UiDocumentFocus.Document))
        verify(document_modal(model.dialog) && rui_focus_node()==model.dialog,"modal document focus")
        rui_test_click(ui_find("background")); ui_legacy_frame() { screen(model) }
        verify(background_clicks==0,"modal blocks native background click")
        hide_document(model.dialog)
        verify(rui_focus_node()==draft,"modal restores editor focus")
        // Events already queued before opening the modal cannot reach the background afterwards.
        rui_test_event(ui_find("open_modal"),"click","")
        rui_test_event(ui_find("background"),"click","")
        ui_legacy_frame() { screen(model) }
        verify(background_clicks==0 && document_modal(model.dialog),"queued background command blocked by new modal")
        // A popup can be opened from a modal and returns focus to that modal.
        rui_focus(ui_find("dialog_button"))
        show_popup(model.menu,float2(790.,590.)); ui_legacy_frame() { screen(model) }
        let bounds=rui_bounds(model.menu)
        verify(bounds.x>=0. && bounds.y>=0. && bounds.x+bounds.z<=800. && bounds.y+bounds.w<=600.,"popup clamped to viewport")
        rui_test_key("Escape",false); ui_legacy_frame() { screen(model) }
        verify(!document_visible(model.menu) && dismiss_reason=="escape" && rui_focus_node()==ui_find("dialog_button"),"Escape and modal focus return")
        hide_document(model.dialog)
        rui_focus(ui_find("background"))
        show_popup(model.menu,float2(500.,300.)); ui_legacy_frame() { screen(model) }
        rui_test_click(ui_find("background")); ui_legacy_frame() { screen(model) }
        verify(dismiss_reason=="outside" && background_clicks==0 && !document_visible(model.menu),"outside click consumed including release")
        verify(rui_focus_node()==ui_find("background"),"outside returns focus")
        show_popup(model.menu,float2(500.,300.)); ui_legacy_frame() { screen(model) }
        rui_test_click(ui_find("menu_item")); ui_legacy_frame() { screen(model) }
        verify(menu_clicks==1 && !document_visible(model.menu),"menu item activates and hides")
        show_popup(model.menu,float2(790.,590.)); rui_test_resize(640,480); ui_legacy_frame() { screen(model) }
        let smaller=rui_bounds(model.menu)
        verify(smaller.x+smaller.z<=640. && smaller.y+smaller.w<=480.,"popup reclamped on resize")
        hide_document(model.menu)
        unsafe { heap_collect(true,false) }
        verify(ui_find("draft")==draft && model.note=="saved while hidden","retained editor survives GC")
        close_document(model.menu); close_document(model.dialog); close_document(model.editor)
        verify(!rui_alive(draft) && rui_listener_count()==0,"closing releases descendant handles and document listeners")
        ui_reset(); rui_shutdown()
        print("PASS: hidden load, focus modes, retained drafts, layering, modal isolation, queued input, popup dismissal/clamping, GC and close\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
