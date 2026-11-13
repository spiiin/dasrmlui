options gen2
options gc
options persistent_heap
options stack=65536
require dasrmlui/live
require daslib/algorithm

struct Root { text:string="initial"; ids:array<int>; number:int }
struct Local { value:int; notes:array<string> }
struct Old { count:int; caption:string }
struct Migrated { total:int; title:string="new default" }
def initial_root():Root {
    var initial=Root()
    initial.ids |> push(1); initial.ids |> push(2)
    return <- initial
}
var root_state=ui_state("test-root",initial_root())
var @live mounts=0
var frame=0
var local_values:table<int;int>
var original_window:uint64

def ui_migrate(saved:JsonValue const?; old_version:int; var value:Migrated):bool {
    if (old_version!=1) { return false }
    value.total=(saved?["count"] ?? 0)*2
    value.title=saved?["caption"] ?? value.title
    return true
}
[ui_component]
def child(id:int) {
    state("counter",Local()) $(var local:Local) {
        on_mount() { mounts+=1 }
        on_unmount() { live_store_string("test-unmounted","yes") }
        row() {
            text("count") { return "{local.value}" }
            button("plus","+") { on_click() { local.value+=id; local.notes |> push("alive") } }
        }
        local_values[id]=local.value
    }
}
[ui_component]
def screen(var model:Root) {
    column() {
        text("title") { return model.text }
        model.ids |> each_keyed($(id:int)=>id) $(id:int) { child(id) }
        native_element("probe","reload-probe") { width(px(20)); height(px(20)) }
    }
}
[export]
def init() {
    ui_live_window("Live reload tests",500,400)
    var old_id:string
    if (live_load_string("test-window",old_id)) { verify(old_id=="{rui_live_window_id()}","window survives context swap") }
    else { live_store_string("test-window","{rui_live_window_id()}") }
    register_native_element("reload-probe",@(event:UiNativeEvent) {
        if (event.kind==UiNativeKind.Destroy) { live_store_string("test-native-destroyed","yes") }
    },float2(20.,20.))
    // Exercise named serialization and an explicit schema migration.
    rt_live_save("migration",1,Old(count=21,caption="migrated"))
    var migrated=Migrated()
    rt_live_restore("migration",2,migrated)
    verify(migrated.total==42 && migrated.title=="migrated")
    delete migrated
}
[export]
def update() {
    ui_frame(root_state) $(var model:Root) { screen(model) }
    let generation=get_reload_generation()
    if (generation==0ul && !is_reload()) {
        if (frame==0) {
            ui_edit(root_state) $(var model:Root) { model.text="retained"; model.number=73; reverse(model.ids) }
            rui_test_click(ui_find("plus",1)); rui_test_click(ui_find("plus",2))
        } elif (frame==2) {
            verify(local_values[1]==1 && local_values[2]==2)
            unsafe { heap_collect(true,false) }
            request_reload(false)
        }
    } elif (generation==1ul && frame>0) {
        ui_read(root_state) $(model:Root) { verify(model.text=="retained" && model.number==73 && model.ids[0]==2) }
        verify(local_values[1]==1 && local_values[2]==2,"local keyed state survived reload")
        verify(mounts==4,"exactly one remount per child")
        var destroyed:string
        verify(live_load_string("test-unmounted",destroyed) && destroyed=="yes")
        verify(live_load_string("test-native-destroyed",destroyed) && destroyed=="yes")
        unsafe { heap_collect(true,false) }
        if (frame==1) { request_reload(true) }
    } elif (generation==2ul) {
        ui_read(root_state) $(model:Root) { verify(model.text=="initial" && model.number==0 && model.ids[0]==1) }
        verify(local_values[1]==0 && local_values[2]==0 && mounts==2,"full reload clears root, local and @live state")
        print("PASS: LiveHost root/local/keyed state, migration, GC, native cleanup, SDL window and full reset\n")
        request_exit()
    }
    frame+=1
}
