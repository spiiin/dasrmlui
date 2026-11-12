options gen2
module advanced_style public
require dasrmlui/ui public

def common_style() {
    rule(part("shell")) { padding(px(30.0)); width(px(1140.0)) }
    rule(part("eyebrow")) { color(rgb(91,212,180)); font_size(px(13.0)); margin_bottom(px(9.0)) }
    rule(part("heading")) { font_size(px(32.0)); margin_bottom(px(8.0)); color(rgb(240,245,252)) }
    rule(part("subtitle")) { color(rgb(145,160,183)); margin_bottom(px(26.0)) }
    rule(part("section")) { font_size(px(20.0)); margin_bottom(px(12.0)) }
    rule(part("muted")) { color(rgb(145,160,183)); font_size(px(14.0)) }
    rule(part("caption")) { color(rgb(174,189,209)); margin_bottom(px(8.0)); font_size(px(13.0)) }
    rule(part("metric")) { width(px(332.0)); padding(px(16.0)); margin_bottom(px(22.0)); background(rgb(23,34,50)); margin_right(px(12)) }
    rule(part("metric_value")) { font_size(px(34.0)); color(rgb(238,245,253)); margin_bottom(px(7.0)) }
    rule(part("card")) { padding(px(18.0)); background(rgb(23,34,50)); margin_bottom(px(12.0)) }
    rule(part("task")) { padding(px(14.0)); background(rgb(31,44,62)); margin_bottom(px(10.0)) }
    rule(part("task_title")) { font_size(px(17.0)); margin_bottom(px(7.0)); color(rgb(239,244,251)) }
    rule(part("toolbar")) { margin_bottom(px(16.0)) }
    rule(part("button")) { padding(px(9.0)); background(rgb(42,60,83)); color(rgb(222,234,249)); margin_right(px(8)) }
    part("button") |> hover() |> rule() { background(rgb(58,82,110)) }
    rule(part("primary")) { padding(px(10.0)); background(rgb(73,193,158)); color(rgb(9,32,28)); margin_right(px(8)) }
    part("primary") |> hover() |> rule() { background(rgb(105,223,187)) }
    rule(part("danger")) { padding(px(9.0)); background(rgb(89,42,53)); color(rgb(255,189,196)); margin_right(px(8)) }
    rule(part("field")) { width(px(294.0)); padding(px(10.0)); background(rgb(12,20,33)); color(rgb(233,242,253)); border_width(px(1)); border_color(rgb(64,84,108)); margin_bottom(px(12.0)) }
    rule(part("name_field")+", "+part("email_field")+", "+part("endpoint_field")+", "+part("draft_field")+", "+part("card_title")) {
        width(px(294.0)); padding(px(10.0)); background(rgb(12,20,33)); color(rgb(233,242,253)); border_width(px(1)); border_color(rgb(64,84,108)); margin_bottom(px(12.0))
    }
    rule(part("divider")) { height(px(1.0)); background(rgb(49,65,86)); margin_top(px(12.0)); margin_bottom(px(16.0)) }
    rule(part("good")) { color(rgb(98,218,175)); margin_bottom(px(10.0)) }
    rule(part("warning")) { color(rgb(244,184,111)); margin_bottom(px(10.0)) }
    rule(part("error")) { color(rgb(250,133,150)); margin_bottom(px(10.0)) }
    rule(part("nav")) { width(px(172.0)); margin_right(px(22)) }
    rule(part("nav_button")) { padding(px(12.0)); margin_bottom(px(8.0)); background(rgb(23,34,50)); color(rgb(193,211,234)) }
    part("nav_button") |> hover() |> rule() { background(rgb(42,60,83)) }
    rule(disabled_state(part("save"))+", "+disabled_state(part("add_card"))) { opacity(0.45) }
}

