options gen2
options persistent_heap
options gc
options stack = 65536
require examples/demo_host
require strings

struct Tile { id:int; title,detail:string }
struct Lab { tiles:array<Tile>; selected:int; activated:string="Nothing activated"; blocked:bool; mode:UiNav=UiNav.Auto }
struct Popup { document:uint64 }
var menu:uint64

[ui_style]
def deck_style() {
    rule(part("desktop")) { background(rgb(17,30,38)); color(rgb(225,236,235)); padding(px(40)); height(px(740)) }
    rule(part("eyebrow")) { letter_spacing(px(3)); color(rgb(120,187,175)); font_size(px(12)); margin_bottom(px(10)); margin_top(px(30)) }
    rule(part("heading")) { font_size(px(44)); margin_bottom(px(12)) }
    rule(part("intro")) { color(rgb(143,167,175)); margin_bottom(px(20)) }
    rule(part("toolbar")+" button") { nav(UiNav.Horizontal); padding(px(10)); margin_right(px(10)); background(rgb(37,61,69)); color(rgb(208,231,226)); border(px(1),rgb(82,110,119)); border_radius(px(4)) }
    rule(part("toolbar")+" button:focus-visible") { border_color(rgb(245,207,112)) }
    rule(part("grid")) { position("absolute"); left(px(40)); top(px(275)); width(px(690)); height(px(350)); property("overflow","auto") }
    rule(part("tile")) { position("absolute"); width(px(210)); height(px(145)); property("box-sizing","border-box"); padding(px(18)); border(px(2),rgb(55,83,94)); border_radius(px(9)); background(rgb(29,48,58)); color(rgb(219,235,233)); nav() }
    rule(part("tile")+":hover") { background(rgb(38,63,73)) }
    rule(part("tile")+":focus") { border_color(rgb(131,184,173)) }
    rule(part("tile")+":focus-visible") { border_color(rgb(244,207,117)); background(rgb(53,70,66)); color(rgb(255,233,177)) }
    rule(part("tile")+":disabled") { opacity(0.35) }
    rule(part("number")) { font_size(px(13)); color(rgb(110,162,157)); margin_bottom(px(15)) }
    rule(part("tile_title")) { font_size(px(23)); margin_bottom(px(8)) }
    rule(part("tile_detail")) { font_size(px(13)); color(rgb(151,180,182)) }
    rule(part("side")) { position("absolute"); left(px(770)); top(px(275)); width(px(335)); padding(px(22)); background(rgb(26,43,51)); border_radius(px(9)) }
    rule(part("side_title")) { font_size(px(22)); margin_bottom(px(14)) }
    rule(part("side_text")) { color(rgb(151,180,182)); property("line-height","24px"); margin_bottom(px(18)) }
    rule(part("scroll")) { width(px(290)); height(px(115)); property("overflow-y","auto"); padding(px(8)); background(rgb(17,30,38)) }
    rule(part("scroll")+" button") { nav(UiNav.Vertical); height(px(36)); flex_shrink(0.); padding(px(8)); border_bottom(px(1),rgb(55,83,94)); color(rgb(175,206,199)) }
    rule(part("scroll")+" button:focus-visible") { background(rgb(66,83,65)); color(rgb(255,230,170)) }
    rule(part("status")) { position("absolute"); left(px(40)); top(px(660)); font_size(px(16)); color(rgb(183,207,198)) }
    rule(part("debug_status")) { position("absolute"); left(px(40)); top(px(710)); font_size(px(13)); color(rgb(120,187,175)) }
    rule(part("menu_items")+" button") { nav(UiNav.Horizontal); padding(px(16)); background(rgb(235,205,129)); color(rgb(45,53,44)); margin_right(px(8)) }
    rule(part("menu_items")+" button:focus-visible") { background(rgb(255,236,183)) }
}
[ui_template]
def command_popup() {
    window_frame("frame") {
        nav(); position("absolute"); z_index(3); width(px(300)); height(px(80)); padding(px(16))
        margin(px(0)); background(rgb(58,75,65)); border(px(2),rgb(217,187,111)); border_radius(px(8))
        slot("items")
    }
}
[ui_component]
def debug_status() {
    use_style(@@deck_style)
    text("debug_status",debugger_visible() ? "F8  /  Debugger ON - choose Element Info, then click a tile" : "F8  /  Open the native RmlUi Debugger")
}
[ui_component]
def tile_view(var model:Lab; tile:Tile) {
    use_style(@@deck_style)
    button("tile") {
        nav_id("deck_tile_{tile.id}"); nav(model.mode)
        left(px((tile.id % 3)*230)); top(px((tile.id / 3)*165))
        disabled() { return model.blocked && tile.id==1 }
        // A deliberate native ID edge: Left on 01 jumps to 06.
        if (tile.id==0) { nav_left(nav_to("deck_tile_5")) }
        on_event("focus") $(event:UiEvent) { model.selected=tile.id }
        on_click() { model.activated=tile.title; if (tile.id==5) { show_popup(menu,float2(300.,380.)) } }
        column() {
            text("number","0{tile.id+1} / NAV TARGET")
            text("tile_title",tile.title)
            text("tile_detail",tile.detail)
        }
    }
}
[ui_component]
def deck(var model:Lab) {
    use_style(@@deck_style)
    state(Popup()) $(var local:Popup) {
        on_mount() {
            debugger_hotkey()
            local.document=open_template(@@command_popup,"Actions",float2(0.),UiDocumentOptions(visible=false)); menu=local.document
            request_focus("tile",0)
        }
        on_unmount() { close_document(local.document); debugger_shutdown() }
        document_nav(rui_root())
        column("desktop") {
            width(px(ui_width()-80.))
            text("eyebrow","NATIVE RMLUI  /  NAVIGATION & INSPECTION")
            text("heading","Vector deck")
            text("intro","Use arrows to explore, Enter to activate. Left on tile 01 jumps directly to tile 06.")
            row("toolbar") {
                button("focus_grid","Focus tiles") { on_click() { request_focus("tile",0) } }
                button("mode","Mode: {model.mode}") {
                    on_click() { model.mode=model.mode==UiNav.Auto ? UiNav.TreeOrder : UiNav.Auto; request_focus("tile",0) }
                }
                button("disable","{model.blocked ? "Enable" : "Disable"} tile 02") { on_click() { model.blocked=!model.blocked; request_focus("tile",0) } }
                button("debugger","Debugger / F8") { on_click() { debugger_toggle() } }
            }
            focus_scope("grid") {
                model.tiles |> each_keyed($(tile:Tile)=>tile.id) $(tile:Tile) { tile_view(model,tile) }
            }
            column("side") {
                text("side_title","Native rules")
                text("side_text","Auto follows geometry inside this scroll region. TreeOrder follows DOM order. Tab stays inside the tile focus scope.")
                column("scroll") {
                    model.tiles |> each_keyed($(tile:Tile)=>tile.id) $(tile:Tile) {
                        button("scroll_item","0{tile.id+1}  {tile.title}") { on_click() { model.activated="Scroll: {tile.title}" } }
                    }
                }
            }
            text("status","Focused tile: 0{model.selected+1}     /     Activated: {model.activated}")
            debug_status()
        }
        document_content(local.document,"items") {
            row("menu_items") {
                button("accept","Confirm") { attribute("autofocus",""); on_click() { model.activated="Confirmed"; hide_document(local.document) } }
                button("dismiss","Cancel") { on_click() { model.activated="Cancelled"; hide_document(local.document) } }
            }
        }
    }
}
[export]
def main(smoke:bool):int {
    var model=Lab()
    model.tiles <- array<Tile>(
        Tile(id=0,title="Signals",detail="Left links to tile 06"), Tile(id=1,title="Routes",detail="Try disabling this tile"),
        Tile(id=2,title="Telemetry",detail="Geometric neighbours"), Tile(id=3,title="Archive",detail="Stable keyed identity"),
        Tile(id=4,title="Sensors",detail="Native focus-visible"), Tile(id=5,title="Actions",detail="Enter opens a popup"))
    var inspected:uint64
    return run_demo("Vector deck - native RmlUi tools","logs/navigation_lab.png",smoke,$() { deck(model) },$(frame:int) {
        if (frame==0) { verify(rui_focused(ui_find("tile",0))); rui_test_shortcut("Right",0) }
        elif (frame==1) { verify(rui_focused(ui_find("tile",1))); rui_test_shortcut("Down",0) }
        elif (frame==2) {
            verify(rui_focused(ui_find("tile",4)))
            rui_focus(ui_find("tile",0)); rui_test_shortcut("Left",0)
            verify(rui_focused(ui_find("tile",5)),"native explicit edge")
            rui_test_shortcut("Return",0)
        } elif (frame==3) {
            verify(document_visible(menu)); rui_test_shortcut("Right",0)
            verify(rui_focused(ui_find("dismiss")),"native navigation inside popup")
            rui_test_key("Escape",false); rui_test_shortcut("F8",0)
        } elif (frame==4) {
            verify(debugger_visible() && !document_visible(menu))
            let tools=rui_test_debugger_document("menu")
            rui_test_click(rui_document_element(tools,"debug-info-button")); rui_update()
            inspected=ui_find("tile",3); rui_test_click(inspected)
        } elif (frame==5) {
            verify(find(rui_inner_markup(rui_test_debugger_document("info")),"deck_tile_3")>=0,"native inspector selected keyed tile")
            verify(model.activated=="Actions","inspection did not activate tile")
            rui_test_shortcut("F8",0)
        } elif (frame==6) {
            verify(!debugger_visible()); rui_test_shortcut("F8",0)
            rui_test_click(rui_document_element(rui_test_debugger_document("menu"),"debug-info-button")); rui_update()
            rui_test_click(ui_find("tile",0))
        } elif (frame==7) {
            verify(debugger_visible() && rui_alive(inspected))
            verify(find(rui_inner_markup(rui_test_debugger_document("info")),"deck_tile_0")>=0)
            print("PASS: native navigation, popup keyboard, F8, inspector picking and stable keyed handles\n")
        }
    })
}
