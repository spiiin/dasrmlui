options gen2
options persistent_heap
options gc
options stack=65536
require examples/demo_host
require examples/data_models_style
require strings

struct Cargo { code:string; name:string; crates:int; destination:string; priority:bool }
struct Voyage { name:string="Northbound / 08"; captain:string="Mara Jensen"; port:string="Rotterdam"; hour:int=14; ready:bool=false }
struct Harbour { model:UiDataModel }

[ui_component]
def harbour(model:UiDataModel) {
    use_style(@@harbour_style)
    native_data("harbour",model) {
        row("top") {
            text("brand","HARBOUR / OPERATIONS")
            button("inspect","Inspect data models") { data_event("click","inspect()") }
        }
        box("intro") {
            text("eyebrow","DEPARTURE MANIFEST / 028")
            text("heading","A clear view of your cargo.")
            text("subtitle","Review the manifest, complete the inspection and authorize departure.")
        }
        row("workspace") {
            box("ledger") {
                row("section") {
                    text("section_title","Outbound inventory")
                    text("total") { data_text("cargo.size + ' consignments'") }
                }
                row("head") {
                    text("item","CONSIGNMENT"); text("qty","CRATES"); text("route","DESTINATION")
                }
                box("cargo_list") {
                    data_for("entry","item","cargo") {
                        data_class("priority","item.priority")
                        box("item") {
                            element("item_name","strong") { data_text("item.name") }
                            text("code") { data_text("item.code") }
                        }
                        text("qty") { data_text("item.crates") }
                        text("route") { data_text("item.destination") }
                        button("select","View") { data_event("click","select(item.code, item.name)") }
                    }
                }
                row("footer") {
                    text("hint","Priority consignments are marked in amber.")
                    button("reload","Load next manifest") { data_event("click","reload()") }
                }
            }
            box("dispatch") {
                text("eyebrow","DISPATCH DESK")
                text("section_title") { data_text("voyage.name") }
                element("captain_label","label") { text("","Captain") }
                text_input("captain") { data_value("voyage.captain") }
                element("port_label","label") { text("","Destination port") }
                select_input("port") {
                    data_value("voyage.port")
                    element("","option") { attribute("value","Rotterdam"); data_text("'Rotterdam'") }
                    element("","option") { attribute("value","Hamburg"); data_text("'Hamburg'") }
                    element("","option") { attribute("value","Antwerp"); data_text("'Antwerp'") }
                }
                element("","label") { text("","Departure window") }
                row("stepper") {
                    button("earlier","-") { data_event("click","voyage.hour = voyage.hour - 1") }
                    text("hour") { data_text("voyage.hour + ':00'") }
                    button("later","+") { data_event("click","voyage.hour = voyage.hour + 1") }
                }
                row("check") {
                    checkbox("ready") { data_checked("voyage.ready") }
                    element("","label") { text("","Inspection complete") }
                }
                button("primary","Authorize departure") {
                    data_disabled("!voyage.ready")
                    data_event("click","depart(voyage.captain, voyage.port, voyage.hour)")
                }
                data_if("notice","voyage.ready") {
                    text("notice_text") { data_text("'Ready for departure to ' + voyage.port | to_upper") }
                }
            }
        }
        row("status") {
            text("dot","LIVE")
            text("status_text") { data_text("status") }
            text("signature","NATIVE DATAMODEL / SDL3")
        }
    }
}
def manifest(alternate:bool):array<Cargo> {
    var rows:array<Cargo>
    rows |> push(Cargo(code="HC-2048",name="Optical equipment",crates=12,destination="Rotterdam",priority=true))
    rows |> push(Cargo(code="HC-2051",name="Navigation instruments",crates=8,destination="Hamburg"))
    rows |> push(Cargo(code="HC-2056",name="Research supplies",crates=24,destination="Antwerp"))
    if (alternate) { rows |> push(Cargo(code="HC-2062",name="Medical cold storage",crates=6,destination="Rotterdam",priority=true)) }
    return <- rows
}
[export]
def main(smoke:bool):int {
    var model=UiDataModel()
    var state=ui_state(Harbour())
    var alternate=false
    return run_demo("dasrmlui - Harbour / Native DataModel","logs/data_models.png",smoke,$() {
        if (!ui_data_alive(model)) {
            model=ui_data_model("harbour")
            ui_data_bind(model,"voyage",Voyage(),true)
            ui_data_bind(model,"cargo",manifest(false))
            ui_data_bind(model,"status","Awaiting inspection clearance.")
            for (name in fixed_array("select","reload","depart","inspect")) { ui_data_on(model,name) }
            ui_edit(state) $(var app:Harbour) { app.model=model }
        }
        ui_data_events(model) $(event:UiDataEvent) {
            if (event.name=="select") { ui_data_set(model,"status","Selected {event.arguments[0].text}: {event.arguments[1].text}") }
            elif (event.name=="reload") { alternate=!alternate; ui_data_set(model,"cargo",manifest(alternate)); ui_data_set(model,"status","Manifest refreshed. {ui_data_size(model,"cargo")} consignments loaded.") }
            elif (event.name=="depart" && ui_data_bool(model,"voyage.ready")) { ui_data_set(model,"status","Cleared: {event.arguments[0].text}, {event.arguments[1].text}, {event.arguments[2].integer}:00.") }
            elif (event.name=="inspect") {
                verify(ui_data_debugger())
            }
        }
        ui_frame(state) $(app:Harbour) { harbour(app.model) }
    }) $(frame:int) {
        let scope=ui_find("harbour")
        if (frame==0) { verify(ui_data_exists("harbour")); rui_test_event(ui_data_find(scope,"captain"),"change","Alex Morgan") }
        elif (frame==1) { verify(ui_data_text(model,"voyage.captain")=="Alex Morgan"); rui_test_click(ui_data_find(scope,"ready")) }
        elif (frame==2) { verify(ui_data_bool(model,"voyage.ready")); rui_test_click(ui_data_find(scope,"later")) }
        elif (frame==3) { verify(ui_data_int(model,"voyage.hour")==15); rui_test_click(ui_data_find(scope,"primary")) }
        elif (frame==4) { verify(find(ui_data_text(model,"status"),"Alex Morgan")>=0); rui_test_click(ui_data_find(scope,"reload")) }
        elif (frame==5) { verify(ui_data_size(model,"cargo")==4); unsafe { heap_collect(true,false) }; rui_test_click(ui_data_find(scope,"inspect")) }
        elif (frame==6) { rui_test_advance_time(2.0lf); rui_update(); verify(rui_visible(rui_test_debugger_document("data-models"))) }
        elif (frame==7) { debugger_shutdown(); print("PASS: native_data DSL, model, forms, expressions, data-for, callbacks and debugger\n") }
    }
}
