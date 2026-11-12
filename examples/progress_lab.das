options gen2
options persistent_heap
options gc
options stack = 65536
require examples/gl_demo_host
require examples/showcase_style
require math
struct PathPoint { id:int; x,y,distance:float }
struct Journey { progress:float; playing:bool }
var path_points:array<PathPoint>
var path_length:float
def segment_fill(point:PathPoint; progress:float):float {
    if (point.id==0) { return progress>0. ? 1. : 0. }
    let previous=path_points[point.id-1].distance
    return clamp((progress*path_length-previous)/(point.distance-previous),0.,1.)
}
def sample_route() {
    clear(path_points); path_length=0.
    var previous=float2(0.)
    for (i in range(161)) {
        let t=float(i)/160.
        let point=float2(38.+660.*t,160.+95.*sin(t*6.2831853))
        if (i>0) { let delta=point-previous; path_length+=sqrt(delta.x*delta.x+delta.y*delta.y) }
        path_points |> push <| PathPoint(id=i,x=point.x,y=point.y,distance=path_length)
        previous=point
    }
}
def route_position(progress:float):float2 {
    let distance=clamp(progress,0.,1.)*path_length
    for (i in range(1,length(path_points))) {
        let b=path_points[i]; let a=path_points[i-1]
        if (distance<=b.distance) {
            let t=(distance-a.distance)/(b.distance-a.distance)
            return float2(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t)
        }
    }
    let last=path_points[length(path_points)-1]
    return float2(last.x,last.y)
}
[ui_style]
def journey_style() {
    expedition_sprites(); showcase_controls()
    rule(part("shell")) { padding(px(30)); background(rgb(16,16,39)); color(rgb(237,229,255)); property("min-height","760px") }
    rule(part("heading")) { font_size(px(38)); margin_bottom(px(12)) }
    rule(part("muted")) { color(rgb(158,149,193)); margin_bottom(px(20)) }
    rule(part("map")) { width(px(740)); height(px(340)); property("position","relative"); background(rgb(28,27,57)); property("border-radius","18px"); property("margin-right","20px") }
    rule(part("point")) { property("position","absolute"); width(px(9)); height(px(9)); property("border-radius","5px"); background(rgb(68,59,105)) }
    rule(part("light")) { width(px(9)); height(px(9)); property("border-radius","5px"); background(rgb(178,148,255)); property("box-shadow","#9c6fff 0px 0px 6px 1px") }
    rule(part("craft")) { property("position","absolute"); width(px(80)); height(px(80)); property("pointer-events","none") }
    rule(part("radial_card")) { width(px(280)); padding(px(20)); background(rgb(38,30,67)); property("border-radius","18px") }
    rule(part("shell")+" "+part("radial")) { width(px(250)); height(px(250)); property("fill-image",sprite_name("probe")); property("background-color","#201c38"); property("border-radius","125px") }
    rule(part("shell")+" "+part("radial")+" fill") { property("background-color","transparent") }
    rule(part("controls")) { margin_top(px(24)); padding(px(24)); width(px(1040)); background(rgb(28,27,57)); property("border-radius","12px") }
    rule(part("percentage")) { font_size(px(42)); color(rgb(190,162,255)); margin_bottom(px(12)) }
}
[ui_component]
def journey(var model:Journey) {
    use_style(@@journey_style)
    column("shell") {
        width(px(ui_width()-60.))
        text("heading","Follow the signal")
        text("muted","A curved route filled by travelled distance, with a radial sprite reveal alongside it.")
        row() {
            column() {
                box("map") {
                    path_points |> each_keyed($(p:PathPoint)=>p.id) $(p:PathPoint) {
                        box("point") {
                            property("left","{p.x}px"); property("top","{p.y}px")
                            box("light") {
                                // Fractional final segment. The threshold follows arc length, not x.
                                opacity(segment_fill(p,model.progress))
                            }
                        }
                    }
                    box("traveller") {
                        property("position","absolute")
                        property("left","{route_position(model.progress).x-35.}px")
                        property("top","{route_position(model.progress).y-35.}px")
                        sprite_image("craft","scout")
                    }
                }
                text("muted","PATH / 160 samples, accumulated segment lengths")
            }
            column("radial_card") {
                text("muted","NATIVE RADIAL PROGRESS")
                progress_bar("radial",model.progress,1.,"clockwise")
                text("muted","Transparent sprite / clockwise fill-image")
            }
        }
        column("controls") {
            text("percentage","{model.progress*100.:.0f}%")
            range_input("scrub") { bind_range(model.progress,0.,1.,.01) $(value:float) { model.progress=value; model.playing=false } }
            row() {
                button("play",model.playing ? "Pause journey" : "Play journey") { on_click() { model.playing=!model.playing } }
                button("half","Jump to 50%") { on_click() { model.progress=.5; model.playing=false } }
                button("reset","Reset") { on_click() { model.progress=0.; model.playing=false } }
            }
        }
    }
}
[export]
def main(smoke:bool):int {
    sample_route()
    var model=Journey()
    var first=0ul
    var origin=float4(0.)
    return run_gl_demo("dasrmlui - Follow the signal","logs/progress_lab.png",smoke,$(dt:float) {
        if (model.playing) { model.progress=min(1.,model.progress+(smoke ? .02 : dt*.12)); if (model.progress>=1.) { model.playing=false } }
    },$() { journey(model) }) $(frame:int) {
        if (frame==0) { first=ui_find("point",80); origin=rui_bounds(ui_find("traveller")); verify(rui_local_property(ui_find("light",0),"opacity")=="0"); verify(rui_bounds(ui_find("radial")).w==250.); rui_test_click(ui_find("half")) }
        elif (frame==1) { verify(model.progress==.5 && ui_find("point",80)==first); verify(rui_get_attr(ui_find("radial"),"value")=="0.5"); verify(rui_bounds(ui_find("traveller")).x>origin.x+250.); verify(rui_local_property(ui_find("light",40),"opacity")=="1" && rui_local_property(ui_find("light",120),"opacity")=="0") }
        elif (frame==4) { model.progress=1. }
        elif (frame==7) { verify(rui_get_attr(ui_find("radial"),"value")=="1"); verify(route_position(1.).x==698. && rui_local_property(ui_find("light",160),"opacity")=="1"); rui_test_click(ui_find("reset")) }
        elif (frame==8) { verify(model.progress==0. && rui_bounds(ui_find("traveller")).x==origin.x); rui_test_click(ui_find("play")) }
        elif (frame==10) { verify(model.progress>0. && model.playing); rui_test_click(ui_find("play")) }
        elif (frame==11) { verify(!model.playing); print("PASS: curved path, radial sprite, reset, playback\n") }
    }
}
