options gen2
require dasrmlui/live
[export]
def init() { ui_live_window("error test",200,150) }
[export]
def update() { request_exit() }
[export]
def shutdown() { panic("EXPECTED shutdown error") }
