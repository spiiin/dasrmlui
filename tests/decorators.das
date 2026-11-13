options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope
require dassdl3/sdl3_gl_egl

struct Memory { texture:uint64; seed:string; element,canvas:uint64 }
struct Model { amount:float=0.5; opacity:float=1.; width:float=80.; shown:bool=true; changed:bool }
var memories:table<uint64;Memory>
var creates,destroys,paints:int
var last_canvas:uint64
def install(seed:string) {
    let params=(fill = rgb(40,200,100), edge = dp(4), amount = 0.5, asset = "examples/assets/native_mesh_atlas.png")
    register_decorator("test-frame",params,@(event:UiDecoratorEvent) {
        let canvas=event.canvas
        if (event.kind==UiDecoratorKind.Create) {
            memories[canvas]=Memory(seed="{seed}:owned",element=event.element,canvas=canvas); creates+=1
            verify(rui_alive(event.element),"decorator belongs to an ordinary live element")
        } elif (event.kind==UiDecoratorKind.Destroy) {
            verify(key_exists(memories,canvas)); memories |> erase(canvas); destroys+=1
            verify(native_texture_size(canvas,0ul)==int2(0),"canvas is already invalid in Destroy")
            unsafe { heap_collect(true,false) }
        } else {
            verify(memories[canvas].seed=="{seed}:owned")
            unsafe { heap_collect(true,false) }
            let fill=decorator_color(canvas,"fill")
            let edge=decorator_length(canvas,"edge",event.size.x)
            let amount=decorator_number(canvas,"amount")
            verify(edge>0. && event.dpi>0.)
            if (fill.ink.b==240) { verify(edge==8.,"percentage length resolves against caller-selected base") }
            if (memories[canvas].texture==0ul) {
                memories[canvas].texture=native_texture_load(canvas,decorator_string(canvas,"asset"))
                verify(memories[canvas].texture!=0ul)
            }
            native_rect(canvas,float4(0.,0.,event.size.x,event.size.y),fill.ink,fill.alpha)
            native_rect(canvas,float4(0.,0.,edge,event.size.y),rgb(180,40,200))
            native_rect(canvas,float4(0.,event.size.y-8.,event.size.x*amount,8.),rgb(40,100,240))
            native_image(canvas,memories[canvas].texture,float4(12.,12.,16.,16.),float4(0.,0.,0.5,1.))
            last_canvas=canvas; paints+=1
        }
    })
}
[ui_style]
def sheet() {
    rule("body") { background(rgb(0,0,0)); width(px(320)); height(px(200)) }
    rule(part("clip")) { property("position","absolute"); property("left","20px"); property("top","20px"); width(px(90)); height(px(70)); property("overflow","hidden") }
    rule(part("first")) { padding(px(6)); height(px(60)); property("border","2px #fff") }
    rule(part("second")) {
        property("position","absolute"); property("left","140px"); property("top","20px")
        width(px(80)); height(px(60)); padding(px(6)); property("border","2px #fff")
        custom_decorator("test-frame","content-box")
    }
    rule(part("second")+":hover") {
        custom_decorator("test-frame",(fill = rgb(80,120,240), edge = pct(10)),"content-box")
    }
}
[ui_component(legacy=true)]
def view(var model:Model) {
    use_style(@@sheet)
    box("clip") {
        when($()=>model.shown) {
            box("first") {
                width(px(model.width)); opacity(model.opacity)
                custom_decorator("test-frame",(amount = model.amount, fill = model.changed ? rgb(240,80,60) : rgb(40,200,100)))
            }
        }
    }
    box("second") {}
}
[ui_template]
def decorated_frame() {
    window_frame("frame") {
        width(px(60)); height(px(50))
        custom_decorator("test-frame","border-box")
        slot("body")
    }
}
def snapshot(renderer:SDL_Renderer?; prefix,phase:string) {
    if (renderer!=null) { verify(is_ok(renderer |> clear(uint4(0u,0u,0u,255u)))) }
    rui_render(); verify(rui_screenshot("logs/decorator_{prefix}_{phase}.png"))
}
def exercise(renderer:SDL_Renderer?; prefix:string) {
    var inscope survivor=array<string>("caller-live-{prefix}")
    verify(rui_default_font()); rui_test_display_scale(1.)
    creates=0; destroys=0; paints=0; last_canvas=0ul
    install("capture"); unsafe { heap_collect(true,false) }
    verify(decorator_handler_count()==1)
    // Bad schemas must not replace or root a handler.
    var caught=false
    try { register_decorator("linear-gradient",array<UiDecoratorParam>(),@(event:UiDecoratorEvent) {}) } recover { caught=true }
    verify(caught)
    caught=false
    try { install("duplicate") } recover { caught=true }
    verify(caught && decorator_handler_count()==1)
    caught=false
    try { register_decorator("test-invalid",array<UiDecoratorParam>(UiDecoratorParam(name="edge",parser="length_percent",default_value="nonsense")),@(event:UiDecoratorEvent) {}) } recover { caught=true }
    verify(caught && !decorator_registered("test-invalid"))
    caught=false
    try { register_decorator("test-duplicate",array<UiDecoratorParam>(decorator_number_param("value",1.),decorator_number_param("value",2.)),@(event:UiDecoratorEvent) {}) } recover { caught=true }
    verify(caught && decorator_handler_count()==1)
    register_decorator("test-unused",array<UiDecoratorParam>(),@(event:UiDecoratorEvent) {})
    verify(unregister_decorator("test-unused") && !unregister_decorator("test-unused"))
    register_decorator("test-unused",(value = 1.),@(event:UiDecoratorEvent) {})
    verify(unregister_decorator("test-unused"),"re-registration keeps retired RCSS pointers safe")
    var model=Model()
    ui_legacy_frame() { view(model) }; snapshot(renderer,prefix,"initial")
    verify(creates-destroys==2 && decorator_instance_count("test-frame")==2 && native_texture_resources()==2)
    let first=ui_find("first"); let old_canvas=last_canvas; let saved=paints
    var second_canvas:uint64
    let second=ui_find("second")
    for (memory in values(memories)) { if (memory.element==second) { second_canvas=memory.canvas } }
    verify(!rui_is_native(first) && !unregister_decorator("test-frame"))
    ui_clear_stats(); ui_legacy_frame() { view(model) }; snapshot(renderer,prefix,"cached")
    verify(paints==saved && ui_stats().binding_updates==0)
    native_invalidate(old_canvas); snapshot(renderer,prefix,"invalidate"); verify(paints==saved+1)
    caught=false
    try { decorator_number(old_canvas,"fill") } recover { caught=true }; verify(caught)
    caught=false
    try { custom_decorator("test-frame",(unknown = 1)) } recover { caught=true }; verify(caught)
    caught=false
    try { custom_decorator("test-frame",(edge = "nonsense")) } recover { caught=true }; verify(caught)
    caught=false
    try { custom_decorator("test-frame",array<UiDecoratorArg>(decorator_arg("amount",1.),decorator_arg("amount",0.))) } recover { caught=true }; verify(caught)
    model.changed=true; model.amount=0.8; ui_legacy_frame() { view(model) }; snapshot(renderer,prefix,"changed")
    verify(ui_find("first")==first && creates-destroys==2 && native_texture_resources()==2)
    verify(key_exists(memories,second_canvas),"changing one binding leaves the other decorator data intact")
    model.opacity=0.5; ui_legacy_frame() { view(model) }; snapshot(renderer,prefix,"alpha")
    model.opacity=1.; set_ui_scale(2.); ui_legacy_frame() { view(model) }; snapshot(renderer,prefix,"dpi")
    model.width=50.; ui_legacy_frame() { view(model) }; snapshot(renderer,prefix,"resized")
    model.shown=false; ui_legacy_frame() { view(model) }; snapshot(renderer,prefix,"removed")
    verify(creates-destroys==1 && native_texture_resources()==1)
    model.shown=true; ui_legacy_frame() { view(model) }; snapshot(renderer,prefix,"remount")
    verify(ui_find("first")!=first && creates-destroys==2)
    rui_pseudo(ui_find("second"),"hover",true); rui_update(); snapshot(renderer,prefix,"hover")
    rui_pseudo(ui_find("second"),"hover",false); rui_update(); rui_render()
    verify(survivor[0]=="caller-live-{prefix}","GC in callbacks traces suspended caller locals")
    unsafe { heap_collect(true,false) }
    ui_reset(); rui_update(); verify(creates==destroys && empty(memories) && native_texture_resources()==0)
    caught=false
    try { decorator_number(old_canvas,"amount") } recover { caught=true }; verify(caught)
    // Two uses of one decorator type on one ordinary element need distinct canvases.
    let layered=rui_create(rui_root(),"div","","")
    rui_property(layered,"display","block"); rui_property(layered,"width","60px"); rui_property(layered,"height","50px")
    rui_property(layered,"decorator","test-frame(), test-frame()")
    rui_update(); rui_render()
    verify(decorator_instance_count("test-frame")==2 && length(memories)==2 && native_texture_resources()==2)
    rui_remove(layered); rui_update()
    verify(empty(memories) && native_texture_resources()==0)
    let document=open_template(@@decorated_frame,"Decorated template",float2(240.,110.))
    rui_update(); rui_render()
    verify(decorator_instance_count("test-frame")==1 && native_texture_resources()==1)
    close_document(document); rui_update()
    verify(empty(memories) && native_texture_resources()==0 && creates==destroys)
    // Failure after resource submission: no callback unwinds a native render traversal.
    for (mode in range(3)) {
        let name="test-fault-{mode}"
        register_decorator(name,array<UiDecoratorParam>(),@(event:UiDecoratorEvent) {
            if (mode==0 && event.kind==UiDecoratorKind.Create) { panic("create fault") }
            if (event.kind==UiDecoratorKind.Paint) {
                var data=array<uint4>(uint4(255u))
                let texture=native_texture_rgba(event.canvas,int2(1,1),data)
                native_image(event.canvas,texture,float4(0.,0.,10.,10.))
                if (mode==1) { rui_remove(event.element) }
            }
            if (mode==2 && event.kind==UiDecoratorKind.Destroy) { panic("destroy fault") }
        })
        let element=rui_create(rui_root(),"div","","")
        rui_property(element,"width","20px"); rui_property(element,"height","20px"); rui_property(element,"decorator","{name}()")
        rui_update(); var errors=0
        try { rui_render() } recover { errors+=1 }
        try { rui_remove(element); rui_update(); rui_native_check() } recover { errors+=1 }
        verify(errors==1 && decorator_instance_count(name)==0 && native_texture_resources()==0)
    }
    verify(rui_warning_count()==0)
    // Live canvas teardown before the script Context and renderer disappear.
    ui_legacy_frame() { view(model) }; snapshot(renderer,prefix,"shutdown")
    rui_shutdown(); verify(creates==destroys && empty(memories) && native_texture_resources()==0 && decorator_handler_count()==0)
    ui_reset(); unsafe { heap_collect(true,false) }
}

