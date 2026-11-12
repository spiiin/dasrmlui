options gen2
options persistent_heap
options gc
options stack = 65536
require examples/demo_host
require examples/showcase_style
require daslib/strings_convert

struct Cargo { id,zone:int; title,sprite_id:string }
struct Manifest { items:array<Cargo>; message:string="Drag a craft into a bay, or onto another craft to insert before it."; moves:int }
def bay_count(model:Manifest; zone:int):int {
    var count=0
    for (item in model.items) { if (item.zone==zone) { count+=1 } }
    return count
}
def drop_cargo(var model:Manifest; payload:string; zone,before:int) {
    let parsed=try_to_int(payload)
    if (!is_ok(parsed)) { return }
    let id=unwrap(parsed)
    if (id==before) { return }
    var source = -1
    for (i in range(length(model.items))) { if (model.items[i].id==id) { source=i } }
    if (source<0) { return }
    if (zone==1 && model.items[source].zone!=zone && bay_count(model,zone)>=2) {
        model.message="Flight deck is full. Return a craft to storage first."
        return
    }
    var moved=model.items[source]
    moved.zone=zone
    var reordered:array<Cargo>
    var inserted=false
    for (item in model.items) {
        if (item.id==id) { continue }
        if (item.id==before && item.zone==zone) { reordered |> push(moved); inserted=true }
        reordered |> push(item)
    }
    if (!inserted) { reordered |> push(moved) }
    model.items <- reordered
    model.moves+=1
    model.message="{moved.title} transferred / {model.moves} accepted drops"
}
[ui_style]
def cargo_style() {
    expedition_sprites(); showcase_controls()
    rule(part("shell")) { padding(px(32)); background(rgb(237,227,207)); color(rgb(44,52,44)); property("min-height","756px") }
    rule(part("heading")) { font_size(px(38)); margin_bottom(px(10)) }
    rule(part("caption")) { font_size(px(14)); color(rgb(94,106,87)); margin_bottom(px(24)) }
    rule(part("bay")) { width(px(480)); padding(px(20)); property("margin-right","24px"); background(rgb(247,243,231)); property("border","2px #bac3a7"); property("border-radius","12px") }
    rule(part("bay")+":drop, "+part("pad")+":drop") { background(rgb(208,233,185)); property("border-color","#547d39") }
    rule(part("cargo")) { padding(px(8)); height(px(68)); background(rgb(222,227,208)); margin_bottom(px(12)); property("border","2px #c1ccb0"); property("border-radius","8px"); property("cursor","move") }
    rule(part("cargo")+":drag") { opacity(0.8); background(rgb(178,210,150)); property("border-color","#527338") }
    rule(part("cargo")+":drop") { property("border-top","4px #527338") }
    rule(part("icon")) { width(px(68)); height(px(68)); property("margin-right","18px"); property("pointer-events","none") }
    rule(part("name")) { font_size(px(22)); property("pointer-events","none") }
    rule(part("pad")) { height(px(70)); padding(px(12)); property("border","2px #b6c2a4"); color(rgb(94,106,87)) }
    rule(part("status")) { padding(px(18)); margin_top(px(20)); background(rgb(55,76,49)); color(rgb(240,249,229)); property("border-radius","6px") }
}
[ui_component]
def cargo_bay(var model:Manifest; zone:int; title:string) {
    use_style(@@cargo_style)
    column("bay") {
        on_drop() $(payload:string) { drop_cargo(model,payload,zone,-1) }
        text("heading",title)
        text("caption",zone==1 ? "{bay_count(model,zone)} / 2 departure slots" : "Storage / no capacity limit")
        model.items |> each_keyed($(item:Cargo)=>item.id) $(item:Cargo) {
            when(item.zone==zone) {
                row("cargo") {
                    draggable("{item.id}")
                    on_drop() $(payload:string) { drop_cargo(model,payload,zone,item.id) }
                    sprite_image("icon",item.sprite_id)
                    text("name",item.title)
                }
            }
        }
        box(zone==0 ? "storage_drop" : "flight_drop") {
            property("height","70px"); padding(px(12)); property("border","2px #b6c2a4")
            text("caption","DROP HERE TO APPEND")
        }
    }
}
[ui_component]
def cargo_screen(var model:Manifest) {
    use_style(@@cargo_style)
    column("shell") {
        width(px(ui_width()-64.))
        text("heading","Field logistics")
        text("caption","Native RmlUi drag clones / keyed inventory / capacity rules")
        row() { property("align-items","flex-start"); cargo_bay(model,0,"Storage"); cargo_bay(model,1,"Flight deck") }
        text("status",model.message)
        text("outside","Dropping outside a bay cancels the transfer.")
    }
}
[export]
def main(smoke:bool):int {
    var model=Manifest()
    model.items |> push <| Cargo(id=0,zone=0,title="Kestrel scout",sprite_id="scout")
    model.items |> push <| Cargo(id=1,zone=0,title="Nomad rover",sprite_id="rover")
    model.items |> push <| Cargo(id=2,zone=0,title="Echo probe",sprite_id="probe")
    model.items |> push <| Cargo(id=3,zone=1,title="Atlas lander",sprite_id="cargo")
    var original=0ul
    return run_demo("dasrmlui - Field logistics","logs/drag_drop.png",smoke,$() { cargo_screen(model) }) $(frame:int) {
        if (frame==0) {
            rui_test_drag(ui_find("cargo",0),ui_find("flight_drop"))
        }
        elif (frame==1) { verify(model.moves==1 && bay_count(model,1)==2,"drop into bay"); rui_test_drag(ui_find("cargo",1),ui_find("flight_drop")) }
        elif (frame==2) { verify(model.moves==1 && bay_count(model,1)==2,"capacity rejects drop"); original=ui_find("cargo",2); rui_test_drag(original,ui_find("cargo",1)) }
        elif (frame==3) { verify(model.moves==2 && model.items[0].id==2 && ui_find("cargo",2)==original,"reorder preserves key"); rui_test_drag(ui_find("cargo",0),ui_find("storage_drop")) }
        elif (frame==4) { verify(model.moves==3 && bay_count(model,1)==1); rui_test_drag(ui_find("cargo",1),ui_find("outside")) }
        elif (frame==5) { verify(model.moves==3,"outside drop must cancel"); drop_cargo(model,"invalid",0,-1); verify(model.moves==3) }
        elif (frame==7) { print("PASS: native drag, reorder, capacity rejection, cancel\n") }
    }
}
