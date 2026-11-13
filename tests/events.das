options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Model { subscribed:bool=true; child:bool=true; cancel:bool; immediate:bool; checked:bool }
var trail=""
var legacy,shortcuts,changes,wheels,right_clicks,customs,second:int
var snapshot=UiEvent()

[ui_component(legacy=true)]
def scene(var model:Model) {
    document_events(rui_root()) {
        on_event("remove_child") $(event:UiEvent) { model.child=false }
        on_event("unsubscribe") $(event:UiEvent) { model.subscribed=false }
        on_event("keydown",UiEventOptions(use_capture=true,key="S",modifiers=1,stop=true)) $(event:UiEvent) {
            verify(event_ctrl(event) && !event_shift(event) && event.key=="S" && event.key_code!=0,"shortcut snapshot")
            shortcuts+=1
        }
        on_event("custom",UiEventOptions(enabled=model.subscribed)) $(event:UiEvent) {
            snapshot := event
            customs+=1
        }
    }
    column("parent") {
        width(px(300)); height(px(300))
        on_event("click",UiEventOptions(use_capture=true,stop=model.cancel,stop_immediate=model.immediate)) $(event:UiEvent) {
            verify(event.phase==1 && event.handle==ui_find("parent") && rui_contains(event.handle,event.target),"capture path")
            trail+="C"
        }
        on_event("click",UiEventOptions(use_capture=true)) $(event:UiEvent) { second+=1 }
        on_event("click") $(event:UiEvent) { verify(event.phase==4,"bubble phase"); trail+="B" }
        when(model.child) {
            button("child","Click") {
                width(px(200)); height(px(40))
                on_event("click") $(event:UiEvent) { trail+="T"; snapshot := event }
                on_click() { legacy+=1 }
                on_event("mousedown") $(event:UiEvent) {
                    if (event.button==1) { right_clicks+=1; snapshot := event }
                }
                on_event("mousescroll",UiEventOptions(stop=true)) $(event:UiEvent) { wheels+=1; snapshot := event }
            }
        }
        checkbox("check") {
            width(px(24)); height(px(24))
            bind_checked(model.checked) $(value:bool) { model.checked=value }
            on_event("change",UiEventOptions(stop=true)) $(event:UiEvent) {
                verify(!event.interruptible,"change cannot be cancelled"); changes+=1
            }
        }
        text_input("input") { width(px(200)); height(px(30)) }
    }
}
[export]
def main(smoke:bool):int {
    var model=Model()
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Events",800,600,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,800,600)); verify(rui_default_font())
        ui_legacy_frame() { scene(model) }
        let count=rui_listener_count()
        ui_clear_stats()
        for (i in range(4)) { ui_legacy_frame() { scene(model) } }
        verify(rui_listener_count()==count && ui_stats().updates==0,"idle subscriptions are cached")
        rui_test_event(ui_find("child"),"click","")
        ui_legacy_frame() { scene(model) }
        verify(trail=="CTB" && legacy==1 && second==1,"capture/target/bubble and legacy exactly once")
        verify(snapshot.phase==2 && snapshot.target==ui_find("child") && snapshot.handle==snapshot.target,"target snapshot")
        trail=""; model.cancel=true
        ui_legacy_frame() { scene(model) }
        rui_test_click(ui_find("check"))
        ui_legacy_frame() { scene(model) }
        verify(trail=="C" && second==2 && !model.checked,"stop prevents native checkbox default but keeps same-node listeners")
        model.immediate=true; ui_legacy_frame() { scene(model) }
        rui_test_event(ui_find("child"),"click",""); ui_legacy_frame() { scene(model) }
        verify(second==2,"stop immediate skips remaining same-node listeners")
        model.cancel=false; model.immediate=false; ui_legacy_frame() { scene(model) }
        rui_test_click(ui_find("check")); ui_legacy_frame() { scene(model) }
        verify(model.checked && changes==1,"normal native default and noninterruptible change")
        rui_focus(ui_find("input"))
        rui_test_shortcut("S",1); rui_test_shortcut("S",3); rui_test_shortcut("S",0)
        ui_legacy_frame() { scene(model) }
        verify(shortcuts==1,"exact modifier filter without consuming unmatched keys")
        rui_test_pointer(20.,20.,1,0.); ui_legacy_frame() { scene(model) }
        verify(right_clicks==1 && snapshot.button==1 && snapshot.screen.x==20.,"right button and screen coordinates")
        rui_test_pointer(20.,20.,-1,2.); ui_legacy_frame() { scene(model) }
        verify(wheels==1 && snapshot.wheel.y!=0.,"wheel snapshot")
        rui_test_event(rui_root(),"custom","owned value"); ui_legacy_frame() { scene(model) }
        unsafe { heap_collect(true,false) }
        verify(customs==1 && event_parameter(snapshot,"value")=="owned value","document listener and owned parameters survive GC")
        rui_test_event(rui_root(),"unsubscribe","")
        rui_test_event(rui_root(),"custom","stale subscription")
        ui_legacy_frame() { scene(model) }
        verify(rui_listener_count()==count-1,"conditional static-document subscription removed")
        rui_test_event(rui_root(),"custom","ignored"); ui_legacy_frame() { scene(model) }
        verify(customs==1,"removed listener cannot run")
        // Queue two commands. The first handler removes the target of the second.
        trail=""
        let clicks_before=legacy
        rui_test_event(rui_root(),"remove_child","")
        rui_test_event(ui_find("child"),"click","")
        ui_legacy_frame() { scene(model) }
        verify(empty(trail) && legacy==clicks_before,"queued rich and legacy events cannot reach an unmounted target")
        verify(rui_listener_count()==count-4,"node listeners are released")
        ui_reset(); verify(rui_listener_count()==0,"reset also removes listeners on document roots")
        rui_shutdown()
        print("PASS: event phases, cancellation/default actions, modifiers, mouse/wheel, parameters, GC, subscription lifetime and idle caching\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
