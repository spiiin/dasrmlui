options gen2
options persistent_heap
options gc
options stack = 65536
require examples/gl_demo_host
require shader_dsl_effects

struct Model { amount:float=1.; alpha:float=1.; shown:bool=true; width:float=80. }
var fixture_prefix="gpu"
def install() {
    register_shader("test-solid",%_esc~
vec4 effect(vec2 uv) { return vec4(p_tint.rgb * p_amount, p_tint.a); }
%_esc,(tint = rgb(40,200,100), amount = 1.))
    register_shader("test-edge",%_esc~
vec4 effect(vec2 uv) { return uv.x*u_size.x < p_edge ? vec4(1,0,0,1) : vec4(0,1,0,1); }
%_esc,(edge = dp(4)))
    register_shader("test-clock",%_esc~
vec4 effect(vec2 uv) { return vec4(fract(u_time*0.25),0,0,1); }
%_esc)
    register_filter("test-swap",%_esc~
vec4 effect(vec2 uv) { vec4 c=sample_source(uv); return vec4(c.b,c.g,c.r,c.a); }
%_esc)
    register_filter("test-red",%_esc~
vec4 effect(vec2 uv) { vec4 c=sample_source(uv); c.r *= p_amount; return c; }
%_esc,(amount = 0.5))
    register_filter("test-shift",%_esc~
vec4 effect(vec2 uv) { return sample_source(uv-vec2(4,0)*u_texel); }
%_esc,8.)
}
[ui_style]
def sheet() {
    rule("body") { background(rgb(0,0,0)); width(px(1200)); height(px(820)) }
    rule(with_class("","sample")) { property("position","absolute"); width(px(80)); height(px(60)) }
    rule(part("solid")) { property("left","20px"); property("top","20px"); custom_shader("test-solid"); property("border-radius","10px") }
    rule(part("filtered")) { property("left","120px"); property("top","20px"); background(rgb(40,200,100)); custom_filter("test-swap") }
    rule(part("chain")) { property("left","220px"); property("top","20px"); background(rgb(40,200,100)); custom_filters(array<UiFilterEffect>(filter_effect("test-swap"),filter_effect("test-red"))) }
    rule(part("reverse")) { property("left","320px"); property("top","20px"); background(rgb(40,200,100)); custom_filters(array<UiFilterEffect>(filter_effect("test-red"),filter_effect("test-swap"))) }
    rule(part("behind")) { property("left","420px"); property("top","20px"); background(rgb(40,200,100)) }
    rule(part("glass")) { property("position","absolute"); property("left","10px"); property("top","10px"); width(px(60)); height(px(40)); custom_backdrop_filter("test-swap") }
    rule(part("edge")) { property("left","20px"); property("top","110px"); custom_shader("test-edge") }
    rule(part("percent")) { property("left","120px"); property("top","110px"); custom_shader("test-edge",(edge = pct(25))) }
    rule(part("clock")) { property("left","220px"); property("top","110px"); custom_shader("test-clock") }
    rule(part("builtin")) { property("left","320px"); property("top","110px"); background(rgb(40,200,100)); property("filter","test-swap() opacity(0.5)") }
    rule(part("shift")) { property("left","420px"); property("top","110px"); background(rgb(40,200,100)); custom_filter("test-shift") }
    rule(part("plain")) { property("left","520px"); property("top","20px"); background(rgb(40,200,100)) }
    rule(part("transparent")) {
        property("left","520px"); property("top","110px")
        custom_shader("test-solid",(tint = effect_color(rgb(40,200,100),0.5)))
        custom_filter("test-swap")
    }
    rule(part("clip")) { property("position","absolute"); property("left","20px"); property("top","220px"); width(px(50)); height(px(50)); property("overflow","hidden") }
    rule(part("transformed")) { width(px(80)); height(px(60)); custom_shader("test-solid"); property("transform","translateX(10px)") }
}
[ui_component(legacy=true)]
def view(var model:Model) {
    use_style(@@sheet)
    when($()=>model.shown) {
        box("solid") { class_if("sample",true); width(px(model.width)); opacity(model.alpha); custom_shader("test-solid",(amount = model.amount)) }
        box("filtered") { class_if("sample",true) }
        box("chain") { class_if("sample",true); custom_filters(array<UiFilterEffect>(filter_effect("test-swap"),filter_effect("test-red",(amount = model.amount*0.5)))) }
        box("reverse") { class_if("sample",true) }
        box("behind") { class_if("sample",true); box("glass") {} }
        box("edge") { class_if("sample",true) }
        box("percent") { class_if("sample",true) }
        box("clock") { class_if("sample",true) }
        box("builtin") { class_if("sample",true) }
        box("shift") { class_if("sample",true) }
        box("transparent") { class_if("sample",true) }
        box("clip") { box("transformed") {} }
    }
    box("plain") { class_if("sample",true) }
}
def snapshot(phase:string) {
    // The host's check runs after swap; redraw before reading the back buffer.
    rui_render(); verify(rui_screenshot("logs/{fixture_prefix}_{phase}.png"))
}
[ui_template]
def shader_frame() {
    window_frame("frame") {
        width(px(70)); height(px(50)); custom_shader("test-solid")
        slot("content")
    }
}
def check_errors() {
    let counts=gpu_effect_counts()
    var caught=false
    try { register_shader("test-solid","invalid") } recover { caught=true }
    verify(caught && gpu_effect_counts()==counts)
    caught=false
    try { register_shader("test-broken","not GLSL") } recover { caught=true }
    verify(caught && !shader_registered("test-broken") && gpu_effect_counts()==counts)
    verify(!empty(rui_gpu_error()),"GL driver compiler diagnostics are retained")
    register_shader("test-broken",%_esc~vec4 effect(vec2 uv) { return vec4(1); }%_esc)
    verify(unregister_shader("test-broken"))
    register_shader("test-broken",%_esc~vec4 effect(vec2 uv) { return vec4(0); }%_esc)
    verify(unregister_shader("test-broken") && !unregister_shader("test-broken"))
    caught=false
    try { register_filter("test-invalid","unused",array<UiEffectParam>(effect_number_param("value",1.),effect_number_param("value",2.))) } recover { caught=true }
    verify(caught && gpu_effect_counts()==counts)
    caught=false
    try { register_shader("linear-gradient","unused") } recover { caught=true }
    verify(caught && gpu_effect_counts()==counts)
    caught=false
    try { filter_effect("test-solid") } recover { caught=true }
    verify(caught)
    caught=false
    try { filter_effect("test-red",(typo = 1.)) } recover { caught=true }
    verify(caught)
    caught=false
    try { filter_effect("test-red",array<UiEffectArg>(effect_arg("amount",1.),effect_arg("amount",2.))) } recover { caught=true }
    verify(caught)
    verify(!shader_registered("") && !unregister_filter(""))
    caught=false
    try { filter_effect("test-red",array<UiEffectArg>(UiEffectArg(name="amount",value="oops"))) } recover { caught=true }
    verify(caught)
    caught=false
    try { register_shader("test-invalid","unused",array<UiEffectParam>(UiEffectParam(name="edge",parser="length_percent",default_value="oops"))) } recover { caught=true }
    verify(caught && gpu_effect_counts()==counts)
    caught=false
    try { register_shader("test-invalid","unused",(asset = "path")) } recover { caught=true }
    verify(caught && gpu_effect_counts()==counts)
}
def exercise(dsl:bool):int {
    var model=Model(); var installed=false; var saved:int2
    fixture_prefix=dsl ? "gpu" : "gpu_raw"
    let result=run_gl_demo("GPU effect pixels","logs/{fixture_prefix}_initial.png",true,$(dt:float) {
        if (!installed) {
            if (dsl) { install_shader_fixture() } else { install() }
            check_errors(); installed=true; rui_test_display_scale(1.); rui_test_advance_time(0.0lf); unsafe { heap_collect(true,false) }
        }
    },$() { ui_legacy_frame() { view(model) } },$(frame:int) {
        if (frame==0) { saved=gpu_effect_counts(); verify(saved.x==6 && saved.y>0); verify(!unregister_shader("test-solid") && !unregister_filter("test-swap")); ui_clear_stats() }
        elif (frame==1) { verify(gpu_effect_counts()==saved && ui_stats().binding_updates==0); rui_test_advance_time(1.0lf); unsafe { heap_collect(true,false) } }
        elif (frame==2) { snapshot("time"); model.amount=0.5; model.alpha=0.5 }
        elif (frame==3) { snapshot("alpha"); verify(gpu_effect_counts()==saved); rui_test_display_scale(2.); model.width=120. }
        elif (frame==4) { snapshot("dpi"); verify(gpu_effect_counts()==saved); model.shown=false }
        elif (frame==5) { verify(gpu_effect_counts().y==0); snapshot("removed"); unsafe { heap_collect(true,false) }; model.shown=true }
        elif (frame==6) { verify(gpu_effect_counts()==saved); snapshot("remount"); ui_clear_stats() }
        elif (frame==11) {
            verify(ui_stats().binding_updates==0); verify(gpu_effect_counts()==saved)
            let window=open_template(@@shader_frame,"GPU template",float2(620.,20.))
            rui_update(); snapshot("template"); verify(gpu_effect_counts().y==saved.y+1)
            verify(rui_warning_count()==0ul)
            // Shutdown with compiled instances still attached, before the script Context dies.
            rui_shutdown(); verify(gpu_effect_counts()==int2(0)); unsafe { heap_collect(true,false) }
        }
    })
    verify(gpu_effect_counts()==int2(0) && !shader_registered("test-solid"))
    unsafe { heap_collect(true,false) }
    print("PASS: GPU registration, errors, parameters, lifecycle/GC, cache, resize, DPI, time and rendering\n")
    return result
}
[export]
def main(smoke:bool):int {
    if (exercise(false)!=0) { return 1 }
    // Registries, retired instancers and the GL loader must restart in a new context.
    return exercise(true)
}
