options gen2
options persistent_heap
options gc
options stack = 65536
require examples/demo_host
require examples/advanced_style
require strings

struct Preferences {
    name:string = "Northstar Studio"
    email:string = "team@northstar.example"
    endpoint:string = "https://api.example.test"
    mint:bool = true
    compact:bool
    notifications:bool = true
    advanced:bool
}
struct Settings {
    draft:Preferences = Preferences()
    saved:Preferences = Preferences()
    tab:int
    saves:int
}
def valid_email(value:string):bool { return find(value,"@") > 0 && find(value,".") > 0 }
def dirty(model:Settings):bool {
    let a = model.draft
    let b = model.saved
    return a.name != b.name || a.email != b.email || a.endpoint != b.endpoint || a.mint != b.mint || a.compact != b.compact || a.notifications != b.notifications || a.advanced != b.advanced
}
[ui_component]
def preview(value:Preferences) {
    use_style(@@preferences_style)
    column("card") {
        width(px(318.0))
        text("caption","LIVE PREVIEW")
        column("preview_banner") {
            width(px(286.0)); padding(px(16.0)); margin_bottom(px(20.0))
            class_if("mint",value.mint)
            text("task_title",value.name)
            text("muted","Your workspace, your preferences")
        }
        text("section","Today's activity")
        column("task") {
            width(px(282.0))
            class_if("compact",value.compact)
            text("task_title","Design review")
            text("muted","10:30 / Product team")
        }
        column("task") {
            width(px(282.0))
            class_if("compact",value.compact)
            text("task_title","Release readiness")
            text("muted","14:00 / Engineering")
        }
        text("good",value.notifications ? "Notifications enabled" : "Quiet mode enabled")
        text("muted","Preview your workspace before saving your preferences.")
    }
}
[ui_component]
def settings(var model:Settings) {
    use_style(@@preferences_style)
    column("shell") {
        studio_header(1,"WORKSPACE / PREFERENCES","Make it yours","Tune your workspace and preview changes before saving.")
        row() {
            property("align-items","flex-start")
            column("nav") {
                // The selected tab is a class, so its look lives in the style sheet.
                button("profile_tab","Workspace") { padding(px(13.0)); margin_bottom(px(8.0)); class_if("active",model.tab == 0); on_click() { model.tab = 0 } }
                button("appearance_tab","Appearance") { padding(px(13.0)); margin_bottom(px(8.0)); class_if("active",model.tab == 1); on_click() { model.tab = 1 } }
                button("network_tab","Connection") { padding(px(13.0)); class_if("active",model.tab == 2); on_click() { model.tab = 2 } }
                margin_top(px(4.0))
                box("divider") {}
                text("muted","Changes remain local to this demo until you close it.")
            }
            column("card") {
                width(px(520.0)); margin_right(px(20))
                when(model.tab == 0) {
                    text("section","Workspace details")
                    text("caption","WORKSPACE NAME")
                    text_input("name_field") {
                        width(px(474.0))
                        bind_value(model.draft.name) $(value:string) { model.draft.name = value }
                    }
                    text("caption","CONTACT EMAIL")
                    text_input("email_field") {
                        width(px(474.0))
                        bind_value(model.draft.email) $(value:string) { model.draft.email = value }
                    }
                    when(!valid_email(model.draft.email)) { text("error","Enter an email address containing @ and a domain.") }
                    box("divider") {}
                    text("section","Notifications")
                    text("muted","Receive updates about workspace activity.")
                    button("notifications",model.draft.notifications ? "Notifications: ON" : "Notifications: OFF") {
                        padding(px(12.0)); margin_top(px(12.0)); background(rgb(225,216,211))
                        on_click() { model.draft.notifications = !model.draft.notifications }
                    }
                }
                when(model.tab == 1) {
                    text("section","Appearance")
                    text("caption","ACCENT COLOR")
                    row("toolbar") {
                        button("mint","Mint") { padding(px(14.0)); background(rgb(181,215,196)); on_click() { model.draft.mint = true } }
                        button("indigo","Indigo") { padding(px(14.0)); background(rgb(209,201,232)); on_click() { model.draft.mint = false } }
                    }
                    text("caption","CONTENT DENSITY")
                    button("density",model.draft.compact ? "Compact" : "Comfortable") {
                        padding(px(12.0)); background(rgb(225,216,211)); on_click() { model.draft.compact = !model.draft.compact }
                    }
                    text("muted","Spacing changes in the preview without rebuilding its cards.")
                }
                when(model.tab == 2) {
                    text("section","Connection")
                    text("good","Demo connection / no network requests")
                    button("advanced",model.draft.advanced ? "Hide advanced settings" : "Show advanced settings") {
                        padding(px(12.0)); background(rgb(225,216,211)); on_click() { model.draft.advanced = !model.draft.advanced }
                    }
                    when(model.draft.advanced) {
                        text("caption","ENDPOINT (DEMO VALUE)")
                        text_input("endpoint_field") {
                            width(px(474.0)); bind_value(model.draft.endpoint) $(value:string) { model.draft.endpoint = value }
                        }
                        text("warning","This sample does not connect to the endpoint.")
                    }
                }
                box("divider") {}
                text("muted",dirty(model) ? "You have unsaved changes" : "All changes saved")
                row() {
                    margin_top(px(15.0))
                    button("save","Save changes") {
                        padding(px(12.0)); background(rgb(181,215,196))
                        disabled() { return !valid_email(model.draft.email) || empty(model.draft.name) || !dirty(model) }
                        on_click() { model.saved = model.draft; model.saves += 1 }
                    }
                    button("reset","Discard") {
                        padding(px(12.0)); on_click() { model.draft = model.saved }
                    }
                }
                when(model.saves > 0) { text("good") { return "Saved locally ({model.saves})" } }
            }
            preview(model.draft)
        }
    }
}
[export]
def main(smoke:bool):int {
    var initial = Settings()
    var state=ui_state(initial)
    return run_demo("dasrmlui - Settings studio","logs/settings.png",smoke,$() { ui_frame(state) $(model:Settings) { settings(model) } }) $(frame:int) {
        ui_edit(state) $(var model:Settings) {
            if (frame == 0) { rui_test_event(ui_find("email_field"),"change","invalid") }
            elif (frame == 1) { verify(ui_find("error") != 0ul); rui_test_click(ui_find("reset")) }
            elif (frame == 2) { verify(valid_email(model.draft.email)); rui_test_click(ui_find("appearance_tab")) }
            elif (frame == 3) { verify(ui_find("name_field") == 0ul); rui_test_click(ui_find("indigo")) }
            elif (frame == 4) { verify(!model.draft.mint); rui_test_click(ui_find("save")) }
            elif (frame == 5) { verify(model.saves == 1 && !model.saved.mint); rui_test_click(ui_find("network_tab")) }
            elif (frame == 6) { rui_test_click(ui_find("advanced")) }
            elif (frame == 7) { verify(ui_find("endpoint_field") != 0ul) }
        }
    }
}
