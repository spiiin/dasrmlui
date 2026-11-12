options gen2
options persistent_heap
options gc
options stack = 65536
require examples/gl_demo_host
require strings
require math

struct Lab { enlarged:bool=true; note:string="Keep the northern relay online.\nNext supply window: 06:40." }
var mounts,unmounts:int
[ui_style]
def station_style() {
    spritesheet("examples/assets/style_atlas.png",2.) {
        sprite("night_frame",0,0,96,96); sprite("night_inner",24,24,48,48)
        sprite("paper_frame",96,0,96,96); sprite("paper_inner",120,24,48,48)
    }
    rule(part("shell")) { width(pct(100)); property("box-sizing","border-box"); padding(dp(28)); property("min-height","100%") }
    rule(part("header")) { font_size(dp(32)); margin_bottom(dp(8)); property("letter-spacing","3px") }
    rule(part("caption")) { font_size(dp(14)); margin_bottom(dp(22)) }
    rule(part("controls")) { property("flex-wrap","wrap"); margin_bottom(dp(20)) }
    rule(part("shell")+" button") { padding_y(dp(10)); padding_x(dp(15)); font_size(dp(14)); property("margin-right","8dp"); margin_bottom(dp(8)); property("border-radius","4dp"); property("cursor","pointer") }
    rule(part("shell")+" button:focus") { property("border","1dp #dcb566") }
    rule(part("gallery")) { property("align-items","flex-start") }
    rule(part("main")) { property("flex","1"); property("min-width","0px"); property("margin-right","24dp") }
    rule(part("eyebrow")) { font_size(dp(12)); property("letter-spacing","2px"); margin_bottom(dp(12)) }
    rule(part("preview")) { property("box-sizing","border-box"); property("max-width","100%"); padding(dp(24)); margin_bottom(dp(20)) }
    rule(part("title")) { font_size(dp(24)); margin_bottom(dp(14)) }
    rule(part("body_copy")) { font_size(dp(15)); margin_bottom(dp(16)) }
    rule(part("pills")) { property("flex-wrap","wrap") }
    rule(part("small_patch")) { width(dp(144)); padding(dp(18)); property("margin-right","14dp"); margin_bottom(dp(16)) }
    rule(part("metric")) { font_size(dp(22)); margin_top(dp(8)) }
    rule(part("sidebar")) { width(dp(280)); property("box-sizing","border-box"); padding(dp(24)); property("flex-shrink","0") }
    rule(part("note")) { width(pct(100)); property("box-sizing","border-box"); height(dp(128)); padding(dp(12)); font_size(dp(15)); property("white-space","pre-wrap"); property("border","1dp #6c8490"); margin_bottom(dp(16)) }
    rule(part("environment")) { font_size(dp(13)); margin_top(dp(14)) }
    rule(part("dpi_badge")) { property("display","none"); font_size(dp(12)); margin_top(dp(10)) }
    theme("night") {
        rule(part("shell")) { background(rgb(12,28,38)); color(rgb(218,235,237)) }
        rule(part("caption")+", "+part("body_copy")+", "+part("environment")) { color(rgb(155,185,196)) }
        rule(part("eyebrow")+", "+part("dpi_badge")) { color(rgb(220,181,102)) }
        rule(part("shell")+" button") { background(rgb(41,70,86)); color(rgb(230,239,232)) }
        rule(part("shell")+" button:hover") { background(rgb(62,96,111)) }
        rule(part("preview")+", "+part("sidebar")+", "+part("small_patch")) { ninepatch("night_frame","night_inner") }
        rule(part("note")) { background(rgb(12,30,40)); color(rgb(230,239,232)) }
    }
    theme("paper") {
        rule(part("shell")) { background(rgb(233,224,202)); color(rgb(67,63,50)) }
        rule(part("caption")+", "+part("body_copy")+", "+part("environment")) { color(rgb(111,103,82)) }
        rule(part("eyebrow")+", "+part("dpi_badge")) { color(rgb(139,100,41)) }
        rule(part("shell")+" button") { background(rgb(209,191,151)); color(rgb(65,56,37)) }
        rule(part("shell")+" button:hover") { background(rgb(225,203,154)) }
        rule(part("preview")+", "+part("sidebar")+", "+part("small_patch")) { ninepatch("paper_frame","paper_inner") }
        rule(part("note")) { background(rgb(255,251,238)); color(rgb(67,63,50)) }
    }
    media(media_max_width(dp(900))) {
        rule(part("gallery")) { property("flex-direction","column") }
        rule(part("main")) { width(pct(100)); property("flex","none"); property("margin-right","0px") }
        rule(part("sidebar")) { width(pct(100)); margin_top(dp(12)) }
    }
    media(media_min_resolution(1.25)) { rule(part("dpi_badge")) { property("display","block") } }
    media(media_orientation("portrait")) { rule(part("header")) { font_size(dp(26)) } }
}
[ui_component]
def environment_readout() {
    use_style(@@station_style)
    text("environment","Theme: {ui_theme()}   /   Scale: {int(ui_scale()*100.)}%   /   dp ratio: {ui_dp_ratio()}")
}
[ui_component]
def station(var model:Lab) {
    on_mount() { mounts+=1; set_theme("night") }
    on_unmount() { unmounts+=1 }
    use_style(@@station_style)
    column("shell") {
        width(px(ui_width())); property("min-height","{ui_height()}px")
        text("eyebrow","REMOTE OPERATIONS / STATION 04")
        text("header","The relay station")
        text("caption","Change the light, enlarge the controls, stretch a panel. Your field notes stay with you.")
        row("controls") {
            button("night","Night watch") { on_click() { set_theme("night") } }
            button("paper","Paper map") { on_click() { set_theme("paper") } }
            button("scale_100","100%") { on_click() { set_ui_scale(1.) } }
            button("scale_150","150%") { on_click() { set_ui_scale(1.5) } }
            button("stretch",model.enlarged ? "Shrink panel" : "Stretch panel") { on_click() { model.enlarged=!model.enlarged } }
        }
        row("gallery") {
            column("main") {
                column("preview") {
                    width(dp(model.enlarged ? 500 : 320)); height(dp(model.enlarged ? 230 : 180))
                    text("eyebrow","NORTHERN RELAY")
                    text("title","A clear signal")
                    text("body_copy","Survey teams are connected. The next supply drone arrives at first light.")
                    text("body_copy","UPLINK 98%  /  ALL CHANNELS OPEN")
                }
                row("pills") {
                    column("small_patch") { text("eyebrow","TEMPERATURE"); text("metric","-12 C") }
                    column("small_patch") { text("eyebrow","BATTERY"); text("metric","86%") }
                }
                text("caption","The same frame keeps its corners on every panel.")
            }
            column("sidebar") {
                text("eyebrow","FIELD JOURNAL")
                text("title","Leave a note")
                text_area("note") { bind_value(model.note) $(value:string) { model.note=value } }
                text("body_copy","Resize the window: the journal moves below the signal panel when space is limited.")
                text("dpi_badge","LARGE DISPLAY MODE")
            }
        }
        environment_readout()
    }
}
[export]
def main(smoke:bool):int {
    var model=Lab()
    var initialized=false
    var note,preview=0ul
    let result=run_gl_demo("dasrmlui - The relay station","logs/style_lab.png",smoke,
        $(delta:float) { if (smoke && !initialized) { rui_test_display_scale(1.); initialized=true } },
        $() { station(model) }) $(frame:int) {
        if (frame==0) { note=ui_find("note"); preview=ui_find("preview"); verify(rui_bounds(preview).z==500.); rui_test_event(note,"change","Keep this draft through every theme.") }
        elif (frame==1) { rui_test_click(ui_find("paper")) }
        elif (frame==2) { verify(theme_active("paper") && !theme_active("night")); rui_test_click(ui_find("scale_150")) }
        elif (frame==3) { verify(ui_scale()==1.5 && rui_bounds(preview).z==750. && rui_visible(ui_find("dpi_badge"))); rui_test_click(ui_find("scale_100")) }
        elif (frame==4) { rui_test_resize(760,820) }
        elif (frame==5) { verify(rui_bounds(ui_find("sidebar")).y>rui_bounds(preview).y+100.,"native media column layout"); rui_test_click(ui_find("stretch")) }
        elif (frame==6) { verify(rui_bounds(preview).z==320.); rui_test_resize(1200,820) }
        elif (frame==7) { verify(abs(rui_bounds(ui_find("sidebar")).y-rui_bounds(preview).y)<2.); rui_test_click(ui_find("night")) }
        elif (frame==8) { verify(theme_active("night")); rui_test_click(ui_find("stretch")) }
        elif (frame==11) {
            verify(ui_find("note")==note && ui_find("preview")==preview && rui_get_value(note)=="Keep this draft through every theme." && mounts==1)
            verify(rui_bounds(preview).z==500. && !rui_visible(ui_find("dpi_badge")))
            print("PASS: theme switching, dp scale, responsive media, ninepatch resizing and retained draft/handles\n")
        }
    }
    if (smoke) { verify(unmounts==1) }
    return result
}

