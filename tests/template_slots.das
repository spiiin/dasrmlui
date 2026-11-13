options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Model { ids:array<int>; notes:bool=true; destination:string="status_readout"; status:string="Ready" }
struct Document { handle:uint64; index:int }
struct Draft { index:int; part_name:string; value:string="draft" }
struct Counter { value:int }
var documents:array<uint64>
var mounts,unmounts,moving_mounts,moving_unmounts,definitions:int

[ui_template]
def frame() {
    definitions+=1
    window_frame("frame") {
        width(px(300)); height(px(400))
        title_slot("title")
        column("layout") {
            slot("cargo_manifest") { padding(px(7)) }
            row("details") { slot("mission_notes") }
            // Names can be supplied by ordinary daScript code.
            for (name in array<string>("status_readout","alternate_readout","unused")) { slot(name) }
        }
    }
}
[ui_template]
def static_frame() { window_frame("frame") { text("label","No insertion points required") } }
[ui_component(legacy=true)]
def editor(index:int; part_name:string) {
    state(Draft(index=index,part_name=part_name)) $(var local:Draft) {
        on_mount() { mounts+=1 }
        on_unmount() {
            verify(rui_alive(ui_find(local.part_name,local.index)),"child cleanup before parent closes document")
            unmounts+=1
        }
        text_input(part_name) { bind_value(local.value) $(value:string) { local.value=value } }
    }
}
[ui_component(legacy=true)]
def moving_counter() {
    state(Counter()) $(var local:Counter) {
        on_mount() { moving_mounts+=1 }
        on_unmount() { moving_unmounts+=1 }
        button("moving","{local.value}") { on_click() { local.value+=1 } }
    }
}
[ui_component(legacy=true)]
def window_content(model:Model; index:int) {
    state(Document(index=index)) $(var local:Document) {
        on_mount() { local.handle=open_template(@@frame,"Window {index}",float2(float(index*350),0.)); documents[index]=local.handle }
        on_unmount() { rui_close_document(local.handle); documents[local.index]=0ul }
        document_content(local.handle,"cargo_manifest") { editor(index,"cargo_input") }
        when(model.notes) { document_content(local.handle,"mission_notes") { editor(index,"notes_input") } }
        document_content(local.handle,model.destination) {
            text("status",model.status)
            moving_counter()
        }
    }
}
[ui_component(legacy=true)]
def screen(model:Model) {
    model.ids |> each_keyed($(id:int)=>id) $(id:int) { window_content(model,id) }
}
[export]
def main(smoke:bool):int {
    var model=Model()
    model.ids <- array<int>(0,1)
    documents <- array<uint64>(0ul,0ul)
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Named template slots",800,600,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,800,600)); verify(rui_default_font())
        ui_legacy_frame() { screen(model) }
        verify(definitions==1 && mounts==4 && moving_mounts==2,"cached definition, independent component instances")
        let first=documents[0]; let second=documents[1]
        let cargo=ui_find("cargo_input",0); let notes=ui_find("notes_input",0)
        let cargo_host=rui_document_element(first,"cargo_manifest")
        let notes_host=rui_document_element(first,"mission_notes")
        let status_host=rui_document_element(first,"status_readout")
        let alternate_host=rui_document_element(first,"alternate_readout")
        let unused_host=rui_document_element(first,"unused")
        verify(rui_contains(cargo_host,cargo) && rui_contains(notes_host,notes),"fill correct slots")
        verify(rui_contains(rui_document_element(second,"cargo_manifest"),ui_find("cargo_input",1)))
        verify(cargo_host!=rui_document_element(second,"cargo_manifest") && empty(rui_inner_markup(unused_host)))
        verify(find(template_markup(@@frame)," content=")<0,"no special native insertion point")
        ui_clear_stats()
        for (i in range(10)) { ui_legacy_frame() { screen(model) } }
        verify(ui_stats().updates==0 && mounts==4,"idle slots keep components asleep")

        rui_focus(cargo); rui_test_event(cargo,"change","first window only")
        ui_legacy_frame() { screen(model) }
        verify(rui_get_value(cargo)=="first window only" && rui_get_value(ui_find("cargo_input",1))=="draft")
        let status=ui_find("status",0)
        model.status="Updated"
        ui_legacy_frame() { screen(model) }
        verify(ui_find("status",0)==status && rui_inner_markup(status)=="Updated")
        verify(ui_find("cargo_input",0)==cargo && ui_find("notes_input",0)==notes && rui_focused(cargo),"sibling update preserves input and focus")
        model.ids[0]=1; model.ids[1]=0
        unsafe { heap_collect(true,false) }
        ui_legacy_frame() { screen(model) }
        verify(documents[0]==first && ui_find("cargo_input",0)==cargo && mounts==4,"keyed order and GC preserve slots")

        model.notes=false
        ui_legacy_frame() { screen(model) }
        verify(unmounts==2 && !rui_alive(notes) && rui_alive(notes_host) && empty(rui_inner_markup(notes_host)))
        verify(rui_get_value(cargo)=="first window only")
        model.notes=true
        ui_legacy_frame() { screen(model) }
        verify(mounts==6 && ui_find("notes_input",0)!=notes && rui_get_value(ui_find("notes_input",0))=="draft")

        let moving=ui_find("moving",0)
        rui_test_event(moving,"click","")
        ui_legacy_frame() { screen(model) }
        verify(rui_inner_markup(moving)=="1")
        model.destination="alternate_readout"
        ui_legacy_frame() { screen(model) }
        verify(!rui_alive(moving) && moving_mounts==4 && moving_unmounts==2,"changing destination remounts the child")
        verify(empty(rui_inner_markup(status_host)) && rui_contains(alternate_host,ui_find("moving",0)))
        verify(rui_inner_markup(ui_find("moving",0))=="0" && ui_find("cargo_input",0)==cargo)

        model.ids |> erase(0) // Remove window 1 after reordering.
        ui_legacy_frame() { screen(model) }
        verify(!rui_alive(second) && rui_alive(first) && unmounts==4 && moving_unmounts==3)
        let standalone=open_template(@@static_frame,"Static",float2(0.,0.))
        verify(rui_document_element(standalone,"label")!=0ul,"templates may have zero slots")
        rui_close_document(standalone)
        ui_reset()
        verify(unmounts==mounts && moving_unmounts==moving_mounts && !rui_alive(first))
        ui_legacy_frame() { screen(model) }
        verify(definitions==2 && rui_alive(documents[0]) && ui_find("cargo_input",0)!=cargo,"reset clears definition and component caches")
        ui_reset(); rui_shutdown()
        verify(unmounts==mounts && moving_unmounts==moving_mounts)
        print("PASS: arbitrary named slots, zero slots, instance isolation, local state, selective updates, focus, keyed order, retargeting, GC and lifecycle\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
