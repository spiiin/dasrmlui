options gen2
options gc
require dasrmlui/ui
struct Model { count:int }
[export]
def main(smoke:bool):int {
    var state=ui_state(Model())
    state.data[0].count=1
    return 0
}
