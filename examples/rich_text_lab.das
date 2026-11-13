options gen2
options persistent_heap
options gc
options stack = 65536
require examples/demo_host
require strings
require math

struct Reading {
    name:string="Mira"
    size:float=22.
    narrow:bool=false
    notes:bool=true
    visits:int
    destination:string="journal:field-guide"
    status:string="Follow an underlined passage to open its reading note."
}
[ui_style]
def editorial() {
    spritesheet("examples/assets/expedition_atlas.png") {
        sprite("scout",0,0,627,627); sprite("rover",627,0,627,627)
    }
    rule(part("shell")) { background(rgb(244,239,227)); color(rgb(40,48,45)); padding(px(38)); min_height(pct(100)); property("box-sizing","border-box") }
    rule(part("masthead")) { font_size(px(14)); letter_spacing(px(4)); color(rgb(119,51,47)); margin_bottom(px(24)) }
    rule(part("title")) { font_size(px(48)); font_weight("bold"); margin_bottom(px(10)) }
    rule(part("deck")) { font_size(px(17)); color(rgb(111,115,102)); margin_bottom(px(30)) }
    rule(part("spread")) { property("align-items","flex-start") }
    rule(part("article")) { flex_grow(1.); min_width(px(0)); padding_right(px(36)) }
    rule(part("copy")) { line_height(1.55); margin_bottom(px(22)) }
    rule(part("caption")) { font_size(px(12)); letter_spacing(px(2)); color(rgb(125,85,57)); margin_bottom(px(16)) }
    rule(part("quote")) { font_size(px(27)); color(rgb(126,53,48)); border_left(px(3),rgb(126,53,48)); padding_left(px(20)); margin_y(px(8)); margin_bottom(px(24)); line_height(1.45) }
    rule(part("aside")) { width(px(252)); padding(px(22)); background(rgb(228,225,211)); flex_shrink(0.); border_top(px(4),rgb(63,91,75)) }
    rule(part("aside_title")) { font_weight("bold"); font_size(px(22)); margin_bottom(px(18)) }
    rule(part("label")) { font_size(px(13)); color(rgb(91,105,91)); margin_bottom(px(8)) }
    rule(part("name")) { width(px(226)); padding(px(12)); background(rgb(253,251,243)); color(rgb(40,48,45)); margin_bottom(px(20)); border_bottom(px(1),rgb(125,139,119)) }
    rule(part("control")) { padding(px(11)); background(rgb(63,91,75)); color(rgb(253,251,243)); margin_bottom(px(10)); width(px(230)) }
    rule(part("control")+":hover") { background(rgb(82,116,95)) }
    rule(part("control")+":focus") { border(px(1),rgb(162,105,59)) }
    rule(part("shell")+" a") { color(rgb(37,109,104)) }
    rule(part("shell")+" a:hover, "+part("shell")+" a:focus") { color(rgb(161,69,48)); background(rgb(237,225,197)) }
    rule(part("note")) { font_size(px(14)); line_height(1.5); color(rgb(94,103,91)); margin_top(px(14)) }
    rule(part("footer")) { border_top(px(1),rgb(197,193,176)); padding_top(px(18)); margin_top(px(18)); font_size(px(14)); color(rgb(94,103,91)) }
    media(media_max_width(px(900))) {
        rule(part("spread")) { property("flex-direction","column") }
        rule(part("article")) { width(pct(100)); padding_right(px(0)) }
        rule(part("aside")) { margin_top(px(20)); width(px(290)) }
        rule(part("title")) { font_size(px(36)) }
    }
}
[ui_component]
def journal(var model:Reading) {
    use_style(@@editorial)
    on_mount() { verify(rui_default_font_styles()) }
    column("shell") {
        text("masthead","THE FIELD NOTES   /   VOL. 08")
        text("title","Small details. A bigger story.")
        text("deck","A living reading room for the curious explorer.")
        row("spread") {
            column("article") {
                text("caption","01  /  AN INVITATION TO NOTICE")
                rich_text("copy") {
                    width(px(min(model.narrow ? 360. : 730.,max(240.,ui_width()-(ui_width()<900. ? 76. : 410.)))))
                    font_size(px(model.size))
                    text("welcome","Dear ")
                    strong("reader") { text("reader_name",model.name) }
                    text("intro",", every expedition begins with a small observation. Take the ")
                    inline_sprite("craft","scout") { width(em(1.8)); height(em(1.8)); vertical_align("middle") }
                    text("journey"," beyond the familiar and look for ")
                    strong("layers") {
                        text("bold","the unexpected ")
                        emphasis("layered") { text("bold_italic","inside the ordinary") }
                    }
                    text("continuation",". A change of perspective is often all it takes. ")
                    link("guide",model.destination) {
                        text("guide_label","Read the field guide")
                        on_activate() { model.visits+=1; model.status="Opened the field guide / reading {model.visits}." }
                    }
                    text("stop",".")
                }
                rich_text("quote") {
                    emphasis() { text("quotation","The most interesting line is the one that invites you to keep reading.") }
                    line_break()
                    span() { font_size(px(14)); font_style("normal"); text("credit","— NOTES FROM THE OBSERVATORY") }
                }
                rich_text("copy") {
                    font_size(px(model.size)); line_height(1.55)
                    text("second","Pack your curiosity, a notebook and ")
                    inline_sprite("rover","rover") { width(em(1.8)); height(em(1.8)); vertical_align("baseline") }
                    text("equipment"," a reliable companion. The old advice was ")
                    strike() { text("old_advice","move faster") }
                    text("new_advice",". Our advice: ")
                    underline() { text("underlined","notice more") }
                    text("period",".")
                    when(model.notes) {
                        span("reference") {
                            vertical_align("super"); font_size(em(0.65))
                            link("footnote","journal:note-1") {
                                text("footnote_label","[1]")
                                on_activate() { model.status="Note 1: observation is a skill. Give it time." }
                            }
                        }
                    }
                }
                when(model.notes) {
                    rich_text("note") { strong() { text("note_number","[1] ") }; text("note_body","Mixed sizes, nested emphasis and pictures belong to the same flowing paragraph. Resize the window to watch them travel together.") }
                }
            }
            column("aside") {
                text("aside_title","Make it your own")
                text("label","READER NAME")
                text_input("name") { bind_value(model.name) $(value:string) { model.name=value } }
                button("control","Narrow / wide column") { on_click() { model.narrow=!model.narrow } }
                button("control","Larger / smaller type") { on_click() { model.size=model.size==22. ? 27. : 22. } }
                button("control","Show / hide footnote") { on_click() { model.notes=!model.notes } }
                rich_text("note") {
                    text("aside_hint","The ")
                    inline_image("swatch","examples/assets/native_mesh_atlas.png") { width(px(32)); height(px(16)); vertical_align("middle") }
                    text("aside_hint_end"," marker is an ordinary PNG inside a sentence. Links work with a click, Tab and Enter.")
                }
            }
        }
        text("footer",model.status)
    }
}
[export]
def main(smoke:bool):int {
    var initial=Reading()
    var reader=0ul
    var state=ui_state(initial)
    return run_demo("dasrmlui - The Field Notes","logs/rich_text_lab.png",smoke,$() { ui_frame(state) $(model:Reading) { journal(model) } }) $(frame:int) {
        ui_edit(state) $(var model:Reading) {
            if (frame==0) { reader=ui_find("reader_name"); rui_test_event(ui_find("name"),"change","Alex"); model.narrow=true }
            elif (frame==1) { verify(model.name=="Alex" && ui_find("reader_name")==reader); rui_test_click(ui_find("guide_label")) }
            elif (frame==2) { verify(model.visits==1); rui_focus(ui_find("guide")); rui_test_key("Enter",false) }
            elif (frame==3) { verify(model.visits==2); model.notes=false; model.size=27. }
            elif (frame==4) { verify(ui_find("footnote")==0ul); model.notes=true; model.narrow=false }
            elif (frame==5) { verify(ui_find("footnote")!=0ul); rui_test_click(ui_find("footnote_label")) }
            elif (frame==6) { verify(find(model.status,"Note 1")>=0); model.name="Mira"; model.size=22. }
            elif (frame==7) { verify(ui_find("reader_name")==reader); print("PASS: rich text reading room, sprites/PNG, nested styles, reflow, input and keyboard links\n") }
        }
    }
}