def run_backend(gl:bool):int {
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        if (gl) {
            set_gl_attribute(SDL_GLAttr.GL_CONTEXT_MAJOR_VERSION,3) |> sdl_try
            set_gl_attribute(SDL_GLAttr.GL_CONTEXT_MINOR_VERSION,3) |> sdl_try
            set_gl_attribute(SDL_GLAttr.GL_CONTEXT_PROFILE_MASK,int(SDL_GL_CONTEXT_PROFILE_CORE)) |> sdl_try
            set_gl_attribute(SDL_GLAttr.GL_STENCIL_SIZE,8) |> sdl_try
        }
        let window:SDL_Window?=with_window("Decorator pixels",320,200,SDL_WINDOW_HIDDEN | (gl ? SDL_WINDOW_OPENGL : 0ul)) |> sdl_use
        if (gl) {
            let rendering=sdl_scope() {
                let context:SDL_GLContextState?=window |> with_gl_context() |> sdl_use
                verify(rui_init_gl(window,320,200)); exercise(null,"gl")
                return sdl_ok()
            }
            if (is_err(rendering)) { return rendering }
        } else {
            let rendering=sdl_scope() {
                let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
                verify(rui_init(window,renderer,320,200)); exercise(renderer,"sdl")
                return sdl_ok()
            }
            if (is_err(rendering)) { return rendering }
        }
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
[export]
def main(smoke:bool):int {
    if (run_backend(false)!=0) { return 1 }
    if (run_backend(true)!=0) { return 1 }
    print("PASS: decorators, parameters, lifecycle/GC, cache, errors, DPI and rendering on SDL/GL3\n")
    return 0
}
