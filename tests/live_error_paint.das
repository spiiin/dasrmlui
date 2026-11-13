options gen2
require dasrmlui/live
[export]
def init() {
    ui_live_window("error test",200,150)
    register_native_element("test-error",@(event:UiNativeEvent) {
        if (event.kind==UiNativeKind.Paint) { panic("EXPECTED paint error") }
    },float2(30.,30.))
}
[ui_component(legacy=true)]
def screen() { native_element("bad","test-error") { width(px(30)); height(px(30)) } }
[export]
def update() { ui_legacy_frame() { screen() } }
