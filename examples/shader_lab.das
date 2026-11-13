options gen2
options persistent_heap
options gc
options stack = 65536
require examples/gl_demo_host
require math
require examples/shader_lab_effects

struct Studio { split:float=6.; speed:float=1.; violet:bool; third:bool=true }
[ui_style]
def studio_style() {
    rule("body") { background(rgb(10,14,25)); color(rgb(234,238,255)); font_size(px(16)) }
    rule(part("page")) { padding(px(40)); property("box-sizing","border-box") }
    rule(part("kicker")) { color(rgb(84,221,202)); font_size(px(12)); margin_bottom(px(14)); property("letter-spacing","2px") }
    rule(part("heading")) { font_size(px(48)); margin_bottom(px(10)) }
    rule(part("intro")) { color(rgb(143,154,182)); font_size(px(17)); margin_bottom(px(30)) }
    rule(part("cards")) { property("align-items","flex-start"); margin_bottom(px(28)) }
    rule(with_class("","card")) { width(px(352)); property("margin-right","22px") }
    rule(with_class("","surface")) {
        height(px(306)); width(pct(100)); property("position","relative"); property("border-radius","20px")
        custom_shader("lab-aurora"); property("border","1px #303950")
    }
    rule(part("third")) { property("margin-right","0") }
    rule(part("label")) { font_size(px(12)); color(rgb(116,131,164)); margin_top(px(18)); margin_bottom(px(9)) }
    rule(part("name")) { font_size(px(22)); margin_bottom(px(8)) }
    rule(part("detail")) { font_size(px(14)); color(rgb(143,154,182)); property("line-height","21px") }
    rule(part("overprint")) { property("position","absolute"); property("left","24px"); property("bottom","24px"); font_size(px(26)); color(rgb(233,250,255)) }
    rule(part("glass")) {
        property("position","absolute"); property("left","22px"); property("right","22px"); property("bottom","22px")
        padding(px(20)); property("border","1px #657389"); property("border-radius","12px"); custom_backdrop_filter("lab-glass")
    }
    rule(part("glassTitle")) { font_size(px(22)); margin_bottom(px(8)) }
    rule(part("glassDetail")) { color(rgb(204,215,235)); font_size(px(13)) }
    rule(part("controls")) { padding(px(22)); background(rgb(20,27,43)); property("border-radius","14px"); property("align-items","center"); margin_bottom(px(20)) }
    rule(part("amount")) { width(px(170)); font_size(px(14)); color(rgb(157,175,204)) }
    rule(part("split")) { width(px(220)); height(px(24)); property("margin-right","28px") }
    rule(part("split")+" slidertrack") { height(px(4)); margin_top(px(10)); background(rgb(49,61,82)) }
    rule(part("split")+" sliderbar") { width(px(16)); height(px(24)); background(rgb(84,221,202)); property("border-radius","6px") }
    rule(part("controls")+" button") { padding_y(px(12)); padding_x(px(16)); property("margin-right","12px"); background(rgb(37,48,70)); color(rgb(213,225,247)); property("border-radius","7px") }
    rule(part("controls")+" button:hover") { background(rgb(56,75,101)) }
    rule(part("footer")) { color(rgb(111,127,157)); font_size(px(14)); property("line-height","22px") }
}
[ui_component]
def studio(var model:Studio) {
    use_style(@@studio_style)
    column("page") {
        width(px(ui_width())); height(px(max(820.,ui_height())))
        text("kicker","MATERIAL STUDIES     /     GL3 SHADER LAB     /     020")
        text("heading","Light, bent in real time.")
        text("intro","One procedural surface. Three native RmlUi rendering paths, authored from daScript.")
        row("cards") {
            column("first") {
                class_if("card",true)
                box("original") {
                    class_if("surface",true)
                    custom_shader("lab-aurora",array<UiEffectArg>(effect_arg("speed",model.speed),effect_arg("tint",model.violet ? rgb(154,110,255) : rgb(46,232,210))))
                    text("overprint","01 / Aurora")
                }
                text("label","SHADER  /  GENERATED SURFACE"); text("name","Pure signal")
                text("detail","Animated rings use GPU time. The component stays idle between input changes.")
            }
            column("second") {
                class_if("card",true)
                box("prism") {
                    class_if("surface",true)
                    custom_shader("lab-aurora",array<UiEffectArg>(effect_arg("speed",model.speed),effect_arg("tint",model.violet ? rgb(154,110,255) : rgb(46,232,210))))
                    custom_filter("lab-prism",array<UiEffectArg>(effect_arg("split",dp(model.split))))
                    text("overprint","02 / Chromatic")
                }
                text("label","FILTER  /  ELEMENT + CHILDREN"); text("name","Split spectrum")
                text("detail","RGB channels sample different pixels. The filter also processes the text above.")
            }
            when($()=>model.third) {
                column("third") {
                    class_if("card",true)
                    box("backdrop") {
                        class_if("surface",true)
                        custom_shader("lab-aurora",array<UiEffectArg>(effect_arg("speed",model.speed),effect_arg("tint",model.violet ? rgb(154,110,255) : rgb(46,232,210))))
                        column("glass") { text("glassTitle","03 / Frosted light"); text("glassDetail","Background filtered. Text stays sharp.") }
                    }
                    text("label","BACKDROP  /  CONTENT BEHIND"); text("name","Through the glass")
                    text("detail","A local sampling pass softens and desaturates only the surface behind this panel.")
                }
            }
        }
        row("controls") {
            text("amount","Chromatic shift: {int(model.split)} dp")
            range_input("split") { bind_range(model.split,0.,18.,1.) $(value:float) { model.split=value } }
            button("motion",model.speed==0. ? "Animate" : "Static phase") { on_click() { model.speed=model.speed==0. ? 1. : 0. } }
            button("tint","Change tint") { on_click() { model.violet=!model.violet } }
            button("toggle",model.third ? "Remove glass" : "Mount glass") { on_click() { model.third=!model.third } }
            button("gc","Collect heap") { on_click() { unsafe { heap_collect(true,false) } } }
        }
        text("footer","Three programs are compiled once at registration. Uniforms follow typed RCSS parameters; element instances are released on unmount.\nResize the window or remove and remount the glass card to exercise the native lifecycle.")
    }
}
[export]
def main(smoke:bool):int {
    var initial=Studio(); var saved:int2
    var state=ui_state(initial)
    let result=run_gl_demo("Shader lab - Light studies","logs/shader_lab.png",smoke,$(dt:float) {
        if (!shader_registered("lab-aurora")) { install_effects() }
    },$() { ui_frame(state) $(model:Studio) { studio(model) } },$(frame:int) {
        ui_edit(state) $(var model:Studio) {
            if (frame==0) { saved=gpu_effect_counts(); verify(saved.x==3 && saved.y==5); ui_clear_stats() }
            elif (frame==1) { verify(ui_stats().binding_updates==0 && gpu_effect_counts()==saved); rui_test_event(ui_find("split"),"change","14") }
            elif (frame==2) { verify(model.split==14. && gpu_effect_counts()==saved); rui_test_click(ui_find("tint")) }
            elif (frame==3) { verify(model.violet); rui_test_click(ui_find("motion")); rui_test_click(ui_find("gc")) }
            elif (frame==4) { verify(model.speed==0.); rui_test_click(ui_find("toggle")) }
            elif (frame==5) { verify(!model.third && gpu_effect_counts().y==3); rui_test_click(ui_find("toggle")) }
            elif (frame==6) { verify(model.third && gpu_effect_counts()==saved); ui_clear_stats() }
            elif (frame==11) { verify(ui_stats().binding_updates==0 && gpu_effect_counts()==saved); print("PASS: shader lab, uniforms, filter, backdrop, animation, remount and GC\n") }
        }
    })
    if (smoke) { verify(gpu_effect_counts()==int2(0)) }
    return result
}
