options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Model {
    visible:bool
    parent:bool=true
    playing:bool=true
    revision,completions,clicks:int
    transition_property:string
    iterations:int=1
}
struct Local { note:string="preserved" }
var mounts,unmounts,runs:int

[ui_style]
def test_style() {
    keyframes("sample") {
        keyframe(0.) { opacity(0.2); width(px(20)) }
        keyframe(100.) { opacity(1.); width(px(80)) }
    }
    keyframes("enter") {
        keyframe(0.) { opacity(0.) }
        keyframe(100.) { opacity(1.) }
    }
    keyframes("leave") {
        keyframe(0.) { opacity(1.) }
        keyframe(100.) { opacity(0.) }
    }
    rule(part("actor")) { opacity(1.); width(px(80)); height(px(20)) }
    rule(part("panel")) { opacity(1.); width(px(200)); height(px(100)) }
    rule(part("shell")+" button") { width(px(150)); height(px(30)) }
    rule(part("trigger")) { background(rgb(10,20,30)); property("transition","background-color 0.2s") }
    rule(part("trigger")+":focus") { background(rgb(200,210,220)) }
}
[ui_component(legacy=true)]
def child(var model:Model) {
    state(Local()) $(var local:Local) {
        on_mount() { mounts+=1 }
        on_unmount() { verify(local.note=="preserved!"); unmounts+=1 }
        focus_scope("scope") {
            text_input("field") { bind_value(local.note) $(value:string) { local.note=value } }
            button("hit","Hit") { on_click() { model.clicks+=1 } }
        }
    }
}
[ui_component(legacy=true)]
def screen(var model:Model) {
    runs+=1
    use_style(@@test_style)
    column("shell") {
        button("trigger","Replay") {
            on_click() { model.revision+=1 }
            on_transition_end() $(property_name:string) { model.transition_property=property_name }
        }
        box("actor") {
            animate(motion("sample",0.6,"linear-in-out",model.iterations),model.revision,model.playing)
            on_animation_end() $(name:string) { model.completions+=1 }
        }
        when(model.parent) {
            animated_when("panel",model.visible,motion("enter",0.4),motion("leave",0.4)) { child(model) }
        }
    }
}
def advance(seconds:float) {
    for (i in range(int(seconds/0.05+0.5))) { rui_test_advance_time(double(0.05)); rui_update() }
}
[export]
def main(smoke:bool):int {
    var model=Model()
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Animation tests",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480)); verify(rui_default_font())
        rui_test_advance_time(double(0.))
        ui_legacy_frame() { screen(model) }
        let actor=ui_find("actor")
        let trigger=ui_find("trigger")
        verify(rui_bounds(actor).z==20.,"initial key applied before first render")
        verify(rui_animation_status(actor)==2)
        let idle_runs=runs
        ui_clear_stats()
        advance(0.2)
        ui_legacy_frame() { screen(model) }
        verify(rui_bounds(actor).z>21. && rui_bounds(actor).z<80.,"native interpolation")
        verify(runs==idle_runs && ui_stats().updates==0,"native animation must not rerun components")
        advance(0.5)
        ui_legacy_frame() { screen(model) }; ui_legacy_frame() { screen(model) }
        verify(model.completions==1,"one completion for both width and opacity")
        rui_focus(trigger)
        model.visible=true
        ui_legacy_frame() { screen(model) }
        let panel=ui_find("panel")
        let field=ui_find("field")
        verify(mounts==1 && panel!=0ul)
        rui_focus(field); rui_test_event(field,"change","preserved!")
        ui_legacy_frame() { screen(model) }
        verify(rui_get_value(field)=="preserved!")
        advance(0.5)
        ui_legacy_frame() { screen(model) }
        model.visible=false
        ui_legacy_frame() { screen(model) }
        verify(rui_alive(panel) && unmounts==0 && !rui_enabled(field),"retain but disable exiting subtree")
        verify(rui_focused(trigger),"return focus at exit start")
        rui_test_event(ui_find("hit"),"click","")
        advance(0.15)
        ui_legacy_frame() { screen(model) }
        verify(model.clicks==0 && rui_alive(panel))
        model.visible=true
        ui_legacy_frame() { screen(model) }
        verify(ui_find("panel")==panel && ui_find("field")==field && mounts==1,"cancel exit without remount")
        unsafe { heap_collect(true,false) }
        advance(0.5)
        ui_legacy_frame() { screen(model) }
        verify(rui_alive(panel) && rui_get_value(field)=="preserved!" && rui_enabled(field))
        model.visible=false
        ui_legacy_frame() { screen(model) }
        advance(0.5)
        ui_legacy_frame() { screen(model) }
        verify(!rui_alive(panel) && !rui_alive(field) && unmounts==1,"unmount after native exit completion")

        // Native completion is queued after click, then frozen by ui_frame.
        // Replaying in the click handler must invalidate that old completion.
        model.revision+=1
        ui_legacy_frame() { screen(model) }
        rui_test_event(trigger,"click","")
        advance(0.7); rui_update()
        let completions=model.completions
        ui_legacy_frame() { screen(model) }
        verify(model.completions==completions && rui_animation_status(actor)==2,"discard stale completion after replay")
        advance(0.7)
        ui_legacy_frame() { screen(model) }; ui_legacy_frame() { screen(model) }
        verify(model.completions==completions+1)

        model.iterations=2
        ui_legacy_frame() { screen(model) }
        advance(0.7)
        ui_legacy_frame() { screen(model) }
        verify(rui_animation_status(actor)==2,"second iteration still running")
        advance(0.7)
        ui_legacy_frame() { screen(model) }; ui_legacy_frame() { screen(model) }
        verify(model.completions==completions+2)
        model.iterations=-1
        ui_legacy_frame() { screen(model) }
        advance(5.)
        ui_legacy_frame() { screen(model) }; ui_legacy_frame() { screen(model) }
        verify(rui_animation_status(actor)==2 && model.completions==completions+2,"infinite animation")
        model.playing=false
        ui_legacy_frame() { screen(model) }
        verify(rui_animation_status(actor)==0 && rui_bounds(actor).z==80.,"stop restores base style")

        rui_focus(trigger); model.visible=true
        ui_legacy_frame() { screen(model) }
        verify(mounts==2 && ui_find("panel")!=panel)
        rui_focus(ui_find("field")); rui_test_event(ui_find("field"),"change","preserved!")
        ui_legacy_frame() { screen(model) }
        model.visible=false
        ui_legacy_frame() { screen(model) }
        model.parent=false
        ui_legacy_frame() { screen(model) }
        verify(unmounts==2,"removing parent immediately cancels exiting subtree")
        verify(model.transition_property=="background-color","native transition completion reports the property")
        let invalid=rui_animation_start(actor,"missing_keyframes",0.2,"linear-in-out",1,false)
        rui_update()
        verify(invalid!=0ul && rui_animation_status(actor)==4,"unknown keyframes fail instead of waiting forever")
        rui_animation_cancel(actor)
        ui_reset(); rui_shutdown()
        print("PASS: native interpolation, idle components, grouped completion, replay, repeat, stop, exit, focus, preserved state, GC and cleanup\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}




