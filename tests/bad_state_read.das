options gen2
options gc
require dasrmlui/ui
struct Model { count:int }
[export]
def main(smoke:bool):int {
    var state=ui_state(Model())
    ui_read(state) $(model:Model) { model.count=1 }
    return 0
}
