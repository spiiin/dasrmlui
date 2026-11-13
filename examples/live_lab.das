options gen2
options gc
options persistent_heap
options stack=65536
require dasrmlui/live
require daslib/algorithm

struct Desk { title:string="Untitled workspace"; edits:int; order:array<int> }
struct Draft { note:string="Type a note, then edit the script"; clicks:int }
var app:$UiState<Desk>?
var @live mounts=0
var @live unmounts=0

// A previous version used `text` instead of `note`. To try it, create a version-1
// snapshot and use state("draft",2,Draft()) below; migrations receive named JSON.
def ui_migrate(saved:JsonValue const?; old_version:int; var value:Draft):bool {
    if (old_version!=1) { return false }
    value.note=saved?["text"] ?? value.note
    value.clicks=saved?["clicks"] ?? 0
    return true
}

[ui_component]
def draft_card(id:int) {
    use_live_style("studio")
    state("draft",2,Draft()) $(var local:Draft) {
        on_mount() { mounts+=1 }
        on_unmount() { unmounts+=1 }
        column("card") {
            text("eyebrow","LOCAL STATE / KEY {id}")
            text("section","Draft {id}")
            text_input("note") { bind_value(local.note) $(value:string) { local.note=value } }
            text("count") { return "{local.clicks} local edits" }
            button("increment","Add a local edit") { on_click() { local.clicks+=1 } }
        }
    }
}
[ui_component]
def studio(var model:Desk) {
    use_live_style("studio")
    column("shell") {
        text("eyebrow","DASCRIPT / LIVEHOST / RMLUI")
        text("heading","Live workbench")
        text("intro","Change code. Keep your work.")
        row("toolbar") {
            button("reload","Reload code / F5") { on_click() { request_reload(false) } }
            button("reverse","Reverse keyed cards") { on_click() { reverse(model.order); model.edits+=1 } }
            button("reset","Reset state / Shift+F5") { on_click() { request_reload(true) } }
        }
        column("workspace") {
            text("eyebrow","ROOT UI_STATE")
            text_input("title") { bind_value(model.title) $(value:string) { model.title=value } }
            text("summary") { return "{model.edits} reorder operations" }
        }
        row("cards") {
            model.order |> each_keyed($(id:int)=>id) $(id:int) { draft_card(id) }
        }
        column("instructions") {
            text("section","Try it")
            text("hint","1. Edit the title and both notes; reverse the cards.")
            text("hint","2. Save a change in live_lab.das. Data returns under the same keys.")
            text("hint","3. Change a color in live_lab_styles.das. Focus and DOM stay in place.")
            text("hint","A compilation error keeps the current UI. F5 retries; Shift+F5 starts fresh.")
        }
    }
}
[export]
def init() {
    ui_live_window("dasrmlui - Live workbench",1100,820)
    var initial=Desk()
    initial.order |> push(1); initial.order |> push(2)
    app=ui_state("workspace",1,initial)
    delete initial
}
[export]
def update() { ui_frame(app) $(var model:Desk) { studio(model) } }