// Three independent scoped sheets, sharing only structural defaults.
[ui_style]
def operations_style() {
    common_style()
    rule(part("shell")) { background(rgb(27,31,39)); min_height(px(760)); border_top(px(6),rgb(218,73,63)) }
    rule(part("eyebrow")) { color(rgb(249,192,66)) }
    rule(part("section")) { color(rgb(249,192,66)); property("text-transform","uppercase"); font_size(px(17)) }
    rule(part("card")) { background(rgb(38,44,55)); border_top(px(2),rgb(218,73,63)) }
    rule(part("metric")) { background(rgb(44,50,61)); border_left(px(4),rgb(215,75,66)) }
    rule(part("task")) { background(rgb(49,57,70)); border_bottom(px(1),rgb(81,93,112)) }
    rule(part("primary")) { background(rgb(201,62,50)); color(rgb(255,244,230)) }
    rule(part("shell")+" button") { border_radius(px(2)); color(rgb(241,225,201)) }
    rule(part("shell")+" button:hover") { background(rgb(150,59,49)) }
}
[ui_style]
def preferences_style() {
    common_style()
    rule(part("shell")) { background(rgb(239,237,232)); color(rgb(48,47,49)); min_height(px(760)); border_top(px(6),rgb(173,48,60)) }
    rule(part("heading")) { color(rgb(57,43,47)); font_size(px(34)) }
    rule(part("eyebrow")) { color(rgb(166,45,58)); letter_spacing(px(2)) }
    rule(part("subtitle")+", "+part("muted")) { color(rgb(105,102,106)) }
    rule(part("caption")) { color(rgb(133,69,76)) }
    rule(part("card")) { background(rgb(255,255,252)); color(rgb(48,47,49)); border(px(1),rgb(214,203,200)); padding(px(17)) }
    rule(part("task")) { background(rgb(244,240,235)); border_left(px(3),rgb(201,101,102)); padding(px(18)) }
    rule(with_class(part("task"),"compact")) { padding(px(7)) }
    rule(part("preview_banner")) { background(rgb(220,215,239)) }
    rule(with_class(part("preview_banner"),"mint")) { background(rgb(208,231,217)) }
    rule(part("task_title")) { color(rgb(57,43,47)) }
    rule(part("primary")) { background(rgb(166,45,58)); color(rgb(255,250,247)) }
    rule(part("button")) { background(rgb(226,216,212)); color(rgb(81,51,57)) }
    rule(part("shell")+" input") { background(rgb(255,255,255)); color(rgb(48,47,49)); border(px(1),rgb(185,125,129)) }
    rule(part("shell")+" button") { color(rgb(81,51,57)) }
    rule(part("nav")+" button") { background(rgb(225,216,211)) }
    rule(part("shell")+" button:hover") { background(rgb(233,194,193)) }
    // After the hover rule and as specific as it is, so the selected tab keeps its colour under the pointer.
    rule(with_class(part("nav")+" button","active")) { background(rgb(229,190,191)) }
    rule(part("good")) { color(rgb(47,120,88)) }
    rule(part("warning")) { color(rgb(154,99,27)) }
    rule(part("error")) { color(rgb(178,40,54)) }
    rule(part("divider")) { background(rgb(218,207,204)) }
}
[ui_style]
def board_style() {
    common_style()
    rule(part("shell")) { background(rgb(241,237,248)); color(rgb(48,42,67)); min_height(px(760)); border_top(px(6),rgb(118,96,175)) }
    rule(part("heading")) { color(rgb(52,37,81)); font_size(px(36)) }
    rule(part("eyebrow")) { color(rgb(118,83,160)) }
    rule(part("subtitle")+", "+part("muted")) { color(rgb(117,108,135)) }
    rule(part("caption")) { color(rgb(133,114,161)); font_size(px(12)) }
    rule(part("card")) { background(rgb(229,224,239)); color(rgb(48,42,67)); border_radius(px(12)) }
    rule(part("task")) { background(rgb(255,253,255)); border_radius(px(8)); border_bottom(px(2),rgb(201,191,220)) }
    rule(part("task_title")) { color(rgb(58,45,80)) }
    rule(part("primary")) { background(rgb(112,83,167)); color(rgb(255,250,255)); border_radius(px(18)) }
    rule(part("shell")+" button") { color(rgb(103,74,146)); border_radius(px(6)) }
    rule(part("shell")+" button:hover") { background(rgb(211,195,235)) }
    rule(part("shell")+" input") { background(rgb(255,253,255)); color(rgb(58,45,80)); border(px(1),rgb(181,162,207)); border_radius(px(6)) }
    rule(part("warning")) { color(rgb(180,98,48)); font_size(px(12)) }
}
def use_theme(theme:int) {
    if (theme == 0) { use_style(@@operations_style) }
    elif (theme == 1) { use_style(@@preferences_style) }
    else { use_style(@@board_style) }
}
[ui_component]
def studio_header(theme:int; product,title,subtitle:string) {
    use_theme(theme)
    column() {
        text("eyebrow",product)
        text("heading",title)
        text("subtitle",subtitle)
    }
}
[ui_component]
def metric(caption,value,note:string) {
    use_style(@@operations_style)
    column("metric") {
        text("caption",caption)
        text("metric_value",value)
        text("muted",note)
    }
}
