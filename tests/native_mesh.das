options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope
require dassdl3/sdl3_gl_egl
require math

var generated,file_texture,foreign:uint64
var paints,creates,destroys,rejections:int
var cleared:bool

def reject_mesh(id:uint64; mode:int) {
    var mesh:UiNativeMesh
    mesh_quad(mesh,float4(0.,0.,10.,10.),rgb(255,255,255))
    if (mode==0) { mesh.indices[0]=-1 }
    elif (mode==1) { mesh.indices[0]=4 }
    elif (mode==2) { mesh.indices |> push(0) }
    elif (mode==3) { clear(mesh.colors) }
    elif (mode==4) { mesh.vertices[0].x=sqrt(-1.) }
    elif (mode==5) { mesh.vertices[0].z=sqrt(-1.) }
    var caught=false
    try { native_mesh(id,mesh,mode==6 ? foreign : 0ul) } recover { caught=true }
    verify(caught,"invalid mesh must fail atomically")
    rejections+=1
}
def paint(event:UiNativeEvent) {
    let id=event.element
    if (event.kind==UiNativeKind.Create) { creates+=1 }
    elif (event.kind==UiNativeKind.Destroy) { destroys+=1 }
    elif (event.kind==UiNativeKind.Paint) {
        paints+=1
        if (cleared) { native_rect(id,float4(0.,0.,180.,110.),rgb(60,80,100)); return }
        var pixels:array<uint4>
        for (y in range(16)) {
            for (x in range(16)) {
                pixels |> push(y<8 ? (x<8 ? uint4(240u,40u,20u,255u) : uint4(20u,220u,80u,255u)) :
                    (x<8 ? uint4(40u,80u,240u,128u) : uint4(240u,220u,40u,255u)))
            }
        }
        generated=native_texture_rgba(id,int2(16,16),pixels)
        file_texture=native_texture_load(id,"examples/assets/native_mesh_atlas.png")
        verify(generated!=0ul && file_texture!=0ul)
        verify(native_texture_size(id,generated)==int2(16,16) && native_texture_size(id,file_texture)==int2(64,32))
        // The lazy texture callback must never borrow script pixel memory.
        clear(pixels); unsafe { heap_collect(true,false) }
        for (i in range(7)) { reject_mesh(id,i) }
        var invalid=false
        try { native_texture_rgba(id,int2(2,2),pixels) } recover { invalid=true }
        verify(invalid)
        invalid=false
        try { native_texture_rgba(id,int2(-1,2),pixels) } recover { invalid=true }
        verify(invalid)
        invalid=false
        try { native_texture_rgba(id,int2(4097,1),pixels) } recover { invalid=true }
        verify(invalid)
        var mesh:UiNativeMesh
        mesh_quad(mesh,float4(0.,0.,80.,60.),rgb(255,255,255))
        native_mesh(id,mesh,generated)
        clear(mesh.vertices); clear(mesh.colors); clear(mesh.indices)
        // Texture -> solid -> same texture must keep the submission order.
        native_rect(id,float4(8.,8.,16.,16.),rgb(255,255,255))
        native_image(id,generated,float4(12.,12.,8.,8.),float4(0.75,0.25,0.75,0.25))
        // UV subrects from a PNG atlas and a tinted second submission.
        native_image(id,file_texture,float4(100.,0.,64.,64.),float4(0.,0.,0.5,1.))
        mesh_quad(mesh,float4(100.,70.,64.,40.),rgb(255,128,255),float4(0.5,0.,1.,1.))
        native_mesh(id,mesh,file_texture)
        clear(mesh.vertices); clear(mesh.colors); clear(mesh.indices)
        mesh_vertex(mesh,float2(0.,70.),rgb(240,0,0))
        mesh_vertex(mesh,float2(60.,70.),rgb(0,240,0))
        mesh_vertex(mesh,float2(0.,130.),rgb(0,0,240))
        mesh_triangle(mesh,0,1,2); native_mesh(id,mesh)
        // Crosses the parent's clip on the right and bottom.
        native_rect(id,float4(175.,0.,50.,140.),rgb(180,40,200))
        unsafe { heap_collect(true,false) }
    }
}
[ui_style]
def fixture_style() { rule("body") { background(rgb(0,0,0)); width(px(320)); height(px(200)) } }
[ui_component(legacy=true)]
def view() {
    use_style(@@fixture_style)
    box("clip") {
        property("position","absolute"); property("left","20px"); property("top","20px")
        width(px(200)); height(px(120)); property("overflow","hidden")
        native_element("mesh","test-mesh") { width(px(260)); height(px(140)); property("display","block") }
    }
    native_element("other","test-other") { property("position","absolute"); property("left","270px"); width(px(1)); height(px(1)) }
}
def snapshot(renderer:SDL_Renderer?; prefix,phase:string) {
    if (renderer!=null) { verify(is_ok(renderer |> clear(uint4(0u,0u,0u,255u)))) }
    rui_render(); verify(rui_screenshot("logs/mesh_{prefix}_{phase}.png"))
}
def exercise(renderer:SDL_Renderer?; prefix:string) {
    verify(rui_default_font()); rui_test_display_scale(1.)
    generated=0ul; file_texture=0ul; foreign=0ul; paints=0; creates=0; destroys=0; rejections=0; cleared=false
    register_native_element("test-mesh",@@paint,float2(260.,140.))
    register_native_element("test-other",@(event:UiNativeEvent) {})
    ui_legacy_frame() { view() }
    let id=ui_find("mesh"); let other=ui_find("other")
    verify(rui_is_native(id) && rui_is_native(other),"both native elements mounted")
    var pixel=array<uint4>(uint4(255u))
    foreign=native_texture_rgba(other,int2(1,1),pixel)
    snapshot(renderer,prefix,"initial")
    verify(paints==1 && rejections==7 && native_texture_resources()==3)
    let old=generated
    verify(!native_texture_release(other,generated),"handles are scoped to the owning element")
    verify(native_texture_size(other,generated)==int2(0))
    verify(native_texture_release(id,generated) && native_texture_release(id,file_texture))
    verify(!native_texture_release(id,old) && native_texture_size(id,old)==int2(0))
    verify(native_texture_resources()==3,"cached batches retain released textures")
    unsafe { heap_collect(true,false) }
    ui_clear_stats(); ui_legacy_frame() { view() }; snapshot(renderer,prefix,"cached")
    verify(paints==1 && ui_stats().binding_updates==0)
    cleared=true; native_invalidate(id); snapshot(renderer,prefix,"cleared")
    verify(paints==2 && native_texture_resources()==1,"repaint releases textures retained by old batches")
    // A new handle must never alias a released handle.
    let replacement=native_texture_rgba(id,int2(1,1),pixel)
    verify(replacement!=old && native_texture_release(id,replacement))
    verify(native_texture_release(other,foreign) && native_texture_resources()==0)
    var invalid=false
    try { native_image(id,old,float4(0.,0.,10.,10.)) } recover { invalid=true }
    verify(invalid,"draw calls outside Paint are rejected")
    ui_reset(); verify(destroys==creates && native_texture_resources()==0)
    register_native_element("test-failed-mesh",@(event:UiNativeEvent) {
        if (event.kind==UiNativeKind.Paint) {
            var data=array<uint4>(uint4(255u))
            let owned=native_texture_rgba(event.element,int2(1,1),data)
            native_image(event.element,owned,float4(0.,0.,10.,10.))
            panic("intentional failure after texture submission")
        }
    },float2(10.,10.))
    let failed=rui_create(rui_root(),"test-failed-mesh","","")
    rui_update(); invalid=false
    try { rui_render() } recover { invalid=true }
    verify(invalid && native_texture_resources()==1)
    rui_remove(failed); rui_update()
    verify(native_texture_resources()==0 && unregister_native_element("test-failed-mesh"),"failed Paint still releases all owned textures")
    // Remount allocates fresh resources; shutdown also destroys unreleased handles.
    cleared=false; foreign=old
    ui_legacy_frame() { view() }; snapshot(renderer,prefix,"remount")
    verify(ui_find("mesh")!=id && generated!=old && native_texture_resources()==2)
    verify(!native_texture_release(id,generated))
    verify(rui_warning_count()==0)
    rui_shutdown(); verify(creates==destroys && native_texture_resources()==0 && native_handler_count()==0)
    ui_reset()
    unsafe { heap_collect(true,false) }
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
        let window:SDL_Window?=with_window("Native mesh pixels",320,200,SDL_WINDOW_HIDDEN | (gl ? SDL_WINDOW_OPENGL : 0ul)) |> sdl_use
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
    print("PASS: bulk mesh validation, RGBA and file textures, ownership, retained cache, GC and shutdown on SDL/GL3\n")
    return 0
}
