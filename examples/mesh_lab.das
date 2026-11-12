options gen2
options persistent_heap
options gc
options stack = 65536
require examples/gl_demo_host
require math
require daslib/strings_convert

struct Textures { atlas,pattern:uint64 }
struct MeshLab { progress:float=0.72; textured:bool=true; alternate:bool; shown:bool=true }
var textures:table<uint64;Textures>
var paints,created,destroyed:int

def install_mesh_lab() {
    register_native_element("lab-mesh",@(event:UiNativeEvent) {
        let id=event.element
        if (event.kind==UiNativeKind.Create) { textures[id]=Textures(); created+=1 }
        elif (event.kind==UiNativeKind.Destroy) { textures |> erase(id); destroyed+=1 }
        elif (event.kind==UiNativeKind.Paint) {
            if (textures[id].atlas==0ul) {
                textures[id].atlas=native_texture_load(id,"examples/assets/native_mesh_atlas.png")
                verify(textures[id].atlas!=0ul)
                var inscope pixels:array<uint4>
                for (y in range(32)) {
                    for (x in range(32)) {
                        let bright=((x+y)/8)%2==0
                        pixels |> push(bright ? uint4(255u,255u,255u,255u) : uint4(85u,110u,160u,255u))
                    }
                }
                textures[id].pattern=native_texture_rgba(id,int2(32,32),pixels)
                verify(textures[id].pattern!=0ul)
            }
            let amount=try_to_float(rui_get_attr(id,"progress")) |> unwrap_or(0.72)
            let textured=rui_get_attr(id,"textured")=="true"
            let alternate=rui_get_attr(id,"alternate")=="true"
            let texture=textured ? textures[id].pattern : 0ul
            native_rect(id,float4(0.,0.,event.size.x,event.size.y),rgb(18,28,44))
            // A UV-mapped ribbon: two vertices per station, shared triangle edges.
            var inscope ribbon:UiNativeMesh
            for (i in range(65)) {
                let t=float(i)/64.; let x=35.+t*550.
                let y=100.+sin(t*7.+amount*3.)*42.
                let radius=12.+sin(t*3.14159)*22.
                let ink=alternate ? rgb(245,145,75) : rgb(80,220,210)
                mesh_vertex(ribbon,float2(x,y-radius),ink,float2(t,0.))
                mesh_vertex(ribbon,float2(x,y+radius),ink,float2(t,1.))
                if (i>0) { let k=i*2; mesh_triangle(ribbon,k-2,k,k+1); mesh_triangle(ribbon,k-2,k+1,k-1) }
            }
            native_mesh(id,ribbon,texture)
            // Annular progress. UV follows the bend instead of a rectangular clip.
            var inscope ring:UiNativeMesh
            for (i in range(97)) {
                let t=float(i)/96.; let angle=-1.570796+t*amount*6.283185
                let n=float2(cos(angle),sin(angle)); let center=float2(820.,115.)
                mesh_vertex(ring,center+n*92.,rgb(255,175,85),float2(t,0.))
                mesh_vertex(ring,center+n*65.,rgb(255,225,160),float2(t,1.))
                if (i>0) { let k=i*2; mesh_triangle(ring,k-2,k,k+1); mesh_triangle(ring,k-2,k+1,k-1) }
            }
            native_mesh(id,ring,texture)
            // An untextured fan with interpolated per-vertex colors.
            var inscope fan:UiNativeMesh
            mesh_vertex(fan,float2(200.,310.),rgb(250,240,255))
            for (i in range(7)) {
                let angle=float(i)*1.047198
                let ink=i%2==0 ? rgb(155,100,245) : rgb(45,190,240)
                mesh_vertex(fan,float2(200.,310.)+float2(cos(angle),sin(angle))*67.,ink)
                if (i>0) { mesh_triangle(fan,0,i,i+1) }
            }
            native_mesh(id,fan)
            native_image(id,textures[id].atlas,float4(390.,265.,90.,90.),float4(0.,0.,0.5,1.))
            native_image(id,textures[id].atlas,float4(500.,265.,90.,90.),float4(0.5,0.,1.,1.))
            native_line(id,float2(655.,270.),float2(690.,310.),4.,rgb(90,225,200))
            native_triangle(id,float2(690.,310.),float2(680.,292.),float2(704.,299.),rgb(90,225,200))
            // Tint + alpha over a solid primitive, retaining draw order across textures.
            var inscope badge:UiNativeMesh
            mesh_quad(badge,float4(760.,265.,115.,90.),rgb(255,150,210),float4(0.5,0.,1.,1.),0.7)
            native_mesh(id,badge,textures[id].atlas)
            paints+=1
        }
    },float2(1050.,410.))
}
[ui_style]
def mesh_style() {
    rule("body") { background(rgb(10,17,29)); color(rgb(223,234,246)); font_size(px(16)) }
    rule(part("page")) { padding(px(42)) }
    rule(part("kicker")) { color(rgb(83,215,204)); font_size(px(13)); margin_bottom(px(14)) }
    rule(part("title")) { font_size(px(44)); margin_bottom(px(10)) }
    rule(part("intro")) { color(rgb(142,161,185)); margin_bottom(px(22)) }
    rule(part("canvas")) { width(px(1050)); height(px(410)); property("display","block"); property("border-radius","14px"); property("overflow","hidden") }
    rule(part("legend")) { color(rgb(142,161,185)); font_size(px(13)); margin_top(px(12)); margin_bottom(px(22)) }
    rule(part("controls")) { property("align-items","center"); margin_bottom(px(18)) }
    rule(part("controls")+" button") { background(rgb(35,53,76)); color(rgb(225,236,247)); padding(px(12)); property("margin-right","12px"); property("border-radius","7px") }
    rule(part("controls")+" button:hover") { background(rgb(51,78,105)) }
    rule(part("progress")) { width(px(240)); height(px(24)); property("margin-right","20px") }
    rule(part("progress")+" slidertrack") { height(px(5)); margin_top(px(8)); background(rgb(65,86,110)) }
    rule(part("progress")+" sliderbar") { width(px(15)); height(px(22)); background(rgb(255,175,85)) }
    rule(part("note")) { color(rgb(113,137,164)); font_size(px(13)) }
}
[ui_component]
def mesh_view(var model:MeshLab) {
    use_style(@@mesh_style)
    column("page") {
        text("kicker","GEOMETRY WORKSHOP   /   NATIVE RMLUI   /   018")
        text("title","Bend the surface.")
        text("intro","Indexed meshes, curved UVs and textures. Every shape is built in daScript.")
        when($()=>model.shown) {
            native_element("canvas","lab-mesh") {
                attribute("progress","{model.progress}"); attribute("textured","{model.textured}"); attribute("alternate","{model.alternate}")
            }
        }
        text("legend","01  UV RIBBON                         02  CURVED PROGRESS          /          03  VERTEX COLOR     04  ATLAS SPRITES     05  TINT + ALPHA")
        row("controls") {
            range_input("progress") { bind_range(model.progress,0.05,1.,0.01) $(value:float) { model.progress=value } }
            button("texture",model.textured ? "Texture: on" : "Texture: off") { on_click() { model.textured=!model.textured } }
            button("tint","Switch ribbon tint") { on_click() { model.alternate=!model.alternate } }
            button("mount",model.shown ? "Unmount canvas" : "Mount canvas") { on_click() { model.shown=!model.shown } }
            button("gc","Collect heap") { on_click() { unsafe { heap_collect(true,false) } } }
        }
        text("note","Paint runs only after a change. Native batches retain textures and geometry; script arrays can be collected immediately.")
    }
}
[export]
def main(smoke:bool):int {
    var model=MeshLab(); var saved=0
    let result=run_gl_demo("Mesh workshop - textures and geometry","logs/mesh_lab.png",smoke,$(dt:float) {
        if (!native_registered("lab-mesh")) { install_mesh_lab() }
    },$() { mesh_view(model) },$(frame:int) {
        if (frame==0) { verify(paints==1 && native_texture_resources()==2); saved=paints; ui_clear_stats() }
        elif (frame==1) { verify(paints==saved && ui_stats().binding_updates==0); rui_test_click(ui_find("gc")) }
        elif (frame==2) { verify(paints==saved); rui_test_event(ui_find("progress"),"change","0.4") }
        elif (frame==3) { verify(model.progress==0.4 && paints>saved); rui_test_click(ui_find("texture")) }
        elif (frame==4) { verify(!model.textured); rui_test_click(ui_find("tint")) }
        elif (frame==5) { verify(model.alternate); rui_test_click(ui_find("mount")) }
        elif (frame==6) { verify(destroyed==1 && native_texture_resources()==0); rui_test_click(ui_find("mount")) }
        elif (frame==7) { verify(created==2 && native_texture_resources()==2) }
        elif (frame==11) { verify(rui_warning_count()==0); print("PASS: mesh workshop, UV ribbon, ring, atlas, tint, cache, remount and GC\n") }
    })
    if (smoke) { verify(created==destroyed && native_texture_resources()==0 && empty(textures)) }
    return result
}
