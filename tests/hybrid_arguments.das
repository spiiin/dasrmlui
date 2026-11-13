options gen2
options persistent_heap
options gc
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

// What keeps a screen off the full pass while nothing changes: arguments a
// component receives by value, primitives with computed arguments, and the
// cases that must still run on every frame because nothing reports them.
enum Tone { Calm, Loud }
struct Item { id:int; title:string }
struct Model { caption:string="Stock"; total:int=3; ratio:float=0.25; wide:bool; flagged:bool; rows:array<Item> }
var external="outside"
var badge_bodies, row_bodies, screen_bodies : int

def external_caption():string { return external }

[ui_component]
def badge(caption:string; count:int; tone:Tone; compact:bool) {
    badge_bodies += 1
    box("badge") {
        text("badge_caption",caption)
        text("badge_count",count)
        text("badge_tone") { return tone==Tone.Loud ? "loud" : "calm" }
        if (compact) { text("badge_compact","compact") }
    }
}
// An argument handed on is covered through both call sites.
[ui_component]
def forwarder(caption:string; count:int) {
    badge(caption,count,Tone.Calm,false)
}
// A row is the same storage as the model's: its fields stay precise bindings.
[ui_component]
def row_view(item:Item; position:int) {
    row_bodies += 1
    row("row") {
        text("row_title",item.title)
        text("row_position",position)
        draggable("{item.id}")
    }
}
[ui_component]
def item_card(item:Item) { text("card_title",item.title) }

[ui_action]
def rename(var model:Model; value:string) { model.caption=value }
[ui_action]
def recount(var model:Model; value:int) { model.total=value }
[ui_action]
def retitle(var model:Model; index:int; value:string) { model.rows[index].title=value }
[ui_action]
def fill(var model:Model; value:float) { model.ratio=value }
[ui_action]
def widen(var model:Model; value:bool) { model.wide=value }
[ui_action]
def mark(var model:Model; value:bool) { model.flagged=value }

[ui_component]
def screen(var model:Model) {
    screen_bodies += 1
    column("screen") {
        badge(model.caption,model.total,Tone.Loud,true)
        badge("{model.caption}!",model.total*2,Tone.Calm,false)
        forwarder(model.caption,7)
        item_card(Item(id=1,title="copy of {model.caption}"))
        box(model.wide ? "wide" : "narrow") {
            pseudo_if("flagged",model.flagged)
            progress_bar("fill",model.ratio)
        }
        model.rows |> each_keyed($(item:Item)=>item.id) $(item:Item) { row_view(item,item.id*10) }
    }
}

// Nothing vouches for these arguments, so each keeps the pass on every frame.
[ui_component]
def opaque_parent(model:Model) { badge(external_caption(),model.total,Tone.Calm,false) }
def plain_helper(count:int) { badge("helper",count,Tone.Calm,false) }
[ui_component]
def helper_parent(model:Model) { plain_helper(model.total) }
[ui_component]
def local_parent(model:Model) {
    let doubled=model.total*2
    badge("local",doubled,Tone.Calm,false)
}

// A plain helper whose body only sets properties from its arguments is
// transparent to the annotation; one that reads a global is not.
var accent=10
def card_look(size:int) { width(px(size)); if (size>40) { padding(px(4)) } }
def global_look() { padding(px(accent)) }
[ui_component]
def styled(model:Model) { box("styled") { card_look(model.total*10) } }
[ui_component]
def global_styled(model:Model) { box("global_styled") { global_look() } }

def has(text:string):bool { return find(rui_markup(),text)>=0 }

