options gen2
options persistent_heap
options gc
options stack = 65536
require examples/demo_host
require strings

struct Entry { id:int; message:string }
struct Studio { entries:array<Entry>; saves:int; revision:int }
struct Windows { editor,menu,dialog:uint64 }
struct Draft { value:string="A quiet channel.\n\nCapture the idea before it disappears.\nThis draft stays alive when the editor is hidden." }
var windows=Windows()
var saved=""
var editor_mounts:int

def record(var model:Studio; message:string) {
    model.entries |> push <| Entry(id=model.revision,message=message)
    if (length(model.entries)>8) { model.entries |> erase(0) }
    model.revision+=1
}

[ui_style]
def desk_style() {
    rule(part("desk")) { padding(px(40)); height(px(740)); background(rgb(229,233,239)); color(rgb(36,49,69)) }
    rule(part("eyebrow")) { font_size(px(13)); color(rgb(63,93,169)); property("letter-spacing","3px"); margin_bottom(px(12)) }
    rule(part("heading")) { font_size(px(48)); margin_bottom(px(10)) }
    rule(part("lede")) { color(rgb(93,108,129)); margin_bottom(px(24)) }
    rule(part("toolbar")+" button") { padding_y(px(10)); padding_x(px(18)); property("margin-right","10px"); background(rgb(255,255,255)); color(rgb(44,65,105)); property("border","1px #c2ccdd"); property("border-radius","5px") }
    rule(part("toolbar")+" button:hover") { background(rgb(214,224,245)) }
    rule(part("journal")) { property("position","absolute"); property("left","750px"); property("top","250px"); width(px(350)); padding(px(20)); background(rgb(245,247,251)); property("border-radius","8px") }
    rule(part("journal_title")) { font_size(px(22)); margin_bottom(px(16)) }
    rule(part("entry")) { padding_y(px(9)); font_size(px(14)); color(rgb(78,96,124)); property("border-bottom","1px #dde3ed") }
    rule(part("hint")) { font_size(px(13)); color(rgb(109,125,147)); margin_bottom(px(16)); property("line-height","21px") }
    rule(part("footer")) { property("position","absolute"); property("left","40px"); property("top","715px"); font_size(px(14)); color(rgb(95,112,138)) }
}
[ui_style]
def editor_frame_style() {
    rule(root()) { property("position","absolute"); property("z-index","1"); width(px(650)); height(px(430)); property("min-width","460px"); property("min-height","300px"); property("margin","0px"); background(rgb(251,252,255)); color(rgb(36,49,69)); property("border","1px #adbcd2"); property("border-radius","8px"); property("overflow","hidden") }
    rule(part("move")) { property("display","block"); padding(px(18)); background(rgb(45,65,101)); color(rgb(239,245,255)); font_size(px(19)); property("cursor","move") }
    rule(part("body")) { property("display","block"); padding(px(24)) }
    rule(part("resize")) { property("position","absolute"); property("right","2px"); property("bottom","2px"); width(px(18)); height(px(18)); background(rgb(157,180,217)); property("cursor","resize") }
}
[ui_template]
def editor_window() {
    use_style(@@editor_frame_style)
    window_frame("frame") { move_handle("move") { title_slot("title") }; slot("body"); resize_handle("resize") }
}
[ui_template]
def menu_window() {
    window_frame("frame") {
        property("position","absolute"); property("z-index","3"); width(px(250)); height(px(206)); property("margin","0px")
        padding(px(8)); background(rgb(35,49,75)); color(rgb(240,246,255)); property("border","1px #7f98bc"); property("border-radius","7px")
        slot("items")
    }
}
[ui_template]
def dialog_window() {
    window_frame("frame") {
        property("position","absolute"); property("z-index","2"); width(px(440)); height(px(225)); property("margin","0px")
        padding(px(28)); background(rgb(255,250,235)); color(rgb(62,59,49)); property("border","2px #bca36e"); property("border-radius","10px")
        slot("body")
    }
}
[ui_style]
def controls_style() {
    rule(part("caption")) { font_size(px(12)); color(rgb(116,132,155)); margin_bottom(px(14)); property("letter-spacing","2px") }
    rule(part("draft")) { width(pct(94)); height(px(180)); padding(px(12)); background(rgb(239,243,249)); color(rgb(46,61,85)); property("border","1px #d2dce9"); property("white-space","pre-wrap"); property("line-height","24px"); margin_bottom(px(18)) }
    rule(part("actions")+" button") { padding_y(px(10)); padding_x(px(18)); property("margin-right","10px"); background(rgb(64,95,159)); color(rgb(255,255,255)); property("border-radius","4px") }
    rule(part("actions")+" button:hover, "+part("actions")+" button:focus") { background(rgb(89,125,197)) }
    rule(part("menu_title")) { font_size(px(11)); color(rgb(143,171,213)); padding(px(10)); property("letter-spacing","2px") }
    rule(part("items")+" button") { property("display","block"); padding(px(12)); color(rgb(229,239,255)); property("border-radius","4px") }
    rule(part("items")+" button:hover, "+part("items")+" button:focus") { background(rgb(63,90,137)) }
    rule(part("dialog_title")) { font_size(px(28)); margin_bottom(px(16)) }
    rule(part("dialog_text")) { property("line-height","24px"); margin_bottom(px(24)) }
}
[ui_component]
def editor_content(var model:Studio) {
    use_style(@@controls_style)
    state(Draft()) $(var local:Draft) {
        on_mount() { editor_mounts+=1 }
        document_events(windows.editor) {
            on_event("keydown",UiEventOptions(use_capture=true,key="S",modifiers=1,stop=true)) $(event:UiEvent) {
                saved=local.value; model.saves+=1; record(model,"Ctrl+S / saved {length(saved)} characters")
            }
        }
        document_content(windows.editor,"body") {
            text("caption","DRAFT 01   /   LOCAL COMPONENT STATE")
            text_area("draft") { bind_value(local.value) $(value:string) { local.value=value } }
            row("actions") {
                button("save","Save draft") {
                    on_click() { saved=local.value; model.saves+=1; record(model,"Saved from the editor") }
                }
                button("hide","Hide editor") { on_click() { hide_document(windows.editor); record(model,"Editor hidden / state retained") } }
            }
        }
    }
}
[ui_component]
def studio(var model:Studio) {
    use_style(@@desk_style)
    state(Windows()) $(var local:Windows) {
        on_mount() {
            local.editor=open_template(@@editor_window,"Channel notes",float2(40.,250.))
            local.menu=open_template(@@menu_window,"Commands",float2(0.),UiDocumentOptions(visible=false))
            local.dialog=open_template(@@dialog_window,"Publish",float2(340.,300.),UiDocumentOptions(visible=false))
            windows=local
        }
        on_unmount() { close_document(local.menu); close_document(local.dialog); close_document(local.editor) }
        editor_content(model)
        column("desk") {
            width(px(ui_width()-80.))
            text("eyebrow","WORKSPACE  /  EVENTS & DOCUMENTS")
            text("heading","Signal desk")
            text("lede","A retained editor, a keyboard menu and a modal publishing dialog. Each is a native document.")
            row("toolbar") {
                button("commands","Commands  +") {
                    on_click() { show_popup(local.menu,float2(40.,220.)); record(model,"Menu opened / modal focus") }
                }
                button("restore","Show editor") { on_click() { show_document(local.editor); bring_to_front(local.editor); record(model,"Editor shown / same draft") } }
                button("publish","Publish...") { on_click() { show_document(local.dialog,UiDocumentOptions(modal=UiModal.Modal)); record(model,"Publish dialog / background blocked") } }
            }
            column("journal") {
                text("journal_title","Event journal")
                text("hint","Ctrl+S saves the draft. Right-click the editor for commands. Escape or an outside click dismisses the menu.")
                model.entries |> each_keyed($(entry:Entry)=>entry.id) $(entry:Entry) { text("entry",entry.message) }
            }
            text("footer","{model.saves} saves   /   {editor_mounts} editor mount   /   hide and reopen without losing the draft")
        }
        document_events(local.editor) {
            on_event("mousedown") $(event:UiEvent) {
                if (event.button==1) { show_popup(local.menu,event.screen); record(model,"Context menu / right button") }
            }
        }
        document_events(local.menu) {
            on_event("dismiss") $(event:UiEvent) { record(model,"Menu dismissed / {event_parameter(event,"reason")}") }
            on_event("keydown",UiEventOptions(key="Down",stop=true)) $(event:UiEvent) { focus_next(local.menu) }
            on_event("keydown",UiEventOptions(key="Up",stop=true)) $(event:UiEvent) { focus_next(local.menu,true) }
        }
        document_events(local.dialog) {
            on_event("keydown",UiEventOptions(key="Escape",stop=true)) $(event:UiEvent) { hide_document(local.dialog); record(model,"Publish cancelled / Escape") }
        }
        document_content(local.menu,"items") {
            use_style(@@controls_style)
            column("items") {
                text("menu_title","COMMAND PALETTE")
                button("menu_open","Open notes") { attribute("autofocus",""); on_click() { hide_document(local.menu); show_document(local.editor); bring_to_front(local.editor); record(model,"Open notes / menu action") } }
                button("menu_publish","Publish draft...") { on_click() { hide_document(local.menu); show_document(local.dialog,UiDocumentOptions(modal=UiModal.Modal)); record(model,"Publish / menu action") } }
                button("menu_hide","Hide notes") { on_click() { hide_document(local.menu); hide_document(local.editor); record(model,"Hide notes / menu action") } }
            }
        }
        document_content(local.dialog,"body") {
            use_style(@@controls_style)
            column() {
                text("dialog_title","Ready to publish?")
                text("dialog_text","The other documents cannot receive input while this dialog has modal focus. Your editor stays mounted.")
                row("actions") {
                    button("confirm","Publish") { on_click() { hide_document(local.dialog); record(model,"Published / focus returned to editor") } }
                    button("cancel","Keep editing") { on_click() { hide_document(local.dialog); record(model,"Cancelled / draft untouched") } }
                }
            }
        }
    }
}
[export]
def main(smoke:bool):int {
    var model=Studio()
    record(model,"Workspace mounted / 3 documents")
    var draft:uint64
    return run_demo("Signal desk - events and documents","logs/event_studio.png",smoke,$() { studio(model) },$(frame:int) {
        if (frame==0) {
            draft=ui_find("draft"); rui_focus(draft)
            rui_test_event(draft,"change","A persistent studio draft.")
            rui_test_shortcut("S",1)
        } elif (frame==1) {
            verify(saved=="A persistent studio draft." && model.saves==1,"shortcut sees latest draft")
            rui_test_click(ui_find("commands"))
        } elif (frame==2) {
            verify(document_visible(windows.menu),"commands popup visible")
            rui_test_key("Down",false)
            ui_frame() { studio(model) }
            verify(rui_focused(ui_find("menu_publish")),"Down moves menu focus")
            rui_test_key("Enter",false)
        } elif (frame==3) {
            verify(document_visible(windows.dialog) && document_modal(windows.dialog),"keyboard menu opens modal")
            rui_test_click(ui_find("confirm"))
        } elif (frame==4) {
            verify(!document_visible(windows.dialog),"confirm closes modal")
            rui_test_click(ui_find("hide"))
        } elif (frame==5) {
            verify(!document_visible(windows.editor) && rui_alive(draft),"hidden editor retained")
            rui_test_click(ui_find("restore"))
        } elif (frame==6) {
            verify(ui_find("draft")==draft && editor_mounts==1,"same editor incarnation")
            let bounds=rui_bounds(draft)
            rui_test_pointer(bounds.x+30.,bounds.y+30.,1,0.)
        } elif (frame==7) {
            verify(document_visible(windows.menu),"right-click context menu")
            print("PASS: studio shortcut, keyboard popup menu, modal action, hidden local draft and context menu\n")
        }
    })
}
