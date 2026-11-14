options gen2
options persistent_heap
options gc
options stack = 65536
require examples/inventory_ui
require sdl3

var inventory = ui_state(initial_inventory())
var frames = 0

[export]
def app_start(window:SDL_Window?; renderer:SDL_Renderer?; fallback_font:string):bool {
    verify(rui_init(window,renderer,800,390))
    verify(rui_default_font())
    verify(rui_fallback_font(fallback_font))
    return true
}

[export]
def app_event(event:SDL_Event) {
    rui_event(event)
}

[export]
def app_frame(smoke:bool):bool {
    ui_frame(inventory) $(model:InventoryUi) { inventory_panel(model) }
    rui_render()
    frames += 1
    if (frames % 120 == 0) { unsafe { heap_collect(true,false) } }

    if (smoke && frames == 1) {
        verify(ui_find("action") != 0ul)
        rui_test_click(ui_find("action"))
    }
    if (smoke && frames == 2) {
        ui_read(inventory) $(model:InventoryUi) {
            verify(length(model.items) == 4 && model.items[3].title == "New item")
        }
        rui_test_click(ui_find("title",12))
        verify(rui_focused(ui_find("title",12)))
    }
    if (smoke && frames > 2 && rui_get_value(ui_find("title",12)) == "AПривет") {
        ui_read(inventory) $(model:InventoryUi) {
            verify(model.items[0].title == "AПривет")
        }
        verify(rui_focused(ui_find("title",12)))
        verify(rui_warning_count() == 0ul)
        return true
    }
    return false
}

[export]
def inventory_select_name() {
    let field = ui_find("title",12)
    rui_select(field,0,13)
}
