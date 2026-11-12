options gen2
module workbench_style public
require dasrmlui/ui public

// Shared dimensions only; each demo owns a separate scoped visual theme.
def workbench_layout() {
    rule(part("shell")) { padding(px(28)); min_height(px(764)) }
    rule(part("eyebrow")) { font_size(px(12)); margin_bottom(px(12)) }
    rule(part("heading")) { font_size(px(34)); margin_bottom(px(8)) }
    rule(part("muted")) { font_size(px(14)); margin_bottom(px(10)) }
    rule(part("section")) { font_size(px(21)); margin_bottom(px(18)) }
    rule(part("card")+", "+part("inspector")+", "+part("activity_panel")) { padding(px(20)); margin_bottom(px(16)) }
    rule(part("shell")+" button") { padding(px(10)); margin_right(px(8)); margin_bottom(px(8)) }
    rule(part("shell")+" button:disabled") { opacity(0.4) }
}

// Botanical library: pale mint paper, green ink, fine rules and compact rows.
[ui_style]
def catalog_style() {
    workbench_layout()
    rule(part("shell")) { background(rgb(226,237,230)); color(rgb(28,66,50)) }
    rule(part("eyebrow")) { color(rgb(47,112,80)); letter_spacing(px(2)) }
    rule(part("heading")) { font_size(px(40)); color(rgb(23,66,47)) }
    rule(part("muted")) { color(rgb(92,117,101)) }
    rule(part("section")) { color(rgb(28,78,54)) }
    rule(part("card")) { background(rgb(247,250,245)); border_radius(px(14)) }
    rule(part("inspector")) { background(rgb(206,224,211)); border_radius(px(14)); border_top(px(4),rgb(54,116,84)) }
    rule(part("shell")+" button") { background(rgb(219,233,220)); color(rgb(36,83,56)); border_radius(px(20)) }
    rule(part("shell")+" button:hover") { background(rgb(190,216,196)) }
    rule(part("shell")+" button:focus") { border(px(1),rgb(54,116,84)) }
    rule(part("shell")+" "+part("asset")) { background(rgb(237,244,235)); color(rgb(36,73,49)); padding(px(12)); border_radius(px(0)); border_bottom(px(1),rgb(203,220,201)); margin_bottom(px(4)) }
    rule(part("shell")+" "+part("asset")+":hover") { background(rgb(218,234,216)) }
    rule(part("shell")+" "+part("asset")+":focus") { background(rgb(203,225,204)); border(px(1),rgb(54,116,84)) }
    rule(part("shell")+" "+part("edit")+", "+part("shell")+" "+part("save")) { background(rgb(41,105,70)); color(rgb(250,255,242)) }
    rule(part("shell")+" "+part("edit")+":hover, "+part("shell")+" "+part("save")+":hover") { background(rgb(29,83,53)) }
    rule(part("field")+", "+part("title")+", "+part("stock")+", "+part("price")) { width(px(246)); padding(px(10)); margin_bottom(px(12)) }
    rule(part("field")+", "+part("title")+", "+part("stock")+", "+part("price")+", "+part("search")) {
        background(rgb(255,255,250)); color(rgb(28,66,50)); border(px(1),rgb(157,183,163)); border_radius(px(6))
    }
    rule(part("shell")+" input:focus, "+part("shell")+" select:focus") { border_color(rgb(54,116,84)) }
    rule(part("shell")+" input:invalid") { border_color(rgb(186,85,66)) }
    rule(part("error")) { color(rgb(172,65,49)); font_size(px(13)); margin_bottom(px(10)) }
    rule(part("check")) { width(px(22)); height(px(22)); background(rgb(255,255,250)); border(px(1),rgb(157,183,163)); margin_right(px(10)) }
    rule(part("check")+":checked") { background(rgb(49,119,78)); border(px(4),rgb(154,195,163)) }
    rule(part("shell")+" selectvalue") { padding(px(4)) }
    rule(part("shell")+" selectarrow") { width(px(18)); background(rgb(97,143,111)) }
    rule(part("shell")+" selectbox") { background(rgb(250,253,245)); border(px(1),rgb(157,183,163)) }
    rule(part("shell")+" option") { padding(px(10)); color(rgb(28,66,50)) }
    rule(part("shell")+" option:hover, "+part("shell")+" option:checked") { background(rgb(203,225,204)) }
    rule(part("shade")) { position("absolute"); left(px(0)); top(px(0)); width(pct(100)); height(pct(100)); property("background-color","#102d22aa"); z_index(9) }
    rule(part("dialog")) { position("absolute"); left(pct(8)); top(px(70)); width(pct(80)); padding(px(24)); background(rgb(247,250,240)); border_top(px(6),rgb(54,116,84)); border_radius(px(12)); z_index(10); display("flex"); property("flex-direction","column") }
    rule(part("shell")+" scrollbarvertical sliderbar") { background(rgb(133,164,141)); border_radius(px(5)) }
}

// Workshop ledger: warm charcoal, copper edges, oversized prices, square controls.
[ui_style]
def component_lab_style() {
    workbench_layout()
    rule(part("shell")) { background(rgb(31,26,24)); color(rgb(238,220,198)) }
    rule(part("eyebrow")) { color(rgb(222,151,103)); letter_spacing(px(3)) }
    rule(part("heading")) { font_size(px(42)); color(rgb(255,239,214)) }
    rule(part("muted")) { color(rgb(172,151,132)) }
    rule(part("card")) { background(rgb(48,39,34)); border_top(px(4),rgb(185,125,81)); border_radius(px(2)) }
    rule(part("package_title")) { font_size(px(22)); color(rgb(244,223,194)); margin_bottom(px(18)) }
    rule(part("units")) { color(rgb(231,183,142)); font_size(px(15)) }
    rule(part("subtotal")) { font_size(px(38)); color(rgb(248,176,115)); margin_bottom(px(18)); border_bottom(px(1),rgb(116,82,61)); padding_y(px(8)) }
    rule(part("shell")+" button") { background(rgb(74,54,42)); color(rgb(245,218,186)); border_radius(px(2)) }
    rule(part("shell")+" button:hover") { background(rgb(108,74,50)) }
    rule(part("shell")+" button:focus") { border(px(1),rgb(229,172,116)) }
    rule(part("shell")+" "+part("add")+", "+part("shell")+" "+part("increase")) { background(rgb(204,137,82)); color(rgb(35,25,19)) }
    rule(part("shell")+" "+part("add")+":hover, "+part("shell")+" "+part("increase")+":hover") { background(rgb(233,169,112)) }
    rule(part("shell")+" "+part("remove")) { background(rgb(39,31,27)); color(rgb(209,160,125)); border_bottom(px(1),rgb(116,82,61)) }
    rule(part("shell")+" "+part("remove")+":hover") { background(rgb(84,49,38)) }
    rule(part("activity_panel")) { background(rgb(24,21,20)); border_left(px(3),rgb(185,125,81)) }
    rule(part("activity")) { color(rgb(181,166,148)); font_size(px(14)); property("line-height","1.6") }
    rule(part("shell")+" scrollbarvertical sliderbar") { background(rgb(136,99,73)) }
}
