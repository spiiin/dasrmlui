options gen2
options persistent_heap
options gc
options stack = 65536
require examples/demo_host
require math
require strings

struct Windows { opened:array<bool>; show_notes:array<bool>; notes:array<string> }
struct WindowLife { document:uint64; index:int }
var documents:array<uint64>
var window_ids:array<int>
var mounted,unmounted:int
var editors_mounted,editors_unmounted:int

[ui_style]
def window_frame_style() {
    rule(root()) {
        position("absolute"); width(px(460)); height(px(460))
        // Opening a window focuses the desktop button first. Keep every tool
        // window above that full-size desktop document, including idle windows.
        z_index(1)
        min_width(px(320)); min_height(px(300))
        margin(px(0)); padding(px(0)); background(rgb(247,240,226)); color(rgb(65,61,56))
        border(px(2),rgb(151,129,109)); border_radius(px(12)); property("overflow","hidden")
    }
    rule(part("move")) { display("block"); height(px(42)); padding_y(px(12)); padding_x(px(18)); background(rgb(121,91,73)); color(rgb(255,244,220)); font_size(px(23)); property("cursor","move") }
    rule(part("mission_actions")) { display("block"); padding(px(12)); background(rgb(226,218,197)); border_bottom(px(1),rgb(199,185,155)) }
    rule(part("field_notes")) { display("block"); padding(px(22)) }
    rule(part("crew_status")) { position("absolute"); left(px(0)); right(px(0)); bottom(px(0)); padding_y(px(14)); padding_x(px(22)); background(rgb(230,224,205)); border_top(px(1),rgb(199,185,155)) }
    rule(part("resize")) { position("absolute"); right(px(2)); bottom(px(2)); width(px(28)); height(px(28)); background(rgb(179,154,119)); property("cursor","resize") }
}
[ui_template]
def workbench_window() {
    use_style(@@window_frame_style)
    window_frame("window") {
        move_handle("move") { title_slot("title") }
        slot("mission_actions")
        slot("field_notes")
        slot("crew_status")
        resize_handle("resize")
    }
}
def open_window(index:int):uint64 {
    return open_template(@@workbench_window,index==0 ? "Mission planner" : "Crew notes",
        float2(float(50+index*550),float(210+index*40)))
}
[ui_style]
def window_style() {
    rule(part("shell")) { padding(px(32)); background(rgb(210,218,211)); color(rgb(52,70,61)); min_height(px(756)) }
    rule(part("heading")) { font_size(px(36)); margin_bottom(px(12)) }
    rule(part("caption")) { margin_bottom(px(20)); color(rgb(90,106,94)) }
    rule(part("action")) { padding(px(12)); background(rgb(82,110,92)); color(rgb(250,249,232)); margin_right(px(12)); margin_bottom(px(12)); border_radius(px(5)) }
    rule(part("shell")+" button, "+part("actions")+" button") { padding(px(10)); background(rgb(82,110,92)); color(rgb(250,249,232)); margin_right(px(10)); border_radius(px(5)) }
    rule(part("editor")) { width(pct(95)); height(px(100)); padding(px(8)); border(px(1),rgb(186,165,139)); background(rgb(255,252,244)); color(rgb(65,61,56)); margin_bottom(px(20)); property("white-space","pre-wrap") }
    rule(part("subheading")) { font_size(px(24)); margin_bottom(px(12)) }
    rule(part("status")) { font_size(px(14)); color(rgb(99,86,68)) }
    rule(part("slot_hint")) { font_size(px(12)); color(rgb(150,119,89)); margin_bottom(px(12)); letter_spacing(px(1)) }
}
[ui_component]
def window_actions(var model:Windows; index:int) {
    use_style(@@window_style)
    row("actions") {
        button("toggle_notes",model.show_notes[index] ? "Hide notes" : "Show notes") { on_click() { model.show_notes[index]=!model.show_notes[index] } }
        button("mark_ready","Mark ready") { on_click() { model.notes[index]+=" Ready." } }
        button("close","Close window") { on_click() { model.opened[index]=false } }
    }
}
[ui_component]
def window_notes(var model:Windows; index:int) {
    use_style(@@window_style)
    on_mount() { editors_mounted+=1 }
    on_unmount() { editors_unmounted+=1 }
    column("content") {
        text("slot_hint","FIELD NOTES")
        text("subheading",index==0 ? "Plan the next expedition" : "Leave a message for the crew")
        text_area("editor") { bind_value(model.notes[index]) $(value:string) { model.notes[index]=value } }
        text("caption","Hide this editor independently. Its notes stay in the model.")
        font_size(px(16))
    }
}
[ui_component]
def window_status(model:Windows; index:int) {
    use_style(@@window_style)
    text("status","{length(model.notes[index])} characters  /  {model.show_notes[index] ? "Editor open" : "Editor hidden"}")
}
[ui_component]
def work_window(var model:Windows; index:int) {
    use_style(@@window_style)
    state(WindowLife(index=index)) $(var local:WindowLife) {
        on_mount() { local.document=open_window(index); documents[index]=local.document; mounted+=1 }
        on_unmount() { rui_close_document(local.document); documents[local.index]=0ul; unmounted+=1 }
        document_content(local.document,"mission_actions") { window_actions(model,index) }
        when(model.show_notes[index]) { document_content(local.document,"field_notes") { window_notes(model,index) } }
        document_content(local.document,"crew_status") { window_status(model,index) }
    }
}
[ui_component]
def window_desktop(var model:Windows) {
    use_style(@@window_style)
    column("shell") {
        width(px(ui_width()-64.))
        text("heading","The field office")
        text("caption","One frame, three named slots: actions, field notes and crew status. Each window has independent content.")
        row() {
            button("open_planner","Open planner") { on_click() { model.opened[0]=true } }
            button("open_notes","Open notes") { on_click() { model.opened[1]=true } }
        }
    }
    window_ids |> each_keyed($(index:int)=>index) $(index:int) {
        when(model.opened[index]) { work_window(model,index) }
    }
}
[export]
def main(smoke:bool):int {
    var model=Windows()
    model.opened <- array<bool>(true,true)
    model.show_notes <- array<bool>(true,true)
    model.notes <- array<string>("Map the eastern valley.\nDeparture: 07:30.","Bring spare batteries.\nWeather is clear.")
    window_ids <- array<int>(0,1); documents <- array<uint64>(0ul,0ul)
    var before=float4(0.)
    var size=float4(0.)
    var old,editor,slot_host,status,other_editor=0ul
    let result=run_demo("dasrmlui - The field office","logs/templates.png",smoke,$() { window_desktop(model) }) $(frame:int) {
        if (frame==0) {
            verify(mounted==2 && editors_mounted==2)
            editor=ui_find("editor",0); other_editor=ui_find("editor",1); status=ui_find("status",0)
            slot_host=rui_document_element(documents[0],"field_notes")
            verify(rui_contains(slot_host,editor) && rui_contains(rui_document_element(documents[0],"crew_status"),status))
            before=rui_bounds(documents[0]); rui_test_drag_offset(rui_document_element(documents[0],"move"),35.,25.)
        }
        elif (frame==1) { let moved=rui_bounds(documents[0]); verify(abs(moved.x-before.x-35.)<2. && abs(moved.y-before.y-25.)<2.,"native move handle"); size=moved; rui_test_drag_offset(rui_document_element(documents[0],"resize"),45.,30.) }
        elif (frame==2) { let resized=rui_bounds(documents[0]); verify(abs(resized.z-size.z-45.)<2. && abs(resized.w-size.w-30.)<2.,"native resize handle"); rui_focus(ui_find("editor",0)); rui_test_text(" Ready.") }
        elif (frame==3) { verify(find(model.notes[0],"Ready.")>=0 && ui_find("status",0)==status); rui_test_click(ui_find("toggle_notes",0)) }
        elif (frame==4) {
            verify(!rui_alive(editor) && rui_alive(slot_host) && empty(rui_inner_markup(slot_host)) && editors_unmounted==1,"unmount one slot only")
            verify(rui_alive(status) && ui_find("editor",1)==other_editor && find(rui_inner_markup(status),"hidden")>=0)
            rui_test_click(ui_find("toggle_notes",0))
        }
        elif (frame==5) {
            verify(ui_find("editor",0)!=editor && editors_mounted==3 && find(rui_get_value(ui_find("editor",0)),"Ready.")>=0)
            old=documents[0]; rui_test_click(ui_find("close",0))
        }
        elif (frame==6) { verify(!rui_alive(old) && unmounted==1 && editors_unmounted==2); rui_test_click(ui_find("open_planner")) }
        elif (frame==7) {
            verify(documents[0]!=0ul && documents[0]!=old && mounted==3 && editors_mounted==4)
            verify(ui_find("editor",1)==other_editor && find(rui_get_value(ui_find("editor",0)),"Ready.")>=0)
            rui_test_click(ui_find("mark_ready",1))
            ui_frame() { window_desktop(model) }
            verify(find(model.notes[1],"Ready.")>=0,"other window remains interactive after reopening planner")
            print("PASS: three named slots, independent components, selective unmount, native handles, binding and close/reopen\n")
        }
    }
    if (smoke) { verify(unmounted==3 && editors_unmounted==4,"ui_reset closes remaining documents and slot contents") }
    return result
}

