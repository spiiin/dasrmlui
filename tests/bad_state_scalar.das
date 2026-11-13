options gen2
options gc
require dasrmlui/ui
[export]
def main(smoke:bool):int {
    var state=ui_state(0)
    return state==null ? 1 : 0
}
