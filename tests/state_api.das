options gen2
options persistent_heap
options gc
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope
struct Item { id:int; title:string }
struct Model { title:string="first"; count:int; visible:bool=true; rows:array<Item> }
var runs:int
[ui_component]
def screen(var model:Model) {
    runs+=1
    text("title",model.title)
    text("count",model.count)
    button("increment","+") { on_click() { model.count+=1 } }
    when(model.visible) { text("conditional","visible") }
    model.rows |> each_keyed($(item:Item)=>item.id) $(item:Item) { text("row",item.title) }
}
def opaque(var model:Model) { model.title="helper" }
def opaque_scalar(var title:string&) { title="alias helper" }
[ui_action]
def action_helper(var model:Model) { opaque(model) }
[export]
def main(smoke:bool):int {
    var initial=Model()
    initial.rows |> push(Item(id=1,title="one"))
    initial.rows |> push(Item(id=2,title="two"))
    var state=ui_state(initial)
    initial.rows[0].title="outside"
    ui_edit(state) $(var model:Model) { model.count=42 }
    ui_read(state) $(model:Model) { verify(model.count==42 && model.rows[0].title=="one","state owns a deep clone") }
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Managed state",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480)); verify(rui_default_font())
        ui_frame(state) $(var model:Model) { screen(model) }
        let first=runs
        ui_frame(state) $(model:Model) { screen(model) }
        verify(runs==first,"default components sleep")
        ui_edit(state) $(var model:Model) { model.title="second"; model.count+=1 }
        ui_frame(state) $(model:Model) { screen(model) }
        verify(runs==first && find(rui_markup(),"second")>=0,"tracked edits only dirty native leaves")
        let reads=rui_hybrid_reads()
        ui_edit(state) $(var model:Model) { model.title="second" }
        ui_frame(state) $(model:Model) { screen(model) }
        verify(runs==first && rui_hybrid_reads()==reads,"equal writes remain idle")
        ui_edit(state) $(var model:Model) { model.count++; --model.count }
        ui_frame(state) $(model:Model) { screen(model) }
        verify(runs==first,"increment statements preserve native scheduling")
        ui_edit(state) $(var model:Model) {
            var alias:int& = model.count
            alias+=1
            ui_edit(state) $(var nested:Model) { nested.count+=1 }
        }
        ui_frame(state) $(model:Model) { screen(model) }
        verify(find(rui_markup(),"45")>=0,"local aliases and nested same-state edits")
        ui_edit(state) $(var model:Model) { opaque(model) }
        ui_frame(state) $(model:Model) { screen(model) }
        verify(find(rui_markup(),"helper")>=0,"opaque mutation gets a conservative notification")
        rui_test_click(ui_find("increment"))
        ui_frame(state) $(model:Model) { screen(model) }
        ui_read(state) $(model:Model) { verify(model.count==46) }
        ui_edit(state) $(var model:Model) { var alias:string& = model.title; opaque_scalar(alias) }
        ui_frame(state) $(model:Model) { screen(model) }
        verify(find(rui_markup(),"alias helper")>=0,"helper through alias is conservative")
        ui_edit(state) $(var model:Model) { action_helper(model) }
        ui_frame(state) $(model:Model) { screen(model) }
        verify(find(rui_markup(),"helper")>=0,"opaque helper inside ui_action")
        let row=ui_find("row",1)
        ui_edit(state) $(var model:Model) {
            let moved=model.rows[0]; model.rows[0]=model.rows[1]; model.rows[1]=moved
            model.rows |> push(Item(id=3,title="three"))
            model.visible=false
        }
        ui_frame(state) $(model:Model) { screen(model) }
        verify(ui_find("row",1)==row && ui_find("row",3)!=0ul && ui_find("conditional")==0ul,"keyed structure and condition")
        try {
            ui_edit(state) $(var model:Model) { model.title="partial"; panic("edit failure") }
        } recover {}
        ui_edit(state) $(var model:Model) { model.count=99 }
        ui_frame(state) $(model:Model) { screen(model) }
        verify(find(rui_markup(),"partial")>=0 && find(rui_markup(),"99")>=0,"failed edit restores guard and publishes partial writes")
        try {
            ui_edit(state) $(var model:Model) { ui_frame(state) $(same:Model) { screen(same) } }
            panic("nested frame was accepted")
        } recover { verify(find(string(this_context().last_exception),"finish ui_edit")>=0) }
        unsafe { heap_collect(true,false) }
        ui_edit(state) $(var model:Model) { model.rows[1].title="after GC" }
        ui_frame(state) $(model:Model) { screen(model) }
        verify(ui_find("row",1)==row && find(rui_markup(),"after GC")>=0)
        var other=ui_state(Model(title="replacement"))
        ui_frame(other) $(model:Model) { screen(model) }
        verify(!rui_alive(row) && find(rui_markup(),"replacement")>=0,"switching states unmounts the old tree")
        ui_reset(); rui_shutdown()
        print("PASS: managed state, read/edit/frame, native default and opaque helper\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
