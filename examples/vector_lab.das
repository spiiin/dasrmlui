options gen2
options persistent_heap
options gc
options stack = 65536
require examples/gl_demo_host
require strings
require math

struct Atelier { alternate,crop,blue,large:bool; visible:bool=true }
def badge(blue:bool):string {
    return "<rect x='20' y='20' width='200' height='160' rx='32' fill='{blue ? "#9abbd3" : "#edb4ab"}'/><path d='M74 112 L105 140 L170 77' fill='none' stroke='#fff8ed' stroke-width='15' stroke-linecap='round' stroke-linejoin='round'/><circle cx='192' cy='33' r='24' fill='#ffe1a0'/>"
}
[ui_style]
def atelier_style() {
    rule("body") { background(rgb(246,241,234)) }
    rule(part("page")) { background(rgb(246,241,234)); color(rgb(69,54,85)); padding(px(38)); width(pct(100)); height(px(820)); property("box-sizing","border-box") }
    rule(part("eyebrow")) { font_size(px(12)); letter_spacing(px(3)); color(rgb(149,108,120)); margin_top(px(18)); margin_bottom(px(14)) }
    rule(part("heading")) { font_size(px(49)); margin_bottom(px(10)) }
    rule(part("intro")) { font_size(px(17)); color(rgb(127,113,137)); margin_bottom(px(30)) }
    rule(part("cards")) { property("align-items","stretch") }
    rule(part("card")) { width(px(330)); padding(px(19)); property("box-sizing","border-box"); margin_right(px(18)); background(rgb(255,251,246)); border(px(1),rgb(223,210,222)); border_radius(px(18)) }
    rule(part("number")) { color(rgb(160,125,144)); font_size(px(12)); margin_bottom(px(12)) }
    rule(part("title")) { font_size(px(24)); margin_bottom(px(6)) }
    rule(part("description")) { font_size(px(14)); color(rgb(135,119,141)); height(px(48)); property("line-height","21px") }
    rule(part("stage")) { width(px(290)); height(px(245)); position("relative"); background(rgb(241,231,238)); border_radius(px(12)); margin_bottom(px(16)) }
    rule(part("art")) { width(pct(100)); height(pct(100)) }
    rule(part("art_size")) { position("absolute"); left(px(25)); top(px(22)) }
    rule(part("controls")) { property("flex-wrap","wrap"); height(px(72)); property("align-content","flex-start") }
    rule(part("controls")+" button") { padding(px(9)); margin_right(px(8)); margin_bottom(px(8)); background(rgb(229,219,237)); color(rgb(79,60,97)); border_radius(px(7)); nav(UiNav.Horizontal) }
    rule(part("controls")+" button:hover") { background(rgb(216,199,229)) }
    rule(part("controls")+" button:focus-visible") { background(rgb(199,178,217)) }
    rule(part("note")) { color(rgb(152,130,151)); font_size(px(12)); property("line-height","19px") }
    rule(part("footer")) { margin_top(px(20)); width(px(1026)); height(px(58)); flex_shrink(0.); background(rgb(231,223,237)); border_radius(px(14)); position("relative") }
    rule(part("seal")) { width(px(64)); height(px(42)); flex_shrink(0.); margin_left(px(18)); svg_decorator("examples/assets/vector_orbit.svg",true) }
    rule(part("footer_text")) { margin_left(px(18)); font_size(px(15)); color(rgb(108,86,126)) }
}
[ui_component]
def atelier(var model:Atelier) {
    use_style(@@atelier_style)
    column("page") {
        width(px(ui_width())); height(px(max(820.,ui_height())))
        text("eyebrow","RMLUI   /   VECTOR COLLECTION   /   016")
        text("heading","Small shapes, endless motion.")
        text("intro","SVG artwork, inline marks and native Lottie. One scene, three ways to draw.")
        row("cards") {
            column("card") {
                text("number","01  /  FILE SVG"); text("title","Petal study")
                text("description","Gradients and paths, rasterized again\nwhen the display size changes.")
                box("stage") { svg_image("art",model.alternate ? "examples/assets/vector_orbit.svg" : "examples/assets/vector_flower.svg",model.crop) }
                row("controls") {
                    button("switch_svg","Swap artwork") { on_click() { model.alternate=!model.alternate } }
                    button("crop",model.crop ? "Crop: content" : "Crop: canvas") { on_click() { model.crop=!model.crop } }
                }
                text("note","LunaSVG  /  gradients + paths\nCrop removes transparent margins.")
            }
            column("card") {
                text("number","02  /  INLINE SVG"); text("title","A little approval")
                text("description","An SVG fragment from daScript.\nOnly its own binding changes.")
                box("stage") { svg_inline("art",badge(model.blue),float2(240.,200.)) }
                row("controls") { button("recolor",model.blue ? "Use rose ink" : "Use blue ink") { on_click() { model.blue=!model.blue } } }
                text("note","Inline XML  /  explicit viewport\nNo separate UI file or parser.")
            }
            column("card") {
                text("number","03  /  LOTTIE JSON"); text("title","Always in orbit")
                text("description","Native looping motion. The component\nstays idle while the picture moves.")
                box("stage") {
                    when($()=>model.visible) {
                        box("art_size") {
                            width(px(model.large ? 240. : 190.)); height(px(model.large ? 240. : 190.))
                            lottie("art",model.alternate ? "examples/assets/vector_pulse.json" : "examples/assets/vector_motion.json")
                        }
                    }
                }
                row("controls") {
                    button("resize",model.large ? "Smaller" : "Larger") { on_click() { model.large=!model.large } }
                    button("visibility",model.visible ? "Remove" : "Mount again") { on_click() { model.visible=!model.visible } }
                }
                text("note","rlottie  /  native automatic loop\nSwap artwork also swaps the animation.")
            }
        }
        row("footer") {
            box("seal") {}
            text("footer_text","SVG can decorate a box, too. This little seal uses svg_decorator().\nVector sources remain sharp when resized; the UI runs entirely in daScript.")
        }
    }
}
[export]
def main(smoke:bool):int {
    var model=Atelier()
    return run_gl_demo("Vector atelier - SVG and Lottie","logs/vector_lab.png",smoke,$(dt:float) {},$() { atelier(model) },$(frame:int) {
        if (frame==0) { verify(rui_warning_count()==0); verify(rui_bounds(ui_find("page")).z==ui_width()); rui_test_click(ui_find("recolor")) }
        elif (frame==1) { verify(model.blue); rui_test_click(ui_find("crop")); rui_test_click(ui_find("resize")) }
        elif (frame==2) { verify(model.crop && model.large); rui_test_click(ui_find("switch_svg")) }
        elif (frame==3) { verify(model.alternate); rui_test_click(ui_find("visibility")) }
        elif (frame==4) { verify(!model.visible); rui_test_click(ui_find("visibility")) }
        elif (frame==5) { verify(model.visible); unsafe { heap_collect(true,false) } }
        elif (frame==6) { ui_clear_stats() }
        elif (frame==7) { verify(ui_stats().binding_updates==0); verify(rui_warning_count()==0) }
        elif (frame==11) { print("PASS: vector atelier sources, crop, inline, resize, remount and idle components\n") }
        rui_test_advance_time(0.2lf)
    })
}
