options gen2
options persistent_heap
options gc
options stack = 65536
require examples/gl_demo_host
require examples/showcase_style

struct Notice { id:int; visible:bool=true; heading,detail:string }
struct Menu {
    briefing:bool=true
    ambient:bool=true
    launching:bool
    launches,completed:int
    notices:array<Notice>
}
struct Briefing { callsign:string="KESTREL / 07" }
var panel_mounts,panel_unmounts:int

[ui_style]
def orbital_style() {
    expedition_sprites()
    keyframes("arrive") {
        keyframe(0.) { opacity(0.); property("transform","translateX(48px)") }
        keyframe(100.) { opacity(1.); property("transform","translateX(0px)") }
    }
    keyframes("depart") {
        keyframe(0.) { opacity(1.); property("transform","translateX(0px)") }
        keyframe(100.) { opacity(0.); property("transform","translateX(48px)") }
    }
    keyframes("float") {
        keyframe(0.) { property("transform","translateY(-8px) rotate(-3deg)") }
        keyframe(100.) { property("transform","translateY(8px) rotate(3deg)") }
    }
    keyframes("pulse") {
        keyframe(0.) { opacity(0.3); property("transform","scale(0.9)") }
        keyframe(100.) { opacity(1.); property("transform","scale(1.1)") }
    }
    keyframes("launch") {
        keyframe(0.) { opacity(0.4); property("transform","scale(0.90)") }
        keyframe(45.) { opacity(1.); property("transform","scale(1.12)") }
        keyframe(100.) { opacity(1.); property("transform","scale(1)") }
    }
    rule(part("shell")) { padding(px(32)); background(rgb(16,22,25)); color(rgb(232,238,223)); min_height(px(756)) }
    rule(part("header")) { property("justify-content","space-between"); property("align-items","center"); padding_y(px(14)); margin_bottom(px(30)); border_bottom(px(1),rgb(64,80,68)) }
    rule(part("brand")) { font_size(px(30)); letter_spacing(px(6)) }
    rule(part("eyebrow")) { color(rgb(181,222,111)); font_size(px(12)); letter_spacing(px(2)); margin_bottom(px(12)) }
    rule(part("muted")) { color(rgb(145,163,153)); font_size(px(14)); margin_bottom(px(16)) }
    rule(part("nav")) { width(px(224)); flex_shrink(0.); margin_right(px(28)) }
    rule(part("shell")+" button") {
        padding_y(px(13)); padding_x(px(16)); background(rgb(34,44,41)); color(rgb(223,235,213));
        border(px(1),rgb(66,84,70)); border_radius(px(6)); margin_bottom(px(10));
        property("transition","background-color 0.2s, transform 0.2s"); property("cursor","pointer")
    }
    rule(part("shell")+" button:hover") { background(rgb(60,79,52)); property("transform","translateX(3px)") }
    rule(part("shell")+" button:focus") { border_color(rgb(197,239,132)) }
    rule(part("shell")+" "+part("launch_button")) { background(rgb(186,226,116)); color(rgb(25,38,26)); margin_top(px(22)) }
    rule(part("stage")) { width(px(460)); height(px(500)); position("relative"); flex_shrink(0.); margin_right(px(26)); property("overflow","hidden"); border(px(1),rgb(64,80,68)); border_radius(px(18)); property("decorator","vertical-gradient(#283d32 #121d20)"); padding(px(24)) }
    rule(part("orbit")) { position("absolute"); left(px(59)); top(px(95)); width(px(338)); height(px(338)); border(px(1),rgb(113,141,84)); border_radius(px(180)) }
    rule(part("inner_orbit")) { position("absolute"); left(px(89)); top(px(125)); width(px(278)); height(px(278)); border(px(1),rgb(66,91,70)); border_radius(px(150)) }
    rule(part("vehicle")) { position("absolute"); left(px(58)); top(px(88)); width(px(350)); height(px(350)); property("transform","translateY(0px) rotate(0deg)") }
    rule(part("ship")) { width(pct(100)); height(pct(100)) }
    rule(part("beacon")) { position("absolute"); left(px(49)); top(px(245)); width(px(20)); height(px(20)); background(rgb(192,236,120)); border_radius(px(12)); opacity(1.) }
    rule(part("vehicle_name")) { position("absolute"); left(px(24)); bottom(px(74)); font_size(px(34)) }
    rule(part("vehicle_detail")) { position("absolute"); left(px(24)); bottom(px(44)); color(rgb(159,184,160)); font_size(px(14)) }
    rule(part("badge")) { position("absolute"); right(px(24)); top(px(24)); background(rgb(176,217,108)); color(rgb(24,40,28)); padding(px(10)); border_radius(px(4)); opacity(1.); property("transform","scale(1)") }
    rule(part("side")) { property("flex","1"); min_width(px(240)) }
    rule(part("briefing")) { padding(px(20)); background(rgb(31,42,38)); border(px(1),rgb(82,100,72)); border_radius(px(12)); margin_bottom(px(18)); opacity(1.); property("transform","translateX(0px)") }
    rule(part("section")) { font_size(px(23)); margin_bottom(px(18)) }
    rule(part("callsign")) { width(pct(100)); height(px(36)); padding(px(7)); background(rgb(17,27,25)); color(rgb(222,238,205)); border(px(1),rgb(113,134,89)); margin_bottom(px(14)) }
    rule(part("readout")) { padding_y(px(12)); border_top(px(1),rgb(64,80,68)); color(rgb(189,209,178)); font_size(px(14)) }
    rule(part("toast")) { padding(px(16)); background(rgb(48,64,46)); border_left(px(3),rgb(190,232,123)); border_radius(px(6)); margin_bottom(px(12)); opacity(1.); property("transform","translateX(0px)") }
    rule(part("toast_title")) { font_size(px(17)); margin_bottom(px(7)) }
    rule(part("toast_copy")) { font_size(px(13)); color(rgb(176,194,164)); margin_bottom(px(12)) }
    rule(part("shell")+" "+part("dismiss")) { padding_y(px(6)); font_size(px(12)); margin_bottom(px(0)); background(rgb(37,50,35)) }
    rule(part("footer")) { margin_top(px(28)); padding_y(px(16)); border_top(px(1),rgb(64,80,68)); property("justify-content","space-between"); font_size(px(13)); color(rgb(149,170,151)) }
}
[ui_component]
def briefing_content() {
    use_style(@@orbital_style)
    state(Briefing()) $(var local:Briefing) {
        on_mount() { panel_mounts+=1 }
        on_unmount() { panel_unmounts+=1 }
        focus_scope("briefing_focus") {
            column() {
                text("eyebrow","MISSION / 012")
                text("section","Beyond the ridge")
                text("muted","A quiet flight over the eastern basin. Collect samples before nightfall.")
                text_input("callsign") { bind_value(local.callsign) $(value:string) { local.callsign=value } }
                text("readout","RANGE                 240 KM")
                text("readout","WEATHER          CLEAR")
                text("readout","CREW                    02 / 02")
            }
        }
    }
}
[ui_component]
def notification(var model:Menu; index:int) {
    use_style(@@orbital_style)
    animated_when("toast",model.notices[index].visible,motion("arrive",0.32),motion("depart",0.32)) {
        text("toast_title",model.notices[index].heading)
        text("toast_copy",model.notices[index].detail)
        button("dismiss","Dismiss") { on_click() { model.notices[index].visible=false } }
    }
}
[ui_component]
def orbital_menu(var model:Menu) {
    use_style(@@orbital_style)
    column("shell") {
        width(px(ui_width()-64.))
        row("header") { text("brand","ORBITAL"); text("eyebrow","FLIGHT OPERATIONS   /   SECTOR 07") }
        row() {
            column("nav") {
                text("eyebrow","EXPEDITION CONTROL")
                button("toggle_panel",model.briefing ? "01    Hide briefing" : "01    Mission briefing") { on_click() { model.briefing=!model.briefing } }
                button("notify","02    Contact the crew") { on_click() { model.notices[0].visible=true } }
                button("ambient",model.ambient ? "03    Stop ambient motion" : "03    Start ambient motion") { on_click() { model.ambient=!model.ambient } }
                button("launch_button","Launch expedition   >") { on_click() { model.launches+=1; model.launching=true } }
                text("muted","Flight checks complete. Your scout is ready for departure.")
            }
            box("stage") {
                text("eyebrow","SCOUT CLASS   /   MK IV")
                box("orbit") {}; box("inner_orbit") {}
                box("vehicle") { animate(motion("float",3.2,"sine-in-out",-1,true),0,model.ambient); sprite_image("ship","scout") }
                box("beacon") { animate(motion("pulse",1.4,"sine-in-out",-1,true),0,model.ambient) }
                text("vehicle_name","Kestrel")
                text("vehicle_detail","LONG-RANGE RECONNAISSANCE")
                box("badge") {
                    animate(motion("launch",0.3,"cubic-out"),model.launches,model.launching)
                    text("badge_text",model.launching ? "LAUNCHING" : "FLIGHT READY")
                    on_animation_end() $(name:string) {
                        model.completed+=1; model.launching=false
                        model.notices[0].heading="Flight plan accepted"
                        model.notices[0].detail="The Kestrel is cleared for departure."
                        model.notices[0].visible=true
                    }
                }
            }
            column("side") {
                animated_when("briefing",model.briefing,motion("arrive",0.4),motion("depart",0.4)) { briefing_content() }
                model.notices |> each_keyed($(notice:Notice)=>notice.id) $(notice:Notice) { notification(model,notice.id) }
            }
        }
        row("footer") {
            text("footer_left","UPLINK ESTABLISHED    /    SIGNAL 98%")
            text("footer_right","SUCCESSFUL LAUNCHES  {model.completed}    /    ALL SYSTEMS NOMINAL")
        }
    }
}
[export]
def main(smoke:bool):int {
    var model=Menu()
    model.notices |> push(Notice(id=0,heading="Welcome aboard",detail="Your crew is waiting at the landing pad."))
    var panel,toast=0ul
    let result=run_gl_demo("dasrmlui - Orbital / animations","logs/animations.png",smoke,
        $(delta:float) { if (smoke) { rui_test_advance_time(double(0.08)) } },
        $() { orbital_menu(model) }) $(frame:int) {
        if (frame==0) { panel=ui_find("briefing"); toast=ui_find("toast",0); rui_test_click(ui_find("toggle_panel")) }
        elif (frame==1) { verify(rui_alive(panel) && panel_unmounts==0); rui_test_click(ui_find("toggle_panel")) }
        elif (frame==2) { verify(ui_find("briefing")==panel && panel_mounts==1,"reopen while exiting preserves component"); rui_test_event(ui_find("callsign"),"change","KESTREL / TEST"); rui_test_click(ui_find("dismiss",0)) }
        elif (frame==3) { verify(rui_alive(toast),"notification retained during exit"); rui_test_click(ui_find("launch_button")) }
        elif (frame==4) { verify(model.launching && model.launches==1) }
        elif (frame==7) { verify(!rui_alive(toast),"notification exit completed"); rui_test_click(ui_find("ambient")) }
        elif (frame==8) { verify(!model.ambient && rui_animation_status(ui_find("vehicle"))==0) }
        elif (frame==11) {
            verify(model.completed==1 && !model.launching && ui_find("toast",0)!=toast && ui_find("toast",0)!=0ul)
            verify(rui_get_value(ui_find("callsign"))=="KESTREL / TEST" && panel_mounts==1)
            print("PASS: GL transforms, panel exit cancellation, local state, notification unmount, launch completion, stop ambient\n")
        }
    }
    if (smoke) { verify(panel_unmounts==1,"reset cleans retained panel") }
    return result
}
