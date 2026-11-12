options gen2
options persistent_heap
options gc
options stack = 65536
require examples/gl_demo_host
require math
require strings
require daslib/strings_convert
require daslib/algorithm

struct Trace { phase:float; gain:float=0.65; frequency:float=2.; paused:bool; selected:bool }
struct Channel { id:int; title,description:string; frequency:float }
struct Bench { channels:array<Channel>; gain:float=0.65; paused,large:bool; selected:int=1; third:bool=true }
var traces:table<uint64;Trace>
var creations,releases,paint_count:int
def attr_number(element:uint64; name:string; fallback:float):float {
    let parsed=try_to_float(rui_get_attr(element,name))
    return is_ok(parsed) ? unwrap(parsed) : fallback
}
def draw_trace(event:UiNativeEvent; trace:Trace) {
    let id=event.element; let w=event.size.x; let h=event.size.y
    native_rect(id,float4(0.,0.,w,h),rgb(24,34,32))
    for (i in range(1,12)) { native_line(id,float2(w*float(i)/12.,0.),float2(w*float(i)/12.,h),1.,rgb(44,58,51)) }
    for (i in range(1,4)) { native_line(id,float2(0.,h*float(i)/4.),float2(w,h*float(i)/4.),1.,rgb(44,58,51)) }
    native_line(id,float2(0.,h*0.5),float2(w,h*0.5),1.,rgb(74,83,63))
    let ink=trace.selected ? rgb(255,197,84) : rgb(139,190,144)
    var previous=float2(0.,h*0.5)
    for (i in range(161)) {
        let x=float(i)/160.
        let wave=sin(x*trace.frequency*6.283185+trace.phase*2.)+0.22*sin(x*trace.frequency*18.84955-trace.phase)
        let point=float2(x*w,h*0.5-wave*h*0.32*trace.gain)
        if (i>0) { native_line(id,previous,point,2.5,ink) }
        previous=point
    }
    let cursor=w*0.72
    native_line(id,float2(cursor,0.),float2(cursor,h),1.,rgb(188,132,65),0.7)
    native_triangle(id,float2(cursor-5.,2.),float2(cursor+5.,2.),float2(cursor,10.),rgb(255,197,84))
}
def install_waveform() {
    register_native_element("lab-waveform",@(event:UiNativeEvent) {
        let id=event.element
        if (event.kind==UiNativeKind.Create) { traces[id]=Trace(); creations+=1 }
        elif (event.kind==UiNativeKind.Attribute) {
            if (event.name=="gain") { traces[id].gain=attr_number(id,"gain",0.65) }
            elif (event.name=="frequency") { traces[id].frequency=attr_number(id,"frequency",2.) }
            elif (event.name=="paused") { traces[id].paused=rui_get_attr(id,"paused")=="true" }
            elif (event.name=="selected") { traces[id].selected=rui_get_attr(id,"selected")=="true" }
        } elif (event.kind==UiNativeKind.Update) {
            if (!traces[id].paused) { traces[id].phase=float(event.time); native_invalidate(id) }
        } elif (event.kind==UiNativeKind.Paint) { draw_trace(event,traces[id]); paint_count+=1 }
        elif (event.kind==UiNativeKind.Destroy) { traces |> erase(id); releases+=1 }
    },float2(620.,90.),true)
}
[ui_style]
def bench_style() {
    rule(part("page")) { padding(px(38)); property("box-sizing","border-box"); background(rgb(225,225,211)); color(rgb(37,47,42)) }
    rule(part("kicker")) { font_size(px(12)); letter_spacing(px(3)); color(rgb(108,113,94)); margin_top(px(12)); margin_bottom(px(14)) }
    rule(part("heading")) { font_size(px(48)); margin_bottom(px(10)) }
    rule(part("intro")) { color(rgb(108,113,94)); font_size(px(16)); margin_bottom(px(24)) }
    rule(part("workspace")) { property("align-items","flex-start") }
    rule(part("rack")) { width(px(720)); margin_right(px(22)) }
    rule(part("channel")) { padding(px(15)); background(rgb(49,58,51)); color(rgb(226,224,201)); border_radius(px(9)); margin_bottom(px(12)) }
    rule(part("channel_head")) { margin_bottom(px(10)); property("justify-content","space-between") }
    rule(part("channel_name")) { font_size(px(18)) }
    rule(part("channel_info")) { font_size(px(12)); color(rgb(148,163,140)) }
    rule(part("trace")) { width(pct(100)); height(px(90)); property("cursor","pointer"); nav() }
    rule(part("trace")+":focus-visible") { border(px(2),rgb(255,197,84)) }
    rule(part("side")) { width(px(300)); padding(px(22)); property("box-sizing","border-box"); background(rgb(239,238,224)); border_radius(px(9)) }
    rule(part("side_title")) { font_size(px(24)); margin_bottom(px(16)) }
    rule(part("caption")) { font_size(px(12)); color(rgb(119,119,99)); margin_top(px(16)); margin_bottom(px(8)); letter_spacing(px(1)) }
    rule(part("gain")) { width(px(245)); height(px(22)) }
    rule(part("gain")+" slidertrack") { height(px(5)); background(rgb(183,187,163)); margin_top(px(8)) }
    rule(part("gain")+" sliderbar") { width(px(16)); height(px(20)); background(rgb(172,103,39)) }
    rule(part("actions")+" button") { width(px(238)); padding(px(11)); background(rgb(64,80,63)); color(rgb(243,237,211)); border_radius(px(5)); margin_bottom(px(8)); nav(UiNav.Vertical) }
    rule(part("actions")+" button:hover") { background(rgb(92,105,73)) }
    rule(part("actions")+" button:focus-visible") { background(rgb(152,106,49)) }
    rule(part("note")) { color(rgb(121,123,103)); font_size(px(13)); property("line-height","21px"); margin_top(px(15)) }
    rule(part("footer")) { font_size(px(13)); color(rgb(101,109,91)); margin_top(px(12)) }
}
[ui_component]
def channel_view(var model:Bench; channel:Channel) {
    use_style(@@bench_style)
    column("channel") {
        row("channel_head") { text("channel_name","0{channel.id} / {channel.title}"); text("channel_info",channel.description) }
        native_element("trace","lab-waveform") {
            attribute("gain","{model.gain}"); attribute("frequency","{channel.frequency}")
            attribute("paused","{model.paused}"); attribute("selected","{model.selected==channel.id}")
            height(px(model.large ? 115. : 90.))
            on_click() { model.selected=channel.id }
        }
    }
}
[ui_component]
def bench(var model:Bench) {
    use_style(@@bench_style)
    column("page") {
        width(px(ui_width())); height(px(max(820.,ui_height())))
        text("kicker","NATIVE INSTRUMENTS   /   017   /   SCRIPT-DEFINED ELEMENTS")
        text("heading","Signal foundry.")
        text("intro","Three independent traces. Native RmlUi elements, drawn and controlled from daScript.")
        row("workspace") {
            column("rack") {
                model.channels |> each_keyed($(channel:Channel)=>channel.id) $(channel:Channel) {
                    when($()=>channel.id!=3 || model.third) { channel_view(model,channel) }
                }
                text("footer","CLICK A TRACE TO SELECT   /   Native geometry keeps moving while the component is idle.")
            }
            column("side") {
                text("side_title","Control room")
                text("caption","AMPLITUDE / {int(model.gain*100.)}%")
                range_input("gain") { bind_range(model.gain,0.1,1.,0.05) $(value:float) { model.gain=value } }
                text("caption","CHANNEL 0{model.selected} SELECTED")
                column("actions") {
                    button("pause",model.paused ? "Resume acquisition" : "Hold traces") { on_click() { model.paused=!model.paused } }
                    button("reverse","Reverse rack order") { on_click() { reverse(model.channels) } }
                    button("third",model.third ? "Remove channel 03" : "Mount channel 03") { on_click() { model.third=!model.third } }
                    button("resize",model.large ? "Compact traces" : "Expand traces") { on_click() { model.large=!model.large } }
                    button("gc","Collect script heap") { on_click() { unsafe { heap_collect(true,false) } } }
                }
                text("note","Reordering preserves each instrument. Removing a channel releases its native element and script state. Mounting creates a new instance.")
                text("note","Hold stops invalidating the geometry. Idle traces reuse their compiled mesh.")
            }
        }
    }
}
[export]
def main(smoke:bool):int {
    var model=Bench()
    model.channels <- array<Channel>(Channel(id=1,title="Carrier",description="2 Hz / reference",frequency=2.),
        Channel(id=2,title="Harmonic",description="4 Hz / oscillator",frequency=4.),
        Channel(id=3,title="Modulation",description="7 Hz / auxiliary",frequency=7.))
    var first:uint64
    var saved_paints:int
    let result=run_gl_demo("Signal foundry - native elements","logs/native_lab.png",smoke,$(dt:float) {
        if (!native_registered("lab-waveform")) { install_waveform() }
    },$() { bench(model) },$(frame:int) {
        if (frame==0) { first=ui_find("trace",1); verify(creations==3); rui_test_click(ui_find("reverse")) }
        elif (frame==1) { verify(ui_find("trace",1)==first && creations==3 && releases==0); rui_test_click(ui_find("third")) }
        elif (frame==2) { verify(releases==1 && length(traces)==2); rui_test_click(ui_find("third")) }
        elif (frame==3) { verify(creations==4 && length(traces)==3); rui_test_click(ui_find("resize")) }
        elif (frame==4) { verify(rui_native_size(first).y==115.); rui_test_click(ui_find("trace",2)); rui_test_click(ui_find("gc")) }
        elif (frame==5) { verify(model.selected==2); rui_test_event(ui_find("gain"),"change","0.4"); rui_test_click(ui_find("pause")) }
        elif (frame==6) { verify(model.paused && model.gain==0.4); saved_paints=paint_count; ui_clear_stats() }
        elif (frame==7) { verify(paint_count==saved_paints && ui_stats().binding_updates==0,"held native geometry and bindings are cached") }
        elif (frame==8) { rui_test_click(ui_find("pause")) }
        elif (frame==11) { verify(paint_count>saved_paints && rui_warning_count()==0); print("PASS: native instruments, input, keyed reorder, remount, resize, GC and retained geometry\n") }
    })
    if (smoke) { verify(creations==releases && empty(traces) && native_handler_count()==0) }
    return result
}
