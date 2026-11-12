options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope
struct Model { count:int = 5; ratio:float = 1.0; enabled:bool; color:string = "red"; title:string = "hello" }
var choices : array<UiOption>
[ui_component]
def screen(var model:Model) {
    column() {
        text_input("count") {
            width(px(200)); height(px(30))
            bind_int(model.count,1,50,"Enter") $(value:int) { model.count=value }
        }
        text("error") { return field_error("count") }
        text_input("ratio") {
            bind_float(model.ratio,0.0,10.0,"blur") $(value:float) { model.ratio=value }
        }
        text_input("title") {
            bind_edit(model.title,"change",$(value:string):string {
                return length(value) < 3 ? "At least 3 characters" : ""
            }) $(value:string) { if (value != "reject") { model.title=value } }
        }
        checkbox("enabled") {
            width(px(24)); height(px(24)); background(rgb(100,100,100))
            bind_checked(model.enabled) $(value:bool) { model.enabled=value }
        }
        select_input("color") {
            width(px(180)); height(px(30))
            select_options(choices)
            bind_value(model.color) $(value:string) { model.color=value }
        }
        button("other","Other") { on_click() {} }
    }
}
[export]
def main(smoke:bool):int {
    var model = Model()
    choices |> push <| UiOption(value="red",caption="Red <safe>")
    choices |> push <| UiOption(value="blue",caption="Blue")
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let window : SDL_Window? = with_window("form tests",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer : SDL_Renderer? = window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480)); verify(rui_default_font())
        ui_frame() { screen(model) }
        let count = ui_find("count")
        rui_focus(count)
        rui_test_event(count,"change","-")
        ui_frame() { screen(model) }
        verify(model.count == 5 && !empty(field_error("count")) && rui_get_value(count) == "-")
        rui_test_event(count,"change","99999999999999999999999999")
        ui_frame() { screen(model) }
        verify(model.count == 5 && !empty(field_error("count")))
        rui_test_event(count,"change","12garbage")
        ui_frame() { screen(model) }
        verify(model.count == 5 && !empty(field_error("count")))
        rui_test_event(count,"change","80")
        rui_test_key("Enter",false)
        ui_frame() { screen(model) }
        verify(model.count == 5 && !empty(field_error("count")))
        rui_test_event(count,"change","12")
        ui_frame() { screen(model) }
        verify(model.count == 5 && empty(field_error("count")))
        rui_test_key("Enter",false)
        ui_frame() { screen(model) }
        verify(model.count == 12)
        rui_test_event(count,"change","-")
        ui_frame() { screen(model) }
        rui_test_key("Escape",false)
        ui_frame() { screen(model) }
        verify(rui_get_value(count) == "12" && empty(field_error("count")))
        model.count = 7
        ui_frame() { screen(model) }
        verify(rui_get_value(count) == "7")
        let ratio = ui_find("ratio")
        rui_focus(ratio)
        rui_test_event(ratio,"change","2.5")
        ui_frame() { screen(model) }
        verify(model.ratio == 1.0)
        rui_focus(ui_find("other"))
        ui_frame() { screen(model) }
        verify(model.ratio == 2.5)
        rui_test_event(ui_find("title"),"change","x")
        ui_frame() { screen(model) }
        verify(model.title == "hello" && !empty(field_error("title")))
        rui_test_event(ui_find("title"),"change","valid")
        ui_frame() { screen(model) }
        verify(model.title == "valid")
        rui_test_event(ui_find("title"),"change","reject")
        ui_frame() { screen(model) }
        verify(model.title == "valid" && rui_get_value(ui_find("title")) == "valid")
        rui_test_click(ui_find("enabled"))
        ui_frame() { screen(model) }
        verify(model.enabled && rui_checked(ui_find("enabled")))
        rui_focus(ui_find("color"))
        rui_test_key("Down",false)
        ui_frame() { screen(model) }
        verify(model.color == "blue")
        model.enabled=false
        ui_frame() { screen(model) }
        verify(!rui_checked(ui_find("enabled")))
        unsafe { heap_collect(true,false) }
        ui_reset(); rui_shutdown()
        print("PASS: typed drafts, overflow, ranges, validation, Enter/blur commits, Escape, checkbox mouse, select keyboard\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
