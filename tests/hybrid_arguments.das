options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

// What keeps a screen off the full pass while nothing changes: arguments a
// component receives by value, primitives with computed arguments, and the
// cases that must still run on every frame because nothing reports them.
enum Tone { Calm, Loud }
struct Item { id:int; title:string }
struct Model { caption:string="Stock"; total:int=3; ratio:float=0.25; wide:bool; flagged:bool; rows:array<Item>; ids:array<int>; picked:int }
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

// An argument computed by a call that reads nothing of the component is an
// opaque getter: read again by every pass, refreshed when a change is reported.
[ui_component]
def opaque_parent(model:Model) { badge(external_caption(),model.total,Tone.Calm,false) }
// Nothing vouches for these arguments, so each keeps the pass on every frame.
def plain_helper(count:int) { badge("helper",count,Tone.Calm,false) }
[ui_component]
def helper_parent(model:Model) { plain_helper(model.total) }
[ui_component]
def local_parent(model:Model) {
    let doubled=model.total*2
    badge("local",doubled,Tone.Calm,false)
}

// A plain helper whose body only sets properties from its arguments is
// transparent to the annotation. A global it reads is tracked at the call site.
var accent=10
[ui_action]
def set_accent(value:int) { accent=value }
def card_look(size:int) { width(px(size)); if (size>40) { padding(px(4)) } }
def global_look() { padding(px(accent)) }
[ui_component]
def styled(model:Model) { box("styled") { card_look(model.total*10) } }
[ui_component]
def global_styled(model:Model) { box("global_styled") { global_look() } }

// class_if on a plain field is a native view; it must set the class the style selects.
[ui_style]
def chip_style() {
    rule(part("chip")) { display("block"); width(px(40)); height(px(10)) }
    part("chip") |> with_class("on") |> rule() { width(px(120)) }
}
[ui_component]
def chip(model:Model) {
    use_style(@@chip_style)
    box("chip") { class_if("on",model.flagged) }
}

// A slot and a component event are blocks written in the caller, where the
// annotation has already seen what they read.
var picked = -1
[ui_component]
def frame_with_slot(title:string; content:block) {
    column("frame") {
        text("frame_title",title)
        slot(content)
    }
}
[ui_component]
def pick_row(item:Item; chosen:block<(id:int):void>) {
    button("pick","Pick") { on_click() { emit(chosen,item.id) } }
}
[ui_component]
def slotted(var model:Model) {
    frame_with_slot("Frame {model.total}") {
        text("slot_caption",model.caption)
        text("slot_computed","{model.caption}?")
        model.rows |> each_keyed($(item:Item)=>item.id) $(item:Item) {
            pick_row(item) $(id:int) { picked=id }
        }
    }
}
// The same component called by code the annotation has not seen.
def plain_slot_caller() { frame_with_slot(external) { text("plain-site","plain_slot",external) } }
[ui_component]
def slot_from_helper(model:Model) { plain_slot_caller() }

