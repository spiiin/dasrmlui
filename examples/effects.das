options gen2
options persistent_heap
options gc
options stack = 65536
require examples/gl_demo_host
require examples/showcase_style
require strings
require math
struct FilterControl { id:int; title:string; minimum,maximum,step:float }
struct Effects { values:array<float>; tab:int; angle:float=0.0; scale:float=1.0; glow:float=3.0; blur:float=4.0 }
var controls:array<FilterControl>
def filter_string(values:array<float>):string {
    return "opacity({values[0]}) sepia({values[1]}) grayscale({values[2]}) saturate({values[3]}) brightness({values[4]}) contrast({values[5]}) hue-rotate({values[6]}deg) invert({values[7]}) blur({values[8]}px) drop-shadow(#e34f96aa {values[9]}px 8px 5px)"
}
[ui_style]
def effects_style() {
    expedition_sprites(); showcase_controls()
    rule(part("shell")) { padding(px(28)); background(rgb(159,181,181)); color(rgb(24,45,44)); min_height(px(764)) }
    rule(part("heading")) { font_size(px(32)); color(rgb(248,255,224)); property("font-effect","shadow(1px 2px #284d37)"); margin_bottom(px(8)) }
    rule(part("header")) { padding(px(20)); background(rgb(83,130,91)); property("border-radius","22px 5px"); margin_bottom(px(18)) }
    rule(part("muted")) { font_size(px(14)); color(rgb(45,73,68)); margin_bottom(px(10)) }
    rule(part("canvas")) { width(px(670)); height(px(620)); position("relative") }
    rule(part("stack")) { width(px(310)); padding(px(14)); margin_left(px(80)); margin_top(px(18)); margin_bottom(px(85)); background(rgb(252,247,224)); border(px(2),rgb(255,249,230)); property("border-radius","30px 8px"); property("box-shadow","#ee399f 24px 24px 0px 0px, #f57cc1 48px 48px 0px 0px, #cfb1bc 72px 72px 0px 0px, #fffacb 0px 0px 12px 5px inset") }
    rule(part("inset")) { width(px(310)); padding(px(14)); margin_left(px(80)); margin_bottom(px(22)); background(rgb(255,220,230)); border(px(2),rgb(255,255,255)); property("border-radius","28px 8px"); property("box-shadow","#9144ff 10px 4px 9px 3px inset") }
    rule(part("icon")) { width(px(54)); height(px(54)); margin_right(px(12)) }
    rule(part("shader")) { width(px(540)); height(px(155)); margin_left(px(28)); property("decorator","shader(\"creation\")"); border_radius(px(28)); property("overflow","hidden"); property("box-shadow","#f66a 10px 8px 18px 0px") }
    rule(part("glass")) { position("absolute"); right(px(28)); top(px(115)); width(px(350)); padding(px(22)); property("background-color","#f8fcf6d9"); property("backdrop-filter","blur(8px)"); border(px(1),rgb(81,107,100)); border_radius(px(18)); z_index(5) }
    rule(part("shell")+" tab") { color(rgb(56,79,70)); margin_right(px(6)); padding(px(8)) }
    rule(part("shell")+" tab:selected") { color(rgb(24,123,139)); border_bottom(px(3),rgb(24,123,139)) }
    rule(part("control")) { height(px(38)); property("align-items","center") }
    rule(part("control_name")) { width(px(98)); font_size(px(14)) }
    rule(part("control_value")) { width(px(48)); property("text-align","right"); font_size(px(13)) }
    rule(part("shell")+" input.range") { width(px(190)); margin_bottom(px(0)) }
    rule(part("shell")+" input.range slidertrack") { background(rgb(224,228,228)) }
    rule(part("shell")+" input.range sliderbar") { background(rgb(65,103,103)) }
    rule(part("type_card")) { margin_top(px(18)); padding(px(20)); background(rgb(22,36,40)); border_radius(px(12)); color(rgb(235,255,251)) }
    rule(part("type_title")) { font_size(px(32)); margin_bottom(px(12)) }
}
[ui_component]
def filter_control(var model:Effects; control:FilterControl) {
    use_style(@@effects_style)
    row("control") {
        text("control_name",control.title)
        range_input("filter") { bind_range(model.values[control.id],control.minimum,control.maximum,control.step) $(value:float) { model.values[control.id]=value } }
        text("control_value","{model.values[control.id]:.1f}")
    }
}
[ui_component]
def effects(var model:Effects) {
    use_style(@@effects_style)
    column("shell") {
        width(px(max(750.0,ui_width()-56.0)))
        column("header") { text("heading","Effects atelier"); text("muted","Live filters, layered shadows, glass, transforms and glowing type") }
        column("canvas") {
            box("filtered") {
                property("filter",filter_string(model.values))
                property("transform","rotate({model.angle}deg) scale({model.scale})")
                property("transform-origin","50% 0%")
                row("stack") { sprite_image("icon","scout"); text("message","Hello, do you feel the funk?") }
                row("inset") { sprite_image("icon","probe"); text("message","Inner glow / rounded corners") }
                box("shader") {}
            }
            column("type_card") {
                width(px(500))
                box() { property("font-effect","glow({model.glow}px {model.blur}px 0px 0px #58e8ff)"); text("type_title","AURORA SIGNAL") }
                box() { property("font-effect","outline(1px #f5a5eb)"); text("type_title","OUTLINE / 01") }
                box() { property("font-effect","shadow(3px 3px #f68c7c)"); text("plain","Shadow on live text, not an image") }
            }
        }
        column("glass") {
            tabset("tabs") {
                tab_headers() { tab_label("filters_tab","Filters"); tab_label("transform_tab","Transform"); tab_label("type_tab","Type") }
                tab_panels() {
                    tab_panel("filters") { controls |> each_keyed($(c:FilterControl)=>c.id) $(c:FilterControl) { filter_control(model,c) } }
                    tab_panel("transforms") {
                        text("muted","Rotation / {model.angle:.0f} degrees")
                        range_input("angle") { bind_range(model.angle,-20.0,20.0,1.0) $(v:float) { model.angle=v } }
                        text("muted","Scale / {model.scale:.2f}")
                        range_input("scale") { bind_range(model.scale,0.6,1.2,0.05) $(v:float) { model.scale=v } }
                        text("muted","The OpenGL renderer transforms geometry, clipping and hit testing together.")
                    }
                    tab_panel("typography") {
                        text("muted","Glow outline / {model.glow:.0f}px")
                        range_input("glow") { bind_range(model.glow,0.0,8.0,1.0) $(v:float) { model.glow=v } }
                        text("muted","Glow blur / {model.blur:.0f}px")
                        range_input("glow_blur") { bind_range(model.blur,0.0,12.0,1.0) $(v:float) { model.blur=v } }
                        text("muted","Compare glow, outline and shadow below the shader preview.")
                    }
                }
                bind_tab(model.tab) $(v:int) { model.tab=v }
            }
            button("reset","Reset effects") { margin_top(px(16)); on_click() { model.values <- array<float>(1.,0.,0.,1.,1.,1.,0.,0.,0.,0.); model.angle=0.; model.scale=1.; model.glow=3.; model.blur=4. } }
            text("muted","Animated shader: Creation, by Danilo Guanabara / RmlUi GL3 sample.")
        }
    }
}
[export]
def main(smoke:bool):int {
    var initial=Effects()
    initial.values <- array<float>(1.,0.,0.,1.34,1.,1.32,0.,0.,0.,8.)
    controls |> push <| FilterControl(id=0,title="Opacity",maximum=1.,step=.05)
    controls |> push <| FilterControl(id=1,title="Sepia",maximum=1.,step=.05)
    controls |> push <| FilterControl(id=2,title="Grayscale",maximum=1.,step=.05)
    controls |> push <| FilterControl(id=3,title="Saturate",maximum=3.,step=.05)
    controls |> push <| FilterControl(id=4,title="Brightness",minimum=.2,maximum=2.,step=.05)
    controls |> push <| FilterControl(id=5,title="Contrast",minimum=.2,maximum=2.,step=.05)
    controls |> push <| FilterControl(id=6,title="Hue",maximum=360.,step=1.)
    controls |> push <| FilterControl(id=7,title="Invert",maximum=1.,step=.05)
    controls |> push <| FilterControl(id=8,title="Blur",maximum=8.,step=.5)
    controls |> push <| FilterControl(id=9,title="Shadow",maximum=24.,step=1.)
    var state=ui_state(initial)
    return run_gl_demo("dasrmlui - Effects atelier","logs/effects.png",smoke,$(dt:float) {},$() { ui_frame(state) $(model:Effects) { effects(model) } }) $(frame:int) {
        ui_edit(state) $(var model:Effects) {
            if (frame==0) { rui_test_click(ui_find("filter",2)) }
            elif (frame==1) { verify(model.values[2]>0.0); rui_test_click(ui_find("transform_tab")) }
            elif (frame==2) { verify(model.tab==1); model.angle=12.; model.scale=.85 }
            elif (frame==4) { rui_test_click(ui_find("type_tab")) }
            elif (frame==5) { verify(model.tab==2); model.glow=6.; model.blur=8. }
            elif (frame==8) { rui_test_click(ui_find("reset")) }
            elif (frame==9) { verify(model.angle==0. && model.scale==1. && model.values[2]==0.) }
        }
    }
}
