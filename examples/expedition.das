options gen2
options persistent_heap
options gc
options stack = 65536
require examples/demo_host
require examples/showcase_style
require strings
require math
struct Vehicle { id:int; sprite_id,title:string }
struct Expedition { vehicle:int; tab:int; fuel:float=65.0; route:string="orbit"; notes:string="Survey the northern ridge.\nCollect three samples."; launches:int }
var vehicles:array<Vehicle>
[ui_component]
def expedition(var model:Expedition) {
    use_style(@@expedition_style)
    column("shell") {
        width(px(max(340.0,ui_width()-56.0)))
        text("eyebrow","AURORA / EXPEDITION CONTROL")
        text("heading","Choose your next horizon")
        text("muted","Select a craft, prepare the mission and leave instructions for your crew.")
        flow("layout",900.0) {
            column("hangar") {
                width(px(ui_width()<900.0 ? ui_width()-96.0 : 360.0))
                text("section",vehicles[model.vehicle].title)
                sprite_image("hero",vehicles[model.vehicle].sprite_id)
                row() {
                    vehicles |> each_keyed($(v:Vehicle)=>v.id) $(v:Vehicle) {
                        button("vehicle","") { sprite_image("thumbnail",v.sprite_id); on_click() { model.vehicle=v.id } }
                    }
                }
                text("muted","Scout / Rover / Science probe / Cargo lander")
                text("eyebrow","FUEL RESERVE")
                progress_bar("fuel_bar",model.fuel,100.0)
                text("status","{model.fuel:.0f}% ready for departure")
            }
            column("card") {
                width(px(ui_width()<900.0 ? ui_width()-100.0 : ui_width()-520.0))
                tabset("mission_tabs") {
                    tab_headers() { tab_label("setup_tab","Mission setup"); tab_label("notes_tab","Crew briefing") }
                    tab_panels() {
                        tab_panel("setup") {
                            text("section","Flight preparation")
                            text("muted","Fuel allocation / {model.fuel:.0f}%")
                            range_input("fuel") { bind_range(model.fuel,0.0,100.0,5.0) $(value:float) { model.fuel=value } }
                            text("eyebrow","DESTINATION")
                            row() { radio_input("orbit") { bind_radio(model.route,"route","orbit") $(value:string) { model.route=value } }; text("muted","Orbital survey / 30% fuel") }
                            row() { radio_input("surface") { bind_radio(model.route,"route","surface") $(value:string) { model.route=value } }; text("muted","Surface landing / 60% fuel") }
                            row() { radio_input("deep") { bind_radio(model.route,"route","deep") $(value:string) { model.route=value } }; text("muted","Deep exploration / 90% fuel") }
                            text("muted","Drag the slider or select a destination. Fuel is shared with the reserve indicator.")
                            button("launch","Authorize mission") { on_click() { model.launches += 1 } }
                            text("status","{model.launches} missions authorized")
                        }
                        tab_panel("briefing") {
                            text("section","Instructions for the crew")
                            text_area("notes") { attribute("maxlength","360"); bind_value(model.notes) $(value:string) { model.notes=value } }
                            text("muted","{length(model.notes)} / 360 bytes")
                            button("clear","Clear briefing") { on_click() { model.notes="" } }
                            text("muted","The draft stays intact when switching tabs.")
                        }
                    }
                    bind_tab(model.tab) $(value:int) { model.tab=value }
                }
            }
        }
    }
}
[export]
def main(smoke:bool):int {
    vehicles |> push <| Vehicle(id=0,sprite_id="scout",title="Kestrel / Scout")
    vehicles |> push <| Vehicle(id=1,sprite_id="rover",title="Nomad / Rover")
    vehicles |> push <| Vehicle(id=2,sprite_id="probe",title="Echo / Science probe")
    vehicles |> push <| Vehicle(id=3,sprite_id="cargo",title="Atlas / Cargo lander")
    var model=Expedition()
    return run_demo("dasrmlui - Expedition console","logs/expedition.png",smoke,$() { expedition(model) }) $(frame:int) {
        if (frame==0) { rui_test_click(ui_find("vehicle",2)); rui_test_click(ui_find("surface")) }
        elif (frame==1) { verify(model.vehicle==2 && model.route=="surface"); rui_test_click(ui_find("fuel")) }
        elif (frame==2) { verify(model.fuel!=65.0); rui_test_click(ui_find("notes_tab")) }
        elif (frame==3) { verify(model.tab==1 && rui_visible(ui_find("notes")) && !rui_visible(ui_find("fuel"))); rui_focus(ui_find("notes")); rui_test_text(" Ready.") }
        elif (frame==4) { verify(find(model.notes,"Ready.")>=0); rui_test_click(ui_find("setup_tab")) }
        elif (frame==5) { verify(model.tab==0); rui_test_click(ui_find("launch")) }
        elif (frame==6) { verify(model.launches==1); rui_test_resize(720,820) }
    }
}
