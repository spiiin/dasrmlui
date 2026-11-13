options gen2
options persistent_heap
options gc
options stack = 65536
require examples/demo_host
require examples/workbench_style
require strings
require math

struct QuoteLine { id:int; units:int = 2; rate:float = 25.0 }
struct Quote { ids:array<int>; next_id:int = 4 }
var activity : array<string>
var activity_changed : UiSignal
var calculations : int
def record(message:string) {
    activity |> push(message)
    if (length(activity) > 5) { activity |> erase(0) }
    ui_touch(activity_changed)
}
def total(units:int; rate:float):float { calculations += 1; return float(units)*rate }
def recent_activity():string {
    var text=""
    for (line in activity) { text += "{line}\n" }
    return text
}
// A reusable frame accepts content as a synchronous slot.
[ui_component]
def quote_frame(title:string; content:block) {
    use_style(@@component_lab_style)
    column("card") {
        width(px(ui_width() < 1000.0 ? max(280.0,ui_width()-96.0) : 308.0))
        margin_right(px(14))
        text("package_title",title)
        slot(content)
    }
}
[ui_component]
def quote_line(id:int; removed:block<(id:int):void>) {
    use_style(@@component_lab_style)
    state(QuoteLine(id=id,rate=25.0+float(id)*10.0)) $(var local:QuoteLine) {
        on_mount() { record("Line {local.id} opened") }
        on_unmount() { record("Line {local.id} closed with {local.units} units") }
        computed(total(local.units,local.rate)) $(subtotal:float) {
            quote_frame("Service package {id}") {
                text("muted","EUR {local.rate:.2f} per unit")
                text("units","Quantity: {local.units}")
                row() {
                    margin_top(px(16)); margin_bottom(px(12))
                    button("decrease","- 1") {
                        disabled() { return local.units <= 1 }
                        on_click() { local.units -= 1 }
                    }
                    button("increase","+ 1") { on_click() { local.units += 1 } }
                }
                text("subtotal","EUR {subtotal:.2f}")
                text("muted","Move this card to keep its quantity. Remove it to finish this line.")
                button("remove","Remove line") { on_click() { emit(removed,id) } }
            }
        }
    }
}
[ui_component]
def quotation(var model:Quote) {
    ui_watch(activity_changed)
    use_style(@@component_lab_style)
    column("shell") {
        width(px(max(320.0,ui_width()-56.0)))
        text("eyebrow","NORTHSTAR / QUOTE BUILDER")
        text("heading","Build your next project")
        text("muted","Adjust quantities, reorder service packages and review your activity.")
        row() {
            margin_top(px(12)); margin_bottom(px(20))
            button("reorder","Reverse order") {
                on_click() {
                    for (i in range(length(model.ids)/2)) {
                        let last=length(model.ids)-1-i
                        let old=model.ids[i]; model.ids[i]=model.ids[last]; model.ids[last]=old
                    }
                    record("Reordered service packages")
                }
            }
            button("add","Add package") {
                on_click() { model.ids |> push(model.next_id); model.next_id += 1 }
            }
            button("restore","Restore original packages") {
                on_click() {
                    for (id in range(1,4)) {
                        var present=false
                        for (existing in model.ids) { if (existing == id) { present=true } }
                        if (!present) { model.ids |> push(id) }
                    }
                }
            }
        }
        flow("lines",1000.0) {
            property("flex-wrap","wrap")
            model.ids |> each_keyed($(id:int) => id) $(id:int) {
                quote_line(id) $(removed:int) {
                    for (i in range(length(model.ids))) {
                        if (model.ids[i] == removed) { model.ids |> erase(i); break }
                    }
                }
            }
        }
        column("activity_panel") {
            width(px(max(280.0,ui_width()-96.0)))
            text("eyebrow","RECENT ACTIVITY")
            box() {
                property("white-space","pre-wrap")
                text("activity") { return recent_activity() }
            }
        }
    }
}
[export]
def main(smoke:bool):int {
    var initial=Quote()
    initial.ids |> push(1); initial.ids |> push(2); initial.ids |> push(3)
    activity_changed=ui_signal()
    var first = 0ul
    var state=ui_state(initial)
    return run_demo("dasrmlui - Quote builder","logs/component_lab.png",smoke,$() { ui_frame(state) $(model:Quote) { quotation(model) } }) $(frame:int) {
        ui_edit(state) $(var model:Quote) {
            if (frame == 0) { first=ui_find("units",1); rui_test_click(ui_find("increase",1)) }
            elif (frame == 1) { verify(find(rui_markup(),"Quantity: 3") >= 0); rui_test_click(ui_find("reorder")) }
            elif (frame == 2) { verify(ui_find("units",1) == first); rui_test_click(ui_find("remove",1)) }
            elif (frame == 3) { verify(!rui_alive(first)); rui_test_click(ui_find("restore")) }
            elif (frame == 4) { verify(ui_find("units",1) != first && ui_find("units",1) != 0ul) }
            elif (frame == 5) { rui_test_resize(720,820) }
            elif (frame == 6) { verify(ui_width() == 720.0) }
        }
    }
}
