options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Model { mode:UiNav=UiNav.Auto; blocked,hidden:bool; target:string="six"; popup:uint64 }
var clicks,reads:int
[ui_style]
def layout() {
    rule(part("grid")) { width(px(340)); height(px(125)); property("position","relative"); property("overflow","auto") }
    rule(part("cell")) { width(px(90)); height(px(40)); property("position","absolute"); nav() }
    rule(part("cell")+":focus-visible") { background(rgb(255,200,30)) }
}
[ui_template]
def popup_frame() {
    window_frame("frame") {
        nav(); width(px(250)); height(px(100)); property("position","absolute"); property("z-index","2")
        slot("items")
    }
}
[ui_component(legacy=true)]
def stable() { text("stable") { reads+=1; return "unchanged" } }
[ui_component(legacy=true)]
def scene(var model:Model) {
    use_style(@@layout)
    document_nav(rui_root())
    stable()
    focus_scope("grid") {
        button("cell","One") { nav_id("one"); property("left","0px"); property("top","0px"); nav(model.mode); nav_up(nav_to(model.target)); on_click() { clicks+=1 } }
        button("cell","Two") { nav_id("two"); property("left","110px"); property("top","0px"); disabled() { return model.blocked } }
        button("cell","Three") { nav_id("three"); property("left","220px"); property("top","0px") }
        button("cell","Four") { nav_id("four"); property("left","0px"); property("top","65px"); property("visibility",model.hidden ? "hidden" : "visible") }
        button("cell","Five") { nav_id("five"); property("left","110px"); property("top","65px") }
        button("cell","Six") { nav_id("six"); property("left","220px"); property("top","65px") }
    }
    button("outside","Outside scroll region") { nav_id("outside"); nav() }
    text_input("input") { nav(UiNav.None); width(px(200)); height(px(30)) }
    box("custom") { tab_stop(); nav(UiNav.Vertical); text("custom_label","Focusable generic element"); on_click() { clicks+=10 } }
    column("scroll") {
        height(px(60)); width(px(220)); property("overflow-y","auto")
        button("scroll_first","First") { nav(UiNav.Vertical); height(px(50)); property("flex-shrink","0") }
        box("spacer") { height(px(150)); property("flex-shrink","0") }
        button("scroll_last","Last") { nav(UiNav.Vertical); height(px(50)); property("flex-shrink","0") }
    }
    document_content(model.popup,"items") {
        row() {
            button("popup_first","First") { nav(); nav_id("one"); nav_right(nav_to("two")); attribute("autofocus","") }
            button("popup_second","Second") { nav(); nav_id("two") }
        }
    }
}
def key(name:string) { rui_test_shortcut(name,0) }
def by_id(id:string):uint64 { return rui_document_element(rui_root(),id) }
[export]
def main(smoke:bool):int {
    var model=Model()
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Native navigation",800,600,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,800,600)); verify(rui_default_font())
        model.popup=open_template(@@popup_frame,"Popup",float2(400.,200.),UiDocumentOptions(visible=false))
        ui_legacy_frame() { scene(model) }
        let one=by_id("one"); let two=by_id("two"); let six=by_id("six")
        rui_focus(one); key("Right"); verify(rui_focused(two),"native spatial right")
        key("Down"); verify(rui_focused(by_id("five")),"native spatial down")
        key("Left"); verify(rui_focused(by_id("four")),"native spatial left")
        key("Down"); verify(rui_focused(by_id("four")),"auto stays inside nearest scroll container")
        model.blocked=true; model.hidden=true; ui_legacy_frame() { scene(model) }
        rui_focus(one); key("Right"); verify(rui_focused(by_id("three")),"auto skips disabled controls")
        rui_focus(by_id("five")); key("Left"); verify(!rui_focused(by_id("four")),"auto skips hidden controls")
        rui_focus(one); key("Up"); verify(rui_focused(six),"explicit ID overrides geometric direction")
        model.target="five"; ui_legacy_frame() { scene(model) }
        rui_focus(one); key("Up"); verify(rui_focused(by_id("five")),"reactive explicit target")
        model.mode=UiNav.Horizontal; ui_legacy_frame() { scene(model) }
        rui_focus(one); key("Down"); verify(rui_focused(one),"horizontal prevents vertical navigation")
        model.mode=UiNav.None; ui_legacy_frame() { scene(model) }
        rui_focus(one); key("Right"); verify(rui_focused(one),"none leaves focus")
        model.mode=UiNav.TreeOrder; ui_legacy_frame() { scene(model) }
        rui_focus(one); key("Down"); verify(rui_focused(by_id("three")),"tree-order follows DOM rather than geometry")
        rui_focus(six); key("Tab"); verify(rui_focused(one),"Tab remains trapped in focus_scope")
        model.mode=UiNav.Auto; ui_legacy_frame() { scene(model) }
        rui_focus(ui_find("scroll_first")); key("Down")
        verify(rui_focused(ui_find("scroll_last")) && rui_scroll_top(ui_find("scroll"))>0.,"native navigation scrolls selected item into view")
        let input=ui_find("input"); rui_value(input,"abcd"); rui_focus(input); rui_select(input,4,4); key("Left")
        verify(rui_focused(input) && rui_selection(input).x==3,"text cursor stays native")
        show_popup(model.popup,float2(400.,200.)); key("Right")
        verify(rui_focused(ui_find("popup_second")),"popup native navigation")
        key("Down"); verify(rui_contains(model.popup,rui_focus_node()),"popup cannot navigate to background document")
        hide_document(model.popup)
        rui_focus(one); key("Return"); ui_legacy_frame() { scene(model) }
        verify(clicks==1,"Enter activates navigable control")
        rui_focus(ui_find("custom")); key("Return"); ui_legacy_frame() { scene(model) }
        verify(clicks==11,"tab_stop enables activation of a generic element")
        unsafe { heap_collect(true,false) }
        ui_clear_stats(); ui_legacy_frame() { scene(model) }
        verify(reads==1 && ui_stats().updates==0 && by_id("one")==one,"navigation preserves handles and idle caching")
        verify(rui_warning_count()==0ul,"valid navigation produces no RCSS warnings")
        close_document(model.popup); ui_reset(); rui_shutdown()
        print("PASS: native nav modes, explicit IDs, disabled/hidden, scope, scroll, input cursor, popup, activation and caching\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
