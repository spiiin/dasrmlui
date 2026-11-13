options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

var items : array<int>
var changed : UiSignal
var mounted,retired,clicked,submitted : int
struct Model { dialog,inner:bool }
[ui_component(legacy=true)]
def item_row(id:int) {
    on_mount() { mounted += 1 }
    on_unmount() { retired += 1 }
    button("item","Row {id}") { height(px(28)); on_click() { clicked=id } }
}
[ui_component(legacy=true)]
def catalog() {
    ui_watch(changed)
    virtual_each("list",items,30.0,150.0,$(id:int) => id) $(id:int) { item_row(id) }
}
[ui_component(legacy=true)]
def inner_dialog() {
    on_mount() { request_focus("nested_input") }
    focus_scope("nested") {
        text_input("nested_input") { width(px(100)); height(px(30)) }
    }
}
[ui_component(legacy=true)]
def dialog(var model:Model) {
    on_mount() { request_focus("first") }
    focus_scope("dialog") {
        text_input("first") { width(px(100)); height(px(30)); on_submit() { submitted += 1 } }
        button("second","Close") { on_click() { model.dialog=false } }
        button("disabled","Disabled") { disabled() { return true } }
        when(model.inner) { inner_dialog() }
    }
}
[ui_component(legacy=true)]
def screen(var model:Model) {
    flow("layout",700.0) {
        text("size") { return ui_width() < 700.0 ? "narrow" : "wide" }
        catalog()
        button("open","Open") { on_click() { model.dialog=true } }
        when(model.dialog) { dialog(model) }
    }
}
[export]
def main(smoke:bool):int {
    var model = Model()
    changed=ui_signal()
    for (i in range(10000)) { items |> push(i) }
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let window : SDL_Window? = with_window("viewport tests",900,600,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer : SDL_Renderer? = window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,900,600)); verify(rui_default_font())
        ui_legacy_frame() { screen(model) }
        verify(mounted == 8 && ui_find("item",0) != 0ul && ui_find("item",100) == 0ul)
        let list = ui_find("list")
        for (i in range(5)) { ui_legacy_frame() { screen(model) } }
        verify(mounted == 8 && retired == 0)
        rui_scroll_to(list,3000.0)
        ui_legacy_frame() { screen(model) }
        verify(ui_find("item",100) != 0ul && ui_find("item",0) == 0ul && retired == 8)
        verify(mounted < 25)
        rui_test_click(ui_find("item",101))
        ui_legacy_frame() { screen(model) }
        verify(clicked == 101)
        rui_test_resize(600,600)
        ui_legacy_frame() { screen(model) }
        verify(find(rui_markup(),">narrow<") >= 0 && ui_find("list") == list)
        rui_test_click(ui_find("open"))
        ui_legacy_frame() { screen(model) }
        verify(model.dialog && rui_focused(ui_find("first")))
        rui_test_key("Enter",false)
        ui_legacy_frame() { screen(model) }
        verify(submitted == 1)
        rui_test_key("Tab",false)
        verify(rui_focused(ui_find("second")))
        rui_test_key("Tab",false)
        verify(rui_focused(ui_find("first")))
        rui_test_key("Tab",true)
        verify(rui_focused(ui_find("second")))
        rui_test_key("Enter",false)
        ui_legacy_frame() { screen(model) }
        verify(!model.dialog && rui_focused(ui_find("open")))
        rui_test_click(ui_find("open"))
        ui_legacy_frame() { screen(model) }
        model.inner=true
        ui_legacy_frame() { screen(model) }
        verify(rui_focused(ui_find("nested_input")))
        model.inner=false
        ui_legacy_frame() { screen(model) }
        verify(rui_focused(ui_find("first")))
        model.inner=true
        ui_legacy_frame() { screen(model) }
        model.dialog=false
        ui_legacy_frame() { screen(model) }
        verify(rui_focused(ui_find("open")))
        resize(items,3); ui_touch(changed)
        ui_legacy_frame() { screen(model) }
        verify(ui_find("item",0) != 0ul && rui_scroll_top(list) == 0.0)
        unsafe { heap_collect(true,false) }
        ui_reset(); verify(mounted == retired); rui_shutdown()
        print("PASS: 10000 rows, bounded DOM, scroll, clicks, resize, shrink, focus trap, Enter and focus restoration\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
