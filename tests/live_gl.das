options gen2
options gc
options persistent_heap
require dasrmlui/live
struct Model { count:int }
var state:$UiState<Model>?
[ui_component]
def screen(model:Model) {
    box("card") { width(px(200)); height(px(100)); background(rgb(25,130,170)); text("count") { return "{model.count}" } }
}
[export]
def init() {
    ui_live_window("GL3 live reload",300,200,true)
    state=ui_state("gl",Model())
}
var frames=0
[export]
def update() {
    ui_frame(state) $(model:Model) { screen(model) }
    if (!is_reload() && frames==1) {
        ui_edit(state) $(var model:Model) { model.count=42 }
        request_reload(false)
    }
    if (is_reload() && frames==1) {
        ui_read(state) $(model:Model) { verify(model.count==42) }
        verify(rui_warning_count()==0ul)
        print("PASS: GL3 LiveHost renderer recreation and state\n")
        request_exit()
    }
    frames+=1
}
