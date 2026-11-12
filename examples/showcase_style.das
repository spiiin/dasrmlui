options gen2
module showcase_style public
require dasrmlui/ui public

// Native @spritesheet definitions. The generated PNG is 1254 x 1254.
def expedition_sprites() {
    spritesheet("examples/assets/expedition_atlas.png") {
        sprite("scout",0,0,627,627)
        sprite("rover",627,0,627,627)
        sprite("probe",0,627,627,627)
        sprite("cargo",627,627,627,627)
    }
}
def showcase_controls() {
    rule(part("shell")+" button") { padding(px(10)); background(rgb(42,78,103)); color(rgb(223,245,255)); property("margin-right","10px"); margin_bottom(px(8)); property("border-radius","5px"); property("transition","background-color 0.2s") }
    rule(part("shell")+" button:hover") { background(rgb(63,117,148)) }
    rule(part("shell")+" button:focus") { property("border","1px #71d7ef") }
    rule(part("shell")+" input.range") { width(pct(100)); height(px(22)); margin_bottom(px(14)) }
    rule(part("shell")+" input.range slidertrack") { height(px(8)); property("margin-top","7px"); background(rgb(29,53,73)); property("border-radius","4px") }
    rule(part("shell")+" input.range sliderbar") { width(px(18)); height(px(22)); property("margin-top","-7px"); background(rgb(119,221,239)); property("border-radius","5px") }
    rule(part("shell")+" input.range sliderprogress") { height(px(8)); background(rgb(67,158,186)) }
    rule(part("shell")+" input.range sliderarrowdec, "+part("shell")+" input.range sliderarrowinc") { width(px(0)); height(px(22)) }
    rule(part("shell")+" input.radio") { width(px(18)); height(px(18)); property("border","2px #6b99ac"); property("border-radius","12px"); property("margin-right","10px"); background(rgb(15,31,46)) }
    rule(part("shell")+" input.radio:checked") { background(rgb(113,215,239)); property("border-color","#effcff") }
    rule(part("shell")+" textarea") { width(pct(94)); height(px(130)); padding(px(12)); background(rgb(12,29,44)); color(rgb(215,236,245)); property("border","1px #52768b"); property("border-radius","6px"); property("white-space","pre-wrap") }
    rule(part("shell")+" textarea:focus") { property("border-color","#71d7ef") }
    rule(part("shell")+" tabs") { property("display","flex"); margin_bottom(px(20)); property("border-bottom","1px #3a5e73") }
    rule(part("shell")+" tab") { padding(px(12)); property("margin-right","16px"); color(rgb(130,170,188)); property("cursor","pointer") }
    rule(part("shell")+" tab:selected") { color(rgb(213,251,255)); property("border-bottom","3px #71d7ef") }
    // Panels keep the ru-column flex layout supplied by tab_panel. Overriding
    // them to block makes their span captions and buttons run together inline.
    rule(part("shell")+" panels") { property("display","block") }
    rule(part("shell")+" progress") { width(pct(100)); height(px(12)); background(rgb(17,37,55)); property("border-radius","6px"); margin_top(px(10)); margin_bottom(px(16)) }
    rule(part("shell")+" progress fill") { background(rgb(98,213,213)); property("border-radius","6px") }
}
[ui_style]
def expedition_style() {
    expedition_sprites(); showcase_controls()
    rule(part("shell")) { padding(px(28)); background(rgb(12,26,42)); color(rgb(218,236,246)); property("min-height","764px") }
    rule(part("heading")) { font_size(px(36)); margin_bottom(px(8)) }
    rule(part("eyebrow")) { color(rgb(109,218,236)); font_size(px(12)); property("letter-spacing","3px"); margin_bottom(px(12)) }
    rule(part("muted")) { color(rgb(132,164,183)); font_size(px(14)); margin_bottom(px(16)) }
    rule(part("section")) { font_size(px(23)); margin_bottom(px(18)) }
    rule(part("card")) { padding(px(22)); background(rgb(20,43,62)); property("border-radius","12px"); margin_bottom(px(18)) }
    rule(part("hangar")) { property("decorator","vertical-gradient(#24546b #102436)"); padding(px(20)); property("border-radius","12px"); property("margin-right","20px") }
    rule(part("hero")) { width(px(300)); height(px(300)); property("margin-left","auto"); property("margin-right","auto") }
    rule(part("thumbnail")) { width(px(66)); height(px(66)) }
    rule(part("shell")+" "+part("vehicle")) { padding(px(4)); background(rgb(22,51,70)); property("transition","background-color 0.25s") }
    rule(part("shell")+" "+part("vehicle")+":hover") { background(rgb(53,104,129)) }
    rule(part("status")) { color(rgb(130,235,203)); margin_top(px(10)) }
}