// An item of a list of scalars and the value of computed reach their blocks
// as copies; the list watches the element, computed changes only in a pass.
[ui_action]
def set_id(var model:Model; index,value:int) { model.ids[index]=value }
[ui_action]
def add_id(var model:Model; value:int) { model.ids |> push(value) }
[ui_component]
def id_chip(id:int) { text("chip_id",id) }
[ui_component]
def id_list(var model:Model) {
    computed(model.total*3) $(tripled:int) {
        column("ids") {
            text("tripled",tripled)
            text("tripled_text","x{tripled}")
            model.ids |> each_keyed($(id:int)=>id) $(id:int) {
                id_chip(id)
                text("id_text","#{id}")
            }
        }
    }
}
// A binding to an indexed element follows what the index reads.
[ui_action]
def pick(var model:Model; index:int) { model.picked=index }
[ui_component]
def picker(var model:Model) {
    column("picker") {
        text("picked_index",model.picked)
        text("picked_title",model.rows[model.picked].title)
        text_input("picked_edit") { bind_value(model.rows[model.picked].title) $(value:string) { model.rows[model.picked].title=value } }
    }
}

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
        external="opaque"
        rt_hybrid_frame(model) { opaque_parent(model) }
        epoch=rui_hybrid_epoch()
        external="opaque changed"
        for (i in range(3)) { rt_hybrid_frame(model) { opaque_parent(model) } }
        verify(rui_hybrid_epoch()==epoch && has(">opaque<"),"An opaque getter must not ask for a pass on every frame")
        ui_changed(external); rt_hybrid_frame(model) { opaque_parent(model) }
        verify(has(">opaque changed<"),"A reported change must refresh an opaque getter")

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
        epoch=rui_hybrid_epoch()
        for (i in range(3)) { rt_hybrid_frame(model) { global_styled(model) } }
        verify(rui_hybrid_epoch()==epoch,"A helper that reads a global must not keep the pass")
        set_accent(20); rt_hybrid_frame(model) { global_styled(model) }
        verify(rui_local_property(ui_find("global_styled"),"padding-top")=="20px","A tracked write to a global read by a helper must be reported")
        accent=30
        rt_hybrid_frame(model) { global_styled(model) }
        verify(rui_local_property(ui_find("global_styled"),"padding-top")=="20px","A write nobody reported is not seen")
        ui_changed(accent); rt_hybrid_frame(model) { global_styled(model) }
        verify(rui_local_property(ui_find("global_styled"),"padding-top")=="30px","ui_changed must report a write made elsewhere")

        ui_reset()
        mark(model,false)
        rt_hybrid_frame(model) { chip(model) }
        let switch=ui_find("chip")
        verify(rui_bounds(switch).z==40.)
        epoch=rui_hybrid_epoch()
        mark(model,true); rt_hybrid_frame(model) { chip(model) }
        verify(rui_bounds(switch).z==120.,"class_if on a field must set the class that with_class selects")
        verify(rui_hybrid_epoch()==epoch,"class_if on a field must update without a pass")
        mark(model,false); rt_hybrid_frame(model) { chip(model) }
        verify(rui_bounds(switch).z==40.)

        ui_reset()
        rename(model,"Slot"); recount(model,4)
        rt_hybrid_frame(model) { slotted(model) }
        verify(has(">Frame 4<") && has(">Slot<") && has(">Slot?<"))
        epoch=rui_hybrid_epoch()
        for (i in range(5)) { rt_hybrid_frame(model) { slotted(model) } }
        verify(rui_hybrid_epoch()==epoch,"A slot and a component event must not keep the full pass")
        rename(model,"Slot renamed"); rt_hybrid_frame(model) { slotted(model) }
        verify(has(">Slot renamed<") && has(">Slot renamed?<"),"Slot content must follow what it reads")
        recount(model,6); rt_hybrid_frame(model) { slotted(model) }
        verify(has(">Frame 6<"),"A computed argument beside a slot must follow its source")
        rui_test_click(ui_find("pick",2)); rt_hybrid_frame(model) { slotted(model) }
        verify(picked==2,"A component event must reach the caller's block")
        epoch=rui_hybrid_epoch()
        for (i in range(5)) { rt_hybrid_frame(model) { slotted(model) } }
        verify(rui_hybrid_epoch()==epoch)

        ui_reset()
        external="slot outside"
        rt_hybrid_frame(model) { slot_from_helper(model) }
        external="slot refreshed"
        rt_hybrid_frame(model) { slot_from_helper(model) }
        verify(rui_inner_markup(ui_find("plain_slot"))=="slot refreshed","A block from a caller nobody analysed keeps the pass")

        ui_reset()
        recount(model,3)
        add_id(model,11); add_id(model,12)
        rt_hybrid_frame(model) { id_list(model) }
        verify(has(">9<") && has(">x9<") && has(">11<") && has(">#11<") && has(">12<"))
        epoch=rui_hybrid_epoch()
        for (i in range(5)) { rt_hybrid_frame(model) { id_list(model) } }
        verify(rui_hybrid_epoch()==epoch,"Items of a list of scalars and a computed value must not keep the pass")
        set_id(model,0,21); rt_hybrid_frame(model) { id_list(model) }
        verify(has(">21<") && has(">#21<") && !has(">11<"),"A write to an element of a list of scalars must renew its copies")
        add_id(model,13); rt_hybrid_frame(model) { id_list(model) }
        verify(has(">13<") && has(">#13<"))
        recount(model,5); rt_hybrid_frame(model) { id_list(model) }
        verify(has(">15<") && has(">x15<") && !has(">x9<"),"A computed value must follow its dependencies")
        epoch=rui_hybrid_epoch()
        for (i in range(5)) { rt_hybrid_frame(model) { id_list(model) } }
        verify(rui_hybrid_epoch()==epoch)

        ui_reset()
        retitle(model,0,"zero"); retitle(model,1,"one")
        rt_hybrid_frame(model) { picker(model) }
        verify(has(">zero<") && !has(">one<") && rui_get_value(ui_find("picked_edit"))=="zero")
        epoch=rui_hybrid_epoch()
        for (i in range(5)) { rt_hybrid_frame(model) { picker(model) } }
        verify(rui_hybrid_epoch()==epoch,"An indexed binding must not keep the pass")
        retitle(model,0,"zero renamed"); rt_hybrid_frame(model) { picker(model) }
        verify(has(">zero renamed<") && rui_hybrid_epoch()==epoch,"The selected element must update without a pass")
        pick(model,1); rt_hybrid_frame(model) { picker(model) }
        verify(has(">one<") && !has(">zero renamed<") && rui_get_value(ui_find("picked_edit"))=="one","A change of the index must select the element again")
        retitle(model,0,"zero again"); rt_hybrid_frame(model) { picker(model) }
        verify(!has(">zero again<") && has(">one<"),"The element left behind must no longer be shown")
        rui_test_event(ui_find("picked_edit"),"change","one edited"); rt_hybrid_frame(model) { picker(model) }
        verify(model.rows[1].title=="one edited" && has(">one edited<"),"An indexed input must write the selected element")

        verify(rui_warning_count()==0ul)
        ui_reset(); rui_shutdown()
        print("PASS: covered by-value arguments, forwarded and temporary arguments, computed primitive arguments, transparent helpers, scoped class_if, slots and component events, copied block parameters, indexed bindings, conservative fallbacks\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
