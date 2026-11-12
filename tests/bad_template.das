options gen2
require dasrmlui/ui
[ui_template]
def invalid_template() {
    window_frame("frame") {
        when(true) { slot("body") }
    }
}
[export]
def main(smoke:bool):int { invalid_template(); return 0 }
