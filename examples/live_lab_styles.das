options gen2
require dasrmlui/ui

// Independently compiled by --styles; the name matches use_live_style("studio").
[ui_style(name="studio")]
def studio_theme() {
    rule(part("shell")) { min_height(pct(100)); padding(px(32)); background(rgb(243,240,248)); color(rgb(44,39,64)) }
    rule(part("eyebrow")) { font_size(px(12)); letter_spacing(px(2)); color(rgb(124,98,172)); margin_bottom(px(10)) }
    rule(part("heading")) { font_size(px(44)); margin_bottom(px(6)) }
    rule(part("intro")) { font_size(px(20)); color(rgb(126,115,146)); margin_bottom(px(20)) }
    rule(part("toolbar")) { margin_bottom(px(18)) }
    rule(part("shell")+" button") { padding(px(12)); margin_right(px(10)); background(rgb(98,73,146)); color(rgb(255,255,255)); border_radius(px(8)); font_size(px(14)) }
    rule(part("shell")+" button:hover") { background(rgb(22, 207, 130)) }
    rule(part("shell")+" button:focus") { border(px(2),rgb(211,156,81)) }
    rule(part("reset")) { background(rgb(32, 150, 166)); color(rgb(84,64,111)) }
    rule(part("workspace")) { padding(px(14)); background(rgb(151, 187, 60)); border_radius(px(12)); margin_bottom(px(16)) }
    rule(part("cards")) { gap(px(16)); property("align-items","stretch"); margin_bottom(px(22)) }
    rule(part("card")) { width(pct(44)); padding(px(20)); background(rgb(35, 173, 16)); border_radius(px(12)); border_top(px(3),rgb(186,133,161)) }
    rule(part("section")) { font_size(px(22)); margin_bottom(px(12)) }
    rule(part("shell")+" input") { width(pct(92)); padding(px(12)); background(rgb(255,253,255)); border(px(1),rgb(213,199,225)); border_radius(px(6)); color(rgb(61,46,82)); margin_bottom(px(14)) }
    rule(part("shell")+" input:focus") { border_color(rgb(124,98,172)) }
    rule(part("title")) { font_size(px(22)) }
    rule(part("count")) { margin_bottom(px(14)); color(rgb(131,98,123)) }
    rule(part("summary")) { font_size(px(13)); color(rgb(131,119,144)) }
    rule(part("instructions")) { padding(px(20)); border_left(px(3),rgb(193,179,214)) }
    rule(part("hint")) { font_size(px(14)); margin_bottom(px(8)); color(rgb(117,104,137)) }
}
[export]
def live_styles():string { return ui_style_sheet() { studio_theme() } }
