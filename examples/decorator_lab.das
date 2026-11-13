options gen2
options persistent_heap
options gc
options stack = 65536
require examples/gl_demo_host
require math

struct DecoratorMemory { texture:uint64 }
struct Studio { amount:float=0.64; expanded:bool; third:bool=true; alternate:bool; title:string="Prototype / 024" }
var data:table<uint64;DecoratorMemory>
var created,destroyed,paints:int

def install_ticket() {
    register_decorator("lab-ticket",array<UiDecoratorParam>(
        decorator_color_param("paper",rgb(239,220,173)),
        decorator_color_param("ink",rgb(88,64,45)),
        decorator_length_param("cut",dp(20)),
        decorator_number_param("progress",0.64),
        decorator_string_param("stamp","examples/assets/native_mesh_atlas.png")),@(event:UiDecoratorEvent) {
        let canvas=event.canvas
        if (event.kind==UiDecoratorKind.Create) { data[canvas]=DecoratorMemory(); created+=1 }
        elif (event.kind==UiDecoratorKind.Destroy) { data |> erase(canvas); destroyed+=1 }
        else {
            let paper=decorator_color(canvas,"paper"); let ink=decorator_color(canvas,"ink")
            let w=event.size.x; let h=event.size.y
            let cut=clamp(decorator_length(canvas,"cut",min(w,h)),0.,min(w,h)*0.4)
            let progress=clamp(decorator_number(canvas,"progress"),0.,1.)
            var inscope points=array<float2>(float2(cut,0.),float2(w-cut,0.),float2(w,cut),float2(w,h-cut),
                float2(w-cut,h),float2(cut,h),float2(0.,h-cut),float2(0.,cut))
            var inscope mesh:UiNativeMesh
            mesh_vertex(mesh,float2(w*0.5,h*0.5),paper.ink,float2(0.),paper.alpha)
            for (point in points) { mesh_vertex(mesh,point,paper.ink,float2(0.),paper.alpha) }
            for (i in range(8)) { mesh_triangle(mesh,0,i+1,(i+1)%8+1) }
            native_mesh(canvas,mesh)
            for (i in range(8)) { native_line(canvas,points[i],points[(i+1)%8],2.*event.dpi,ink.ink,ink.alpha) }
            if (h>90.) {
                for (i in range(int((w-56.)/10.))) {
                    native_rect(canvas,float4(28.+float(i)*10.,h-44.,4.,1.),ink.ink,0.35)
                }
                native_rect(canvas,float4(28.,h-26.,max(0.,w-56.)*progress,5.),ink.ink,0.85)
                let source=decorator_string(canvas,"stamp")
                if (source!="none") {
                    if (data[canvas].texture==0ul) { data[canvas].texture=native_texture_load(canvas,source); verify(data[canvas].texture!=0ul) }
                    native_image(canvas,data[canvas].texture,float4(w-58.,22.,28.,28.),float4(0.5,0.,1.,1.),0.85)
                }
            }
            paints+=1
        }
    })
}
[ui_style]
def studio_style() {
    rule("body") { background(rgb(240,235,223)); color(rgb(57,48,45)); font_size(px(16)) }
    rule(part("page")) { padding(px(44)); property("box-sizing","border-box") }
    rule(part("kicker")) { color(rgb(143,87,63)); font_size(px(13)); margin_bottom(px(16)) }
    rule(part("heading")) { font_size(px(46)); margin_bottom(px(10)) }
    rule(part("intro")) { color(rgb(116,102,91)); margin_bottom(px(32)); font_size(px(18)) }
    rule(part("cards")) { margin_bottom(px(28)); property("align-items","flex-start") }
    rule(part("ticket")) {
        width(px(268)); height(px(208)); padding(px(28)); property("margin-right","20px"); property("box-sizing","border-box")
        custom_decorator("lab-ticket")
    }
    rule(part("ticket2")) {
        width(px(300)); height(px(208)); padding(px(28)); property("margin-right","20px"); property("box-sizing","border-box")
        custom_decorator("lab-ticket",array<UiDecoratorArg>(decorator_arg("paper",rgb(203,216,205)),decorator_arg("ink",rgb(57,93,81)),decorator_arg("cut",pct(13)),decorator_arg("progress",0.38)))
    }
    rule(part("ticket3")) {
        width(px(300)); height(px(208)); padding(px(28)); property("box-sizing","border-box")
        custom_decorator("lab-ticket",array<UiDecoratorArg>(decorator_arg("paper",rgb(220,207,226)),decorator_arg("ink",rgb(97,67,112)),decorator_arg("cut",dp(7)),decorator_arg("progress",0.88)))
    }
    rule(part("serial")) { font_size(px(12)); margin_bottom(px(24)); color(rgb(115,100,85)) }
    rule(part("name")) { font_size(px(26)); margin_bottom(px(10)) }
    rule(part("detail")) { font_size(px(14)); color(rgb(111,100,88)); property("line-height","22px") }
    rule(part("caption")) { font_size(px(13)); color(rgb(135,113,95)); margin_bottom(px(12)) }
    rule(part("editor")) { width(px(620)); height(px(48)); padding_x(px(18)); padding_y(px(12)); property("box-sizing","border-box"); color(rgb(57,48,45)); font_size(px(18)); margin_bottom(px(24))
        custom_decorator("lab-ticket",array<UiDecoratorArg>(decorator_arg("paper",rgb(253,248,234)),decorator_arg("cut",dp(8))))
    }
    rule(part("controls")) { property("align-items","center"); margin_bottom(px(22)) }
    rule(part("progress")) { width(px(230)); height(px(24)); property("margin-right","20px") }
    rule(part("progress")+" slidertrack") { height(px(4)); margin_top(px(8)); background(rgb(193,176,147)) }
    rule(part("progress")+" sliderbar") { width(px(15)); height(px(22)); background(rgb(143,87,63)) }
    rule(part("controls")+" button") { padding(px(13)); property("margin-right","12px"); color(rgb(77,60,48)); font_size(px(14))
        custom_decorator("lab-ticket",array<UiDecoratorArg>(decorator_arg("paper",rgb(230,215,188)),decorator_arg("cut",dp(7))))
    }
    rule(part("controls")+" button:hover") { custom_decorator("lab-ticket",array<UiDecoratorArg>(decorator_arg("paper",rgb(215,182,139)),decorator_arg("cut",dp(12)))) }
    rule(part("footer")) { width(px(940)); color(rgb(135,120,105)); font_size(px(14)); property("line-height","23px") }
}
[ui_component]
def studio(var model:Studio) {
    use_style(@@studio_style)
    column("page") {
        width(px(ui_width())); height(px(max(820.,ui_height())))
        text("kicker","SCRIPTED SURFACES   /   DECORATOR STUDIO   /   019")
        text("heading","Edges, made in script.")
        text("intro","One native decorator. Ordinary cards, buttons and an editable field.")
        row("cards") {
            column("ticket") {
                width(px(model.expanded ? 340 : 268))
                custom_decorator("lab-ticket",array<UiDecoratorArg>(decorator_arg("progress",model.amount),decorator_arg("paper",model.alternate ? rgb(245,197,173) : rgb(239,220,173))))
                text("serial","01 / LIVE PARAMETERS"); text("name","{int(model.amount*100.)}% complete")
                text("detail","Move the slider. Only this card gets new decorator data.")
            }
            column("ticket2") {
                text("serial","02 / RELATIVE LENGTHS"); text("name","Cut from paper")
                text("detail","Corner cut: 13% of the shorter side. The frame follows layout.")
            }
            when($()=>model.third) {
                column("ticket3") {
                    text("serial","03 / OWNED RESOURCES"); text("name","Borrowed ink")
                    text("detail","A PNG stamp and cached geometry. Remove to release both.")
                }
            }
        }
        text("caption","THE SAME DECORATOR ON A NATIVE INPUT")
        text_input("editor") { bind_value(model.title) $(value:string) { model.title=value } }
        row("controls") {
            range_input("progress") { bind_range(model.amount,0.,1.,0.01) $(value:float) { model.amount=value } }
            button("resize",model.expanded ? "Compact card" : "Widen card") { on_click() { model.expanded=!model.expanded } }
            button("palette","Change paper") { on_click() { model.alternate=!model.alternate } }
            button("third",model.third ? "Remove card 03" : "Mount card 03") { on_click() { model.third=!model.third } }
            button("gc","Collect heap") { on_click() { unsafe { heap_collect(true,false) } } }
        }
        text("footer","The RCSS cascade chooses parameters; daScript builds the decoration. Hover a button to change its frame. Idle frames reuse native geometry without calling Paint.")
    }
}
[export]
def main(smoke:bool):int {
    var initial=Studio(); var saved=0; var first:uint64
    var state=ui_state(initial)
    let result=run_gl_demo("Decorator studio - Edgecraft","logs/decorator_lab.png",smoke,$(dt:float) {
        if (!decorator_registered("lab-ticket")) { install_ticket() }
    },$() { ui_frame(state) $(model:Studio) { studio(model) } },$(frame:int) {
        ui_edit(state) $(var model:Studio) {
            if (frame==0) { first=ui_find("ticket"); saved=paints; verify(!rui_is_native(first)); ui_clear_stats() }
            elif (frame==1) { verify(paints==saved && ui_stats().binding_updates==0); rui_test_event(ui_find("progress"),"change","0.8") }
            elif (frame==2) { verify(model.amount==0.8 && paints>saved && ui_find("ticket")==first); rui_test_click(ui_find("resize")) }
            elif (frame==3) { verify(model.expanded); rui_test_click(ui_find("palette")) }
            elif (frame==4) { verify(model.alternate); rui_test_click(ui_find("gc")); rui_test_click(ui_find("third")) }
            elif (frame==5) { verify(!model.third && native_texture_resources()==2); rui_test_click(ui_find("third")) }
            elif (frame==6) { verify(native_texture_resources()==3); rui_test_event(ui_find("editor"),"change","Edited / 025") }
            elif (frame==7) { verify(model.title=="Edited / 025"); saved=paints }
            elif (frame==11) { verify(paints==saved && rui_warning_count()==0); print("PASS: decorator studio, ordinary elements, params, resize, input, remount and GC\n") }
        }
    })
    if (smoke) { verify(created==destroyed && empty(data) && native_texture_resources()==0 && decorator_handler_count()==0) }
    return result
}
