options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

// Removing elements forgets exactly what goes away, and an event costs one
// pass: the bookkeeping behind both, checked on a list of bound rows.
struct Item { id:int; title:string }
struct Model { caption:string="List"; clicks:int; rows:array<Item> }
var screen_bodies : int

[ui_component]
def row_view(item:Item) {
    row("row") {
        text("row_title",item.title)
        text("row_key",item.id)
    }
}
[ui_action]
def fill(var model:Model; count:int) {
    for (i in range(count)) { model.rows |> push(Item(id=i+1,title="row {i+1}")) }
}
[ui_action]
def drop_even(var model:Model) {
    var index=length(model.rows)-1
    while (index>=0) {
        if (model.rows[index].id%2==0) { model.rows |> erase(index) }
        index -= 1
    }
}
[ui_action]
def drop_all(var model:Model) { model.rows |> clear() }
[ui_action]
def retitle(var model:Model; index:int; value:string) { model.rows[index].title=value }

[ui_component]
def screen(var model:Model) {
    screen_bodies += 1
    column("screen") {
        text("caption",model.caption)
        text("clicks",model.clicks)
        button("count","Count") { on_click() { model.clicks += 1 } }
        button("append","Append") { on_click() { model.rows |> push(Item(id=1000+length(model.rows),title="appended")) } }
        model.rows |> each_keyed($(item:Item)=>item.id) $(item:Item) { row_view(item) }
    }
}

def has(text:string):bool { return find(rui_markup(),text)>=0 }

[export]
def main(smoke:bool):int {
    var model=Model()
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("hybrid removal",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480)); verify(rui_default_font())

        rt_hybrid_frame(model) { screen(model) }
        let fixed=rui_hybrid_live() // the caption and the counter
        verify(fixed==2)
        fill(model,200); rt_hybrid_frame(model) { screen(model) }
        verify(rui_hybrid_live()==fixed+400)
        let capacity=rui_hybrid_capacity()
        let odd=ui_find("row",1); let even=ui_find("row",2); let last=ui_find("row",199)
        verify(odd!=0ul && even!=0ul && last!=0ul)

        // Half of the rows go away in one pass; the others keep their elements.
        drop_even(model); rt_hybrid_frame(model) { screen(model) }
        verify(!rui_alive(even) && ui_find("row",2)==0ul,"A removed row must be gone")
        verify(rui_alive(odd) && ui_find("row",1)==odd && ui_find("row",199)==last,"A surviving row must keep its element")
        verify(rui_hybrid_live()==fixed+200,"Bindings of removed rows must be retired, the others kept")
        verify(has(">row 199<") && !has(">row 200<"))

        // The survivors are still precise bindings.
        var epoch=rui_hybrid_epoch()
        retitle(model,0,"first renamed"); rt_hybrid_frame(model) { screen(model) }
        verify(has(">first renamed<") && rui_hybrid_epoch()==epoch,"A surviving row must update without a pass")

        // Everything goes away; the slots are reused by the next rows.
        drop_all(model); rt_hybrid_frame(model) { screen(model) }
        verify(!rui_alive(odd) && !rui_alive(last) && rui_hybrid_live()==fixed && !has(">row "))
        fill(model,200); rt_hybrid_frame(model) { screen(model) }
        verify(rui_hybrid_live()==fixed+400 && rui_hybrid_capacity()==capacity,"Retired slots must be reused")
        verify(ui_find("row",1)!=0ul && has(">row 200<"))
        retitle(model,199,"last renamed"); rt_hybrid_frame(model) { screen(model) }
        verify(has(">last renamed<"),"New rows must be bound")
        // Collection by volume: over the threshold it collects, under it it does not.
        verify(ui_collect_garbage(0),"A zero threshold must collect")
        verify(!ui_collect_garbage(1024),"Nothing has grown by a gigabyte since the last collection")
        verify(ui_collect_garbage(1024,true),"A forced collection must run")
        rt_hybrid_frame(model) { screen(model) }
        verify(has(">last renamed<") && ui_find("row",1)!=0ul,"The screen must survive a collection")

        // One event, one pass: the handler's write is shown by the pass that follows it.
        for (i in range(3)) { rt_hybrid_frame(model) { screen(model) } }
        epoch=rui_hybrid_epoch()
        rui_test_click(ui_find("count")); rt_hybrid_frame(model) { screen(model) }
        verify(model.clicks==1 && has(">1<"))
        verify(rui_hybrid_epoch()==epoch+1ul,"An event must cost one pass, not two")
        epoch=rui_hybrid_epoch()
        rui_test_click(ui_find("append")); rt_hybrid_frame(model) { screen(model) }
        verify(length(model.rows)==201 && has(">appended<"),"A structural change made by a handler must be shown in the same frame")
        verify(rui_hybrid_epoch()==epoch+1ul)
        // Two events in one frame are still two passes, in arrival order.
        epoch=rui_hybrid_epoch()
        rui_test_click(ui_find("count")); rui_test_click(ui_find("count")); rt_hybrid_frame(model) { screen(model) }
        verify(model.clicks==3 && has(">3<") && rui_hybrid_epoch()==epoch+2ul)
        epoch=rui_hybrid_epoch()
        let bodies=screen_bodies
        for (i in range(3)) { rt_hybrid_frame(model) { screen(model) } }
        verify(rui_hybrid_epoch()==epoch && screen_bodies==bodies,"The screen must be idle after the events")

        verify(rui_warning_count()==0ul)
        ui_reset(); verify(rui_hybrid_live()==0)
        rui_shutdown()
        print("PASS: removal of bound rows, survivors, slot reuse, one pass per event\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
