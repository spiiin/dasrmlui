options gen2
options persistent_heap
options gc
options stack = 65536
require examples/demo_host
require examples/advanced_style
require strings

struct WorkItem { id:int; title,owner:string; done:bool; urgent:bool }
struct Dashboard {
    items:array<WorkItem>
    query:string
    filter:int
    selected:int = 2
    next_id:int = 5
}
def completed(items:array<WorkItem>):int {
    var n = 0
    for (item in items) { if (item.done) { n += 1 } }
    return n
}
def matches(item:WorkItem; query:string; filter:int):bool {
    return (empty(query) || find(item.title,query) >= 0) && (filter == 0 || (filter == 1 && !item.done) || (filter == 2 && item.done))
}
[ui_action]
def set_done(var model:Dashboard; id:int) {
    for (item in model.items) { if (item.id == id) { item.done = !item.done } }
}
[ui_component]
def dashboard_metrics(items:array<WorkItem>) {
    row() {
        metric("TOTAL TASKS","{length(items)}","Across your workspace")
        metric("COMPLETED","{completed(items)}","Finished this cycle")
        metric("OPEN","{length(items)-completed(items)}","Ready for your next action")
    }
}
[ui_component]
def dashboard(var model:Dashboard) {
    use_style(@@operations_style)
    column("shell") {
        studio_header(0,"WORKSPACE / OPERATIONS", "Good morning, Alex", "Track priorities, review progress and keep your team moving.")
        dashboard_metrics(model.items)
        row() {
            property("align-items","flex-start")
            column("card") {
                width(px(680.0)); margin_right(px(16))
                text("section","Work queue")
                text_input("search") {
                    width(px(632.0)); padding(px(10.0)); background(rgb(12,20,33)); color(rgb(233,242,253))
                    bind_value(model.query) $(value:string) { model.query = value }
                }
                text("muted","Search titles (case-sensitive)")
                row("toolbar") {
                    margin_top(px(12.0))
                    button("all","All") { padding(px(9.0)); on_click() { model.filter = 0 } }
                    button("open","Open") { padding(px(9.0)); on_click() { model.filter = 1 } }
                    button("done","Completed") { padding(px(9.0)); on_click() { model.filter = 2 } }
                    button("primary","+ Add task") {
                        on_click() {
                            model.items |> push <| WorkItem(id=model.next_id,title="New investigation",owner="You")
                            model.selected = model.next_id; model.next_id += 1
                        }
                    }
                }
                column() {
                    width(px(644.0)); height(px(340.0)); property("overflow-y","auto")
                    model.items |> each_keyed($(item:WorkItem) => item.id) $(item:WorkItem) {
                        when(matches(item,model.query,model.filter)) {
                            column("task") {
                                width(px(600.0))
                                text("task_title",item.title)
                                row() {
                                    text("muted") { return "{item.owner}   /   {item.done ? "Complete" : "In progress"}" }
                                    button("inspect","Inspect") { padding(px(7.0)); margin_left(px(14)); on_click() { model.selected = item.id } }
                                    button("toggle",item.done ? "Reopen" : "Complete") { padding(px(7.0)); on_click() { set_done(model,item.id) } }
                                }
                            }
                        }
                    }
                }
            }
            column("card") {
                width(px(354.0))
                text("section","Task inspector")
                model.items |> each_keyed($(item:WorkItem) => item.id) $(item:WorkItem) {
                    when(model.selected == item.id) {
                        text("caption","TITLE")
                        text_input("edit_title") {
                            width(px(306.0)); padding(px(10.0)); background(rgb(12,20,33)); color(rgb(233,242,253))
                            bind_value(item.title) $(value:string) {
                                if (!empty(value)) { for (target in model.items) { if (target.id == item.id) { target.title = value } } }
                            }
                        }
                        text("caption","ASSIGNEE")
                        text("task_title",item.owner)
                        box("divider") {}
                        text("good",item.done ? "Completed" : "In progress")
                        button("priority",item.urgent ? "Priority: HIGH" : "Priority: NORMAL") {
                            padding(px(10.0))
                            on_click() { for (target in model.items) { if (target.id == item.id) { target.urgent = !target.urgent } } }
                        }
                        margin_top(px(12.0))
                        text("muted","Changes appear immediately in the work queue.")
                    }
                }
            }
        }
    }
}
[export]
def main(smoke:bool):int {
    var initial = Dashboard()
    initial.items |> push <| WorkItem(id=1,title="Review the November release",owner="Maya Chen")
    initial.items |> push <| WorkItem(id=2,title="Investigate API latency",owner="Alex Morgan",urgent=true)
    initial.items |> push <| WorkItem(id=3,title="Publish component guidelines",owner="Sam Rivera",done=true)
    initial.items |> push <| WorkItem(id=4,title="Prepare customer handoff",owner="Jordan Lee")
    var state=ui_state(initial)
    return run_demo("dasrmlui - Operations dashboard","logs/dashboard.png",smoke,$() { ui_frame(state) $(model:Dashboard) { dashboard(model) } }) $(frame:int) {
        ui_edit(state) $(var model:Dashboard) {
            if (frame == 0) { rui_test_click(ui_find("toggle",1)) }
            elif (frame == 1) { verify(model.items[0].done); rui_test_event(ui_find("edit_title",2),"change","API latency: resolved") }
            elif (frame == 2) { verify(model.items[1].title == "API latency: resolved"); rui_test_click(ui_find("done")) }
            elif (frame == 3) { verify(ui_find("toggle",2) == 0ul); rui_test_click(ui_find("all")) }
            elif (frame == 4) { verify(ui_find("toggle",2) != 0ul); rui_test_click(ui_find("primary")) }
            elif (frame == 5) { verify(length(model.items) == 5 && model.selected == 5); rui_test_click(ui_find("inspect",2)) }
            elif (frame == 6) { verify(model.selected == 2 && rui_get_value(ui_find("edit_title",2)) == "API latency: resolved") }
        }
    }
}
