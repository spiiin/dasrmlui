options gen2
options persistent_heap
options gc
require examples/inventory_ui
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

[export]
def main(smoke:bool) : int {
    var initial <- initial_inventory()
    var state=ui_state(initial)
    let result = sdl_scope() {
        with_sdl() |> sdl_use
        let window : SDL_Window? = with_window("runtime tests",960,640,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer : SDL_Renderer? = window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,960,640))
        verify(rui_default_font())
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        let input12 = ui_find("title",12)
        let input35 = ui_find("title",35)
        verify(input12 != 0ul && input35 != 0ul)
        verify(rui_get_value(input12) == "Health potion")
        ui_clear_stats()
        for (i in range(20)) { ui_frame(state) $(model:InventoryUi) { inventory_panel(model) } }
        verify(ui_stats().mounts == 0 && ui_stats().binding_updates == 0, "Idle frames preserve mounts and bindings")
        ui_edit(state) $(var model:InventoryUi) { model.items[0].count = 4 }
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        verify(ui_stats().mounts == 0 && rui_inner_markup(ui_find("count",12)) == "x4", "Field edits update the existing keyed badge")
        verify(ui_find("title",12) == input12)
        ui_edit(state) $(var model:InventoryUi) { model.items[0].count = 3 }
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        rui_focus(input12)
        rui_select(input12,1,4)

        rui_test_event(ui_find("reverse"),"click","")
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        ui_read(state) $(model:InventoryUi) { verify(model.items[0].id == 81) }
        verify(ui_find("title",12) == input12)
        verify(ui_find("title",35) == input35)
        verify(rui_focused(input12))
        verify(rui_selection(input12) == int2(1,4))
        let panel = ui_find("panel")
        verify(rui_child(panel,3) == ui_find("item",81), "DOM order must follow keys")

        rui_test_event(input12,"change","Potion <strong>&")
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        verify(rui_get_value(input12) == "Potion <strong>&")
        ui_read(state) $(model:InventoryUi) { verify(model.items[2].title == "Potion <strong>&") }
        // Exercise the actual text editing path, not just event injection.
        rui_focus(input12)
        rui_select(input12,0,1000)
        rui_test_text("Typed through RmlUi")
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        ui_read(state) $(model:InventoryUi) { verify(model.items[2].title == "Typed through RmlUi") }

        rui_test_event(input12,"change","")
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        verify(rui_get_value(input12) == "Typed through RmlUi", "Rejected input must be restored")

        rui_test_event(ui_find("select",12),"click","")
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        let details12 = ui_find("details",12)
        verify(details12 != 0ul)
        rui_test_event(ui_find("select",35),"click","")
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        verify(!rui_alive(details12))
        verify(ui_find("details",35) != 0ul)

        rui_test_event(ui_find("remove",35),"click","")
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        verify(!rui_alive(input35))
        ui_read(state) $(model:InventoryUi) { verify(length(model.items) == 2) }
        ui_edit(state) $(var model:InventoryUi) { model.items |> push <| Item(id=35,title="Replacement",count=1) }
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        verify(ui_find("title",35) != input35)

        // The event queue must be applied in arrival order.
        rui_test_event(ui_find("select",12),"click","")
        rui_test_event(ui_find("select",81),"click","")
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        ui_read(state) $(model:InventoryUi) { verify(model.selected_id == 81) }

        // A queued change to a row removed by a preceding command is stale.
        let replacement35 = ui_find("title",35)
        rui_test_event(ui_find("remove",35),"click","")
        rui_test_event(replacement35,"change","STALE")
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        verify(!rui_alive(replacement35))
        ui_read(state) $(model:InventoryUi) { verify(length(model.items) == 2) }
        unsafe { heap_collect(true,false) }
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        verify(ui_find("title",12) == input12)

        ui_edit(state) $(var model:InventoryUi) { clear(model.items) }
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        verify(ui_find("empty") != 0ul)
        verify(!rui_alive(input12))
        ui_reset()
        verify(rui_child_count(rui_root()) == 0, "Reset must remove the DOM, not just handles")
        ui_frame(state) $(model:InventoryUi) { inventory_panel(model) }
        verify(ui_find("empty") != 0ul)
        ui_reset()
        rui_shutdown()
        print("PASS: keyed identity/order, nested components, focus/selection, real text input, rejected input, conditions, stale events, GC and reset\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}

