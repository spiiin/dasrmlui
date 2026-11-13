options gen2
options gc
require dasrmlui/ui
struct Model { external:int? }
[export]
def main(smoke:bool):int {
    var state=ui_state(Model())
    return state==null ? 1 : 0
}
