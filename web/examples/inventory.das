options gen2
options persistent_heap
options gc
require examples/inventory_ui
require examples/demo_host
[export]
def main(smoke:bool):int {
    var initial <- initial_inventory()
    var state=ui_state(initial)
    return run_demo("Inventory","",smoke,$() { ui_frame(state) $(model:InventoryUi) { inventory_panel(model) } }) $(frame:int) {}
}
