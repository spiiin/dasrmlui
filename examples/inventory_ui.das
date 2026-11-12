options gen2
module inventory_ui public
require dasrmlui/ui public

struct Item {
    id : int
    title : string
    count : int
}
struct InventoryUi {
    items : array<Item>
    selected_id : int = -1
    next_id : int = 100
}
def rename_item(var model:InventoryUi; id:int; title:string) {
    if (empty(title)) { return }
    for (item in model.items) {
        if (item.id == id && item.title != title) {
            item.title = title

            return
        }
    }
}
def remove_item(var model:InventoryUi; id:int) {
    for (i in range(length(model.items))) {
        if (model.items[i].id == id) {
            model.items |> erase(i)

            return
        }
    }
}
[ui_style]
def inventory_style() {
    rule(root()) { padding(px(24.0)); background(rgb(19,25,38)); width(px(800.0)) }
    rule(part("heading")) { font_size(px(28.0)); margin_bottom(px(8.0)) }
    rule(part("subtitle")) { color(rgb(148,163,184)); margin_bottom(px(20.0)) }
    rule(part("item")) { padding(px(12.0)); margin_bottom(px(10.0)); background(rgb(31,41,59)) }
    rule(part("title")) { width(px(300.0)); padding(px(8.0)); background(rgb(12,18,29)); color(rgb(235,240,249)); border_width(px(1)); border_color(rgb(81,100,124)) }
    rule(part("count")) { width(px(65.0)); padding(px(8.0)) }
    rule(part("action")) { padding(px(8.0)); background(rgb(49,85,140)); margin_left(px(8)) }
    part("action") |> hover() |> rule() { background(rgb(65,117,183)) }
    rule(part("details")) { padding(px(10.0)); color(rgb(112,218,175)) }
    rule(part("empty")) { padding(px(20.0)); color(rgb(148,163,184)) }
}
[ui_component]
def stock_badge(count:int) {
    box("badge") {
        width(px(65.0))
        padding(px(8.0))
        text("count") { return "x{count}" }
    }
}
[ui_component]
def inventory_panel(var model:InventoryUi) {
    use_style(@@inventory_style)
    column("panel") {
        text("heading","Inventory / daScript + RmlUi")
        text("subtitle","Edit names, select rows, reverse order. DOM identity follows item keys.")
        row("toolbar") {
            button("action","Add item") {
                on_click() {
                    model.items |> push <| Item(id=model.next_id,title="New item",count=1)
                    model.next_id += 1
                }
            }
            button("reverse","Reverse") {
                property("padding","8px 16px")
                on_click() {
                    for (i in range(length(model.items)/2)) {
                        let j = length(model.items)-1-i
                        let old = model.items[i]
                        model.items[i] = model.items[j]
                        model.items[j] = old
                    }
                }
            }
        }
        when(empty(model.items)) {
            text("empty","No items. Add one above.")
        }
        model.items |> each_keyed($(item:Item) => item.id) $(item:Item) {
            column("item") {
                row() {
                    text_input("title") {
                        bind_value(item.title) $(value:string) {
                            rename_item(model,item.id,value)
                        }
                    }
                    stock_badge(item.count)
                    button("select","Details") {
                        padding(px(8))
                        on_click() { model.selected_id = item.id }
                    }
                    button("remove","Remove") {
                        padding(px(8))
                        on_click() { remove_item(model,item.id) }
                    }
                }
                when(model.selected_id == item.id) {
                    box("details") { text("detail_text") { return "Stable key #{item.id} - {item.title}" } }
                }
            }
        }
    }
}
def initial_inventory() : InventoryUi {
    var model = InventoryUi()
    model.items |> push <| Item(id=12,title="Health potion",count=3)
    model.items |> push <| Item(id=35,title="Iron sword",count=1)
    model.items |> push <| Item(id=81,title="Ancient map",count=1)
    return <- model
}
