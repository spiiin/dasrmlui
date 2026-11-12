options gen2
options persistent_heap
options gc
options stack = 65536
require examples/demo_host
require examples/workbench_style
require math
require strings

struct Asset { id:int; title:string; stock:int; price:float; active:bool = true; group:string = "Design" }
struct Catalog { query:string; selected:int = 1; revision:int; editing:bool }
var assets : array<Asset>
var groups : array<UiOption>
var editor_mounts, editor_unmounts : int

def filtered(query:string; revision:int) : array<Asset> {
    var result : array<Asset>
    for (asset in assets) {
        if (empty(query) || find(asset.title,query) >= 0) { result |> push_clone(asset) }
    }
    return <- result
}
def asset_at(id:int; revision:int) : Asset { return assets[id-1] }

[ui_component]
def asset_editor(var model:Catalog) {
    use_style(@@catalog_style)
    state(asset_at(model.selected,model.revision)) $(var draft:Asset) {
        on_mount() { editor_mounts += 1; request_focus("title") }
        on_unmount() { editor_unmounts += 1 }
        box("shade") {}
        focus_scope("dialog") {
            text("eyebrow","EDIT ASSET / #{draft.id}")
            text("section","Prepare your next release")
            text("muted","Tab stays in this panel. Enter commits numbers; Escape cancels a field draft.")
            flow("editor_fields",850.0) {
                column() {
                    width(px(ui_width() < 850.0 ? 280.0 : 350.0))
                    text("muted","Title / at least 3 characters")
                    text_input("title") {
                        bind_edit(draft.title,"change",$(value:string):string {
                            return length(value) < 3 ? "At least 3 characters" : ""
                        }) $(value:string) { draft.title=value }
                    }
                    text("error") { return field_error("title") }
                    text("muted","Units / whole number 0-10000, commit with Enter")
                    text_input("stock") {
                        bind_int(draft.stock,0,10000,"Enter") $(value:int) { draft.stock=value }
                    }
                    text("error") { return field_error("stock") }
                }
                column() {
                    text("muted","Price / commit when leaving the field")
                    text_input("price") {
                        bind_float(draft.price,0.0,10000.0,"blur") $(value:float) { draft.price=value }
                    }
                    text("error") { return field_error("price") }
                    text("muted","Collection")
                    select_input("field") {
                        select_options(groups)
                        bind_value(draft.group) $(value:string) { draft.group=value }
                    }
                    row() {
                        checkbox("check") { bind_checked(draft.active) $(value:bool) { draft.active=value } }
                        text("muted","Available for download")
                    }
                }
            }
            row() {
                margin_top(px(16))
                button("save","Save asset") {
                    disabled() { return !empty(field_error("title")) || !empty(field_error("stock")) || !empty(field_error("price")) || field_pending("stock") }
                    on_click() { assets[draft.id-1] = draft; model.revision += 1; model.editing=false }
                }
                button("cancel","Cancel") { on_click() { model.editing=false } }
            }
        }
    }
}
[ui_component]
def catalog(var model:Catalog) {
    use_style(@@catalog_style)
    computed(filtered(model.query,model.revision)) $(visible:array<Asset>) {
        column("shell") {
            width(px(max(320.0,ui_width()-56.0)))
            text("eyebrow","NORTHSTAR / ASSET LIBRARY")
            text("heading","A place for everything")
            text("muted","5,000 assets. Search the library, scroll to explore, or open an asset to edit its details.")
            flow("workspace",900.0) {
                column("card") {
                    width(px(ui_width() < 900.0 ? max(280.0,ui_width()-96.0) : ui_width()-440.0))
                    margin_right(px(16))
                    text_input("search") {
                        width(pct(94)); padding(px(12)); margin_bottom(px(12))
                        bind_value(model.query) $(value:string) { model.query=value }
                    }
                    text("muted","{length(visible)} assets / search by title")
                    virtual_each("assets",visible,54.0,max(180.0,ui_height()-(ui_width() < 900.0 ? 560.0 : 310.0)),$(asset:Asset) => asset.id) $(asset:Asset) {
                        button("asset","#{asset.id}   {asset.title}     /     {asset.group}") {
                            on_click() { model.selected=asset.id }
                        }
                    }
                }
                column("inspector") {
                    width(px(ui_width() < 900.0 ? max(280.0,ui_width()-96.0) : 288.0))
                    text("eyebrow","SELECTED ASSET")
                    text("section") { return asset_at(model.selected,model.revision).title }
                    text("muted") { return "Reference  /  NS-{model.selected}" }
                    text("muted") { return "Collection  /  {asset_at(model.selected,model.revision).group}" }
                    text("muted") { return "Available units  /  {asset_at(model.selected,model.revision).stock}" }
                    text("muted") { return "Price  /  EUR {asset_at(model.selected,model.revision).price:.2f}" }
                    button("edit","Edit details") { on_click() { model.editing=true } }
                    text("muted","Resize the window to move these details beneath the library.")
                    button("jump","Jump to item 2500") { on_click() { rui_scroll_to(ui_find("assets"),2498.0*54.0) } }
                }
            }
            when(model.editing) { asset_editor(model) }
        }
    }
}
[export]
def main(smoke:bool):int {
    for (i in range(1,5001)) {
        assets |> push <| Asset(id=i,title="Studio asset {i}",stock=10+i%90,price=12.5+float(i%40),group=i%2 == 0 ? "Design" : "Audio")
    }
    groups |> push <| UiOption(value="Design",caption="Design")
    groups |> push <| UiOption(value="Audio",caption="Audio")
    groups |> push <| UiOption(value="Video",caption="Video")
    var model=Catalog()
    return run_demo("dasrmlui - Asset library","logs/catalog.png",smoke,$() { catalog(model) }) $(frame:int) {
        if (frame == 0) { rui_test_click(ui_find("jump")) }
        elif (frame == 1) { verify(ui_find("asset",2500) != 0ul); rui_test_click(ui_find("asset",2500)) }
        elif (frame == 2) { verify(model.selected == 2500); rui_test_click(ui_find("edit")) }
        elif (frame == 3) {
            verify(rui_focused(ui_find("title")) && editor_mounts == 1)
            rui_test_event(ui_find("title"),"change","Updated asset")
        }
        elif (frame == 4) { rui_test_click(ui_find("save")) }
        elif (frame == 5) {
            verify(assets[2499].title == "Updated asset" && editor_unmounts == 1 && rui_focused(ui_find("edit")))
            rui_test_resize(720,820)
        }
        elif (frame == 6) {
            verify(ui_width() == 720.0)
            rui_test_event(ui_find("search"),"change","Updated")
        }
        elif (frame == 7) { verify(ui_find("asset",2500) != 0ul && ui_find("asset",2499) == 0ul) }
    }
}
