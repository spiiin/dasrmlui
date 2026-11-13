options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

// A global that a component reads is tracked like the model: writes rewritten
// by the annotations report themselves, any other is one ui_changed away. An
// opaque getter is refreshed by a reported change, not by a pass on every frame.
struct Member { id:int; name:string; active:bool }
struct Model { title:string="Crew" }
var crew : array<Member>
var show_roster = true
var counter = 0
var outside = "outside"

def outside_text():string { return outside }

[ui_action]
def enlist(id:int; name:string) { crew |> push(Member(id=id,name=name,active=true)) }
[ui_action]
def rename(index:int; name:string) { crew[index].name=name }
[ui_action]
def discharge(index:int) { crew |> erase(index) }
[ui_action]
def roster(visible:bool) { show_roster=visible }

[ui_component]
def member_row(member:Member) {
    row("member") { text("member_name",member.name) }
}
[ui_component]
def screen(model:Model) {
    column("screen") {
        text("title",model.title)
        text("summary","{length(crew)} aboard")
        text("counter",counter)
        text("getter") { return outside_text() }
        button("count","Count") { on_click() { counter += 1 } }
        if (show_roster) {
            crew |> each_keyed($(member:Member)=>member.id) $(member:Member) { member_row(member) }
        }
    }
}

// Nothing here depends on the list as a whole, so a row stays a precise binding.
[ui_component]
def roster_only(model:Model) {
    column("roster") {
        crew |> each_keyed($(member:Member)=>member.id) $(member:Member) { member_row(member) }
    }
}

def has(text:string):bool { return find(rui_markup(),text)>=0 }
def frames(model:Model; count:int) {
    for (i in range(count)) { rt_hybrid_frame(model) { screen(model) } }
}

[export]
def main(smoke:bool):int {
    var model=Model()
    enlist(1,"Ada"); enlist(2,"Bo"); enlist(3,"Cy")
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("hybrid globals",640,480,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,640,480)); verify(rui_default_font())

        frames(model,1)
        verify(has(">Ada<") && has(">Cy<") && has(">3 aboard<") && has(">0<") && has(">outside<"))
        var epoch=rui_hybrid_epoch()
        frames(model,5)
        verify(rui_hybrid_epoch()==epoch,"A list over a global, a global in a condition and an opaque getter must not keep the pass")

        // A row of a global array is storage like a row of the model. The summary
        // depends on the whole list, so here the write also runs a pass.
        let first=ui_find("member",1)
        rename(0,"Ada L."); frames(model,1)
        verify(has(">Ada L.<") && ui_find("member",1)==first,"A tracked write to a row of a global list must be shown")

        // Structure of the global, and an expression that reads it.
        enlist(4,"Dan"); frames(model,1)
        verify(has(">Dan<") && has(">4 aboard<") && rui_hybrid_epoch()!=epoch,"A push into a global list must run a pass")
        discharge(0); frames(model,1)
        verify(!has(">Ada L.<") && has(">3 aboard<") && !rui_alive(first))
        roster(false); frames(model,1)
        verify(!has(">Bo<") && ui_find("member",2)==0ul,"A global in a condition must be followed")
        roster(true); frames(model,1)
        verify(has(">Bo<") && has(">Dan<"))

        // A write the annotations did not see, then reported.
        epoch=rui_hybrid_epoch()
        crew[0].name="Bo renamed"
        frames(model,2)
        verify(!has(">Bo renamed<") && rui_hybrid_epoch()==epoch,"A write nobody reported is not seen")
        ui_changed(crew[0].name); frames(model,1)
        verify(has(">Bo renamed<"),"ui_changed must report a write made elsewhere")
        crew |> push(Member(id=9,name="Eve",active=true))
        ui_changed(crew); frames(model,1)
        verify(has(">Eve<") && has(">4 aboard<"),"ui_changed on a global list must run a pass")

        // An opaque getter waits for a reported change.
        epoch=rui_hybrid_epoch()
        outside="elsewhere"
        frames(model,3)
        verify(has(">outside<") && rui_hybrid_epoch()==epoch,"An opaque getter must not ask for a pass on every frame")
        ui_changed(outside); frames(model,1)
        verify(has(">elsewhere<"),"A reported change must refresh an opaque getter")

        // A handler writes a global scalar that is bound natively.
        rui_test_click(ui_find("count")); frames(model,1)
        verify(counter==1 && has(">1<"),"A global assigned by a handler must be reported")
        epoch=rui_hybrid_epoch()
        frames(model,5)
        verify(rui_hybrid_epoch()==epoch)

        // Without anything that reads the whole list, a row updates without a pass.
        ui_reset()
        rt_hybrid_frame(model) { roster_only(model) }
        epoch=rui_hybrid_epoch()
        rename(1,"precise"); rt_hybrid_frame(model) { roster_only(model) }
        verify(has(">precise<") && rui_hybrid_epoch()==epoch,"A field of a global row must update without a pass")
        crew[1].name="reported"; ui_changed(crew[1].name); rt_hybrid_frame(model) { roster_only(model) }
        verify(has(">reported<") && rui_hybrid_epoch()==epoch,"ui_changed on a bound field must update it without a pass")

        verify(rui_warning_count()==0ul)
        ui_reset(); rui_shutdown()
        print("PASS: tracked global list, rows, conditions and scalars, reported writes, opaque getter\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
