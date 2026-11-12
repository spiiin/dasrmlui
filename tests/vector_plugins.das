options gen2
options persistent_heap
options gc
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Model { svg_version,lottie_version,ink:int; crop:bool; visible:bool=true; viewport:float2=float2(100.,100.) }
var svg_reads,lottie_reads,inline_reads:int
def svg_source(version:int):string { svg_reads+=1; return version==0 ? "examples/assets/vector_probe.svg" : "examples/assets/vector_probe_alt.svg" }
def lottie_source(version:int):string { lottie_reads+=1; return version==0 ? "examples/assets/vector_probe.json" : "examples/assets/vector_probe_alt.json" }
def fragment(ink:int):string { inline_reads+=1; return "<rect width='100' height='100' fill='{ink==0 ? "#e8505b" : "#18aa88"}'/>" }
[ui_style]
def vectors() {
    rule(part("inline")) { width(px(100)); height(px(100)); image_color(rgb(255,255,255)) }
    rule(part("decorated")) { width(px(80)); height(px(80)); svg_decorator("examples/assets/vector_probe.svg",true) }
}
[ui_template]
def frame() {
    window_frame("frame") {
        width(px(400)); height(px(200))
        svg_image("file","examples/assets/vector_probe.svg",true)
        svg_inline("inline","<circle cx='10' cy='10' r='8' fill='red'/>",float2(20.,20.))
        lottie("motion","examples/assets/vector_probe.json")
        slot("body")
    }
}
[ui_component]
def screen(var model:Model) {
    use_style(@@vectors)
    svg_image("file",svg_source(model.svg_version),model.crop)
    svg_inline("inline",fragment(model.ink),model.viewport)
    when($()=>model.visible) { lottie("motion",lottie_source(model.lottie_version)) }
    box("decorated") {}
}
[export]
def main(smoke:bool):int {
    var model=Model()
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Vector plugins",800,600,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,800,600)); verify(rui_default_font())
        rui_test_display_scale(1.); rui_test_advance_time(0.0lf)
        ui_frame() { screen(model) }
        let svg=ui_find("file"); let inline_svg=ui_find("inline"); let anim=ui_find("motion")
        verify(rui_vector_kind(svg)==1 && rui_vector_kind(inline_svg)==1 && rui_vector_kind(anim)==2,"official native factories")
        verify(rui_intrinsic_size(svg)==float2(100.,100.) && rui_intrinsic_size(anim)==float2(200.,100.))
        verify(find(rui_inner_markup(inline_svg),"#e8505b")>=0)
        verify(svg_reads==1 && lottie_reads==1 && inline_reads==1)
        ui_clear_stats(); rui_test_advance_time(0.5lf); ui_frame() { screen(model) }; rui_render()
        verify(ui_stats().binding_updates==0 && svg_reads==1 && lottie_reads==1 && inline_reads==1,"native animation requires no component updates")
        model.svg_version=1; ui_frame() { screen(model) }
        verify(ui_find("file")==svg && rui_intrinsic_size(svg)==float2(100.,50.))
        verify(svg_reads==2 && lottie_reads==1 && inline_reads==1,"source dependencies are independent")
        model.ink=1; ui_frame() { screen(model) }
        verify(inline_reads==2 && svg_reads==2 && lottie_reads==1)
        verify(ui_find("inline")==inline_svg && find(rui_inner_markup(inline_svg),"#18aa88")>=0)
        model.viewport=float2(120.,80.); ui_frame() { screen(model) }
        verify(rui_intrinsic_size(inline_svg)==float2(120.,80.))
        model.lottie_version=1; ui_frame() { screen(model) }
        verify(ui_find("motion")==anim && rui_intrinsic_size(anim)==float2(100.,100.))
        model.crop=true; ui_frame() { screen(model) }; verify(rui_has_attr(svg,"crop-to-content"))
        model.crop=false; ui_frame() { screen(model) }; verify(!rui_has_attr(svg,"crop-to-content"))
        set_ui_scale(2.); ui_frame() { screen(model) }
        verify(rui_intrinsic_size(svg)==float2(200.,100.) && rui_intrinsic_size(anim)==float2(200.,200.),"native intrinsic dimensions respect density")
        set_ui_scale(1.)
        let doc=open_template(@@frame,"Vectors",float2(0.,0.))
        rui_update()
        verify(rui_vector_kind(rui_document_element(doc,"file"))==1)
        verify(rui_has_attr(rui_document_element(doc,"file"),"crop-to-content"))
        verify(rui_intrinsic_size(rui_document_element(doc,"inline"))==float2(20.,20.))
        verify(rui_vector_kind(rui_document_element(doc,"motion"))==2)
        close_document(doc)
        model.visible=false; ui_frame() { screen(model) }; verify(!rui_alive(anim))
        unsafe { heap_collect(true,false) }
        model.visible=true; ui_frame() { screen(model) }; verify(rui_vector_kind(ui_find("motion"))==2)
        rui_render(); verify(rui_warning_count()==0,"valid vector sources and decorator must load without warnings")
        // The same native FileInterface also supports all-in-daScript resources.
        rui_resource("memory/vector.svg","<svg xmlns='http://www.w3.org/2000/svg' width='64' height='32'><rect width='64' height='32' fill='#18aa88'/></svg>")
        rui_resource("memory/vector.json","\{\"v\":\"5.7.4\",\"fr\":30,\"ip\":0,\"op\":60,\"w\":64,\"h\":32,\"layers\":[]\}")
        rui_attr(svg,"src","memory/vector.svg"); rui_attr(ui_find("motion"),"src","memory/vector.json")
        rui_update(); rui_render()
        verify(rui_intrinsic_size(svg)==float2(64.,32.) && rui_intrinsic_size(ui_find("motion"))==float2(64.,32.))
        verify(rui_warning_count()==0,"SVG and Lottie can load in-memory resources")
        rui_resource("memory/broken.svg","not SVG"); rui_resource("memory/broken.json","not JSON")
        rui_attr(svg,"src","memory/broken.svg"); rui_attr(ui_find("motion"),"src","memory/broken.json")
        rui_update(); rui_render()
        verify(rui_warning_count()>0,"malformed resources are reported without a crash")
        // Native failures leave a safe empty element; a new source recovers it.
        let warnings=rui_warning_count()
        rui_attr(svg,"src","examples/assets/missing-vector.svg")
        rui_attr(ui_find("motion"),"src","examples/assets/missing-vector.json")
        rui_update(); rui_render()
        verify(rui_warning_count()>warnings)
        rui_attr(svg,"src","examples/assets/vector_probe.svg")
        rui_attr(ui_find("motion"),"src","examples/assets/vector_probe.json")
        rui_update(); rui_render()
        verify(rui_intrinsic_size(svg)==float2(100.,100.) && rui_intrinsic_size(ui_find("motion"))==float2(200.,100.))
        ui_reset(); rui_shutdown()
        verify(rui_init(window,renderer,800,600)); verify(rui_default_font())
        ui_frame() { screen(model) }; rui_render()
        verify(rui_vector_kind(ui_find("file"))==1 && rui_vector_kind(ui_find("motion"))==2,"plugins re-register after restart")
        ui_reset(); rui_shutdown()
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    print("PASS: native SVG/Lottie, per-binding sources, inline, template, crop, DPI, lifecycle and recovery\n")
    return 0
}