[export]
def main(smoke:bool):int {
    var model=Model()
    model.rows |> push(Item(id=1,title="first")); model.rows |> push(Item(id=2,title="second"))
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("hybrid arguments",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480)); verify(rui_default_font())

        rt_hybrid_frame(model) { screen(model) }
        verify(has(">Stock<") && has(">3<") && has(">Stock!<") && has(">6<") && has(">7<"))
        verify(has(">loud<") && has(">calm<") && has(">compact<") && has(">copy of Stock<") && has(">10<") && has(">20<"))
        var epoch=rui_hybrid_epoch()
        var bodies=badge_bodies+row_bodies+screen_bodies
        for (i in range(5)) { rt_hybrid_frame(model) { screen(model) } }
        verify(rui_hybrid_epoch()==epoch && badge_bodies+row_bodies+screen_bodies==bodies,
            "By-value arguments and computed primitive arguments must not keep the full pass")

        // A field of a row passed by reference is still a native binding.
        retitle(model,0,"renamed"); rt_hybrid_frame(model) { screen(model) }
        verify(has(">renamed<") && rui_hybrid_epoch()==epoch,"A row passed by reference must update without a pass")

        // The source of a copied argument changes: one pass, every copy follows.
        rename(model,"Depot"); rt_hybrid_frame(model) { screen(model) }
        verify(rui_hybrid_epoch()!=epoch,"A write to the source of a by-value argument must run a pass")
        verify(has(">Depot<") && has(">Depot!<") && has(">copy of Depot<") && !has("Stock"),"Every copy of the argument must follow its source")
        recount(model,5); rt_hybrid_frame(model) { screen(model) }
        verify(has(">5<") && has(">10<") && !has(">3<") && !has(">6<"))
        epoch=rui_hybrid_epoch()
        for (i in range(5)) { rt_hybrid_frame(model) { screen(model) } }
        verify(rui_hybrid_epoch()==epoch,"The screen must be idle again after the pass")

        // Computed arguments of primitives are dependencies, not a standing pass.
        let bar=ui_find("fill")
        verify(rui_get_attr(bar,"value")=="0.25")
        fill(model,0.75); rt_hybrid_frame(model) { screen(model) }
        verify(rui_get_attr(bar,"value")=="0.75" && ui_find("fill")==bar)
        let holder=ui_find("narrow")
        verify(holder!=0ul && ui_find("wide")==0ul)
        widen(model,true); rt_hybrid_frame(model) { screen(model) }
        verify(ui_find("wide")==holder && ui_find("narrow")==0ul && rui_has_class(holder,"__wide") && !rui_has_class(holder,"__narrow"),
            "A computed part name must follow its source")
        epoch=rui_hybrid_epoch()
        mark(model,true); rt_hybrid_frame(model) { screen(model) }
        verify(rui_hybrid_epoch()!=epoch,"A write to the source of pseudo_if must run a pass")
        epoch=rui_hybrid_epoch()
        for (i in range(5)) { rt_hybrid_frame(model) { screen(model) } }
        verify(rui_hybrid_epoch()==epoch)
        verify(rui_warning_count()==0ul)

        // A root component is called by the frame, which analyses nothing.
        ui_reset()
        rt_hybrid_frame(model) { badge(external,1,Tone.Calm,false) }
        external="changed"
        rt_hybrid_frame(model) { badge(external,1,Tone.Calm,false) }
        verify(has(">changed<"),"An argument nobody vouches for must be read again on every frame")

        ui_reset()
        rt_hybrid_frame(model) { opaque_parent(model) }
        external="opaque refreshed"
        rt_hybrid_frame(model) { opaque_parent(model) }
        verify(has(">opaque refreshed<"),"An argument that cannot be followed keeps the pass")

        ui_reset()
        rt_hybrid_frame(model) { helper_parent(model) }
        recount(model,8); rt_hybrid_frame(model) { helper_parent(model) }
        verify(has(">8<"),"A component mounted by a plain helper is not covered")

        ui_reset()
        rt_hybrid_frame(model) { local_parent(model) }
        recount(model,9); rt_hybrid_frame(model) { local_parent(model) }
        verify(has(">18<"),"A local passed as an argument keeps the conservative pass")

        ui_reset()
        rt_hybrid_frame(model) { styled(model) }
        let card=ui_find("styled")
        verify(rui_local_property(card,"width")=="90px" && rui_local_property(card,"padding-top")=="4px")
        epoch=rui_hybrid_epoch()
        for (i in range(5)) { rt_hybrid_frame(model) { styled(model) } }
        verify(rui_hybrid_epoch()==epoch,"A helper that only styles from its arguments must not keep the pass")
        recount(model,3); rt_hybrid_frame(model) { styled(model) }
        verify(rui_local_property(card,"width")=="30px","A transparent helper must follow the source of its argument")

        ui_reset()
        rt_hybrid_frame(model) { global_styled(model) }
        accent=20
        rt_hybrid_frame(model) { global_styled(model) }
        verify(rui_local_property(ui_find("global_styled"),"padding-top")=="20px","A helper that reads a global keeps the pass")

        verify(rui_warning_count()==0ul)
        ui_reset(); rui_shutdown()
        print("PASS: covered by-value arguments, forwarded and temporary arguments, computed primitive arguments, transparent helpers, conservative fallbacks\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
