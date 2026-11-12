options gen2
require dasrmlui/ui
[ui_template]
def invalid_template() { window_frame("frame") { slot("") } }
[export]
def main(smoke:bool):int { invalid_template(); return 0 }
