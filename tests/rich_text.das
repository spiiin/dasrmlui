options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require math
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

struct Model {
    width:float=480.
    title:string="Initial fragment"
    target:string="route:first"
    source:string="examples/assets/native_mesh_atlas.png"
    activated:int
    visible:bool=true
}
var hybrid_runs:int
[ui_style]
def sheet() {
    rule(part("paragraph")) { color(rgb(25,45,65)); line_height(1.5) }
    rule(part("anchor")+":focus") { color(rgb(160,40,90)) }
}
[ui_template]
def rich_frame() {
    window_frame("window") {
        rich_text("caption") { text("a","Static "); strong("b") { text("c","rich frame") } }
        slot("content")
    }
}
[ui_component(legacy=true)]
def page(var model:Model) {
    use_style(@@sheet)
    rich_text("paragraph") {
        width(px(model.width)); font_size(px(20))
        text("long","One continuous paragraph with enough words to wrap over several lines when the width changes. ")
        strong("bold") {
            text("bold_text","Bold ")
            emphasis("nested") { text("nested_text",model.title) }
        }
        text("space"," ")
        link("anchor",model.target) {
            text("link_text","open details")
            on_activate() { model.activated+=1 }
        }
        text("end",".")
    }
    rich_text("baseline") {
        width(px(600)); line_height(1.5)
        span("small") { font_size(px(16)); text("small_text","Small ") }
        strong("large") { font_size(px(32)); text("large_text","Large ") }
        inline_image("icon",model.source) { width(px(24)); height(px(24)); vertical_align("baseline") }
        span("raised") { vertical_align("super"); text("raised_text","2") }
    }
    rich_text("breaks") { text("before","First"); line_break(); underline("under") { text("after","Second") } }
    rich_text("nowrap") { width(px(40)); white_space("nowrap"); text("nowrap_text","Never split this text") }
    rich_text("pre") { white_space("pre-wrap"); text("pre_text","first\nsecond") }
    rich_text("adjacent") { text("a","Hello"); emphasis() { text("b",", ") }; text("c","world") }
    rich_text("conditional") { when(model.visible) { strike("old") { text("old_text","Old price") } } }
}
[ui_component]
def native_page(var model:Model) {
    hybrid_runs+=1
    rich_text("native_paragraph") {
        width(px(400))
        strong("native_bold") { emphasis("native_nested") { text("native_title",model.title) } }
        link("native_link",model.target) { text("native_label","Read"); on_activate() { model.activated+=1 } }
        inline_image("native_icon",model.source) { width(px(20)); height(px(20)) }
    }
}
[ui_action]
def change(var model:Model) {
    model.title="Dynamic <tag> & text"
    model.target="route:second"
    model.source="examples/assets/style_atlas.png"
}
def close(a,b:float):bool { return abs(a-b)<1.1 }
def baseline(name:string):float { return rui_text_line_position(ui_find(name),0).y }
[export]
def main(smoke:bool):int {
    var model=Model()
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Rich text layout tests",800,600,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        verify(rui_init(window,renderer,800,600)); verify(rui_default_font_styles())
        set_base_text("LatoLatin",px(18),rgb(20,30,40))
        ui_legacy_frame() { page(model) }
        let title=ui_find("nested_text"); let link_id=ui_find("anchor"); let icon=ui_find("icon")
        let wide=rui_text_line_count(ui_find("long"))
        verify(wide>=1)
        verify(close(baseline("small_text"),baseline("large_text")),"mixed font sizes share the native glyph baseline")
        let image=rui_bounds(icon)
        verify(close(image.y+image.w,baseline("large_text")),"inline image bottom aligns to text baseline")
        verify(baseline("raised_text")<baseline("large_text"),"superscript raises the baseline")
        verify(rui_computed_property(title,"font-style")=="italic","nested emphasis inherits a real italic face")
        let weight=rui_computed_property(title,"font-weight")
        verify(weight=="bold" || weight=="700","nested bold is applied, not just matching two regular fragments")
        verify(rui_computed_property(title,"font-weight")==rui_computed_property(ui_find("bold_text"),"font-weight"),"nested emphasis preserves bold")
        verify(rui_computed_property(title,"color")==rui_computed_property(ui_find("long"),"color"),"inline fragments inherit paragraph color")
        verify(baseline("after")>baseline("before"),"explicit br splits the line")
        verify(rui_text_line_count(ui_find("nowrap_text"))==1)
        verify(rui_text_line_count(ui_find("pre_text"))==2)
        verify(close(baseline("a"),baseline("c")) && rui_text_line(ui_find("b"),0)==", ","fragment boundaries do not insert whitespace")
        model.width=130.
        ui_legacy_frame() { page(model) }
        verify(rui_text_line_count(ui_find("long"))>wide,"narrow width reflows native inline text")
        verify(ui_find("nested_text")==title && ui_find("anchor")==link_id,"reflow preserves fragment and handler identity")
        model.width=480.; change(model)
        ui_legacy_frame() { page(model) }
        verify(rui_inner_markup(title)=="Dynamic &lt;tag&gt; &amp; text","dynamic text stays text, not RML")
        verify(rui_get_attr(link_id,"href")==model.target && rui_get_attr(icon,"src")==model.source)
        rui_test_click(ui_find("link_text")); ui_legacy_frame() { page(model) }
        verify(model.activated==1,"nested link text bubbles to one activation")
        rui_focus(link_id); rui_test_key("Enter",false); ui_legacy_frame() { page(model) }
        verify(model.activated==2,"focused links activate once with Enter")
        rui_test_key("Space",false); ui_legacy_frame() { page(model) }
        verify(model.activated==3,"native Space activation is not duplicated")
        let retired=ui_find("old_text"); model.visible=false; ui_legacy_frame() { page(model) }
        verify(!rui_alive(retired)); model.visible=true; ui_legacy_frame() { page(model) }
        verify(ui_find("old_text")!=retired)
        let markup=template_markup(@@rich_frame)
        verify(find(markup,"font-weight")>=0 && find(markup,"rich frame")>=0,"rich text lowers through static templates too")
        rui_render(); verify(rui_screenshot("logs/rich_text_test.png"))
        ui_reset()
        model.title="Native first"; model.target="route:first"; model.source="examples/assets/native_mesh_atlas.png"
        rt_hybrid_frame(model) { native_page(model) }
        let first=ui_find("native_title"); let runs=hybrid_runs; let reads=rui_hybrid_reads()
        for (i in range(5)) { rt_hybrid_frame(model) { native_page(model) } }
        verify(hybrid_runs==runs && rui_hybrid_reads()==reads,"rich text has a sleeping hybrid path")
        change(model); rt_hybrid_frame(model) { native_page(model) }
        verify(hybrid_runs==runs && ui_find("native_title")==first,"native leaf changes preserve formatted tree")
        verify(rui_hybrid_reads()==reads+3,"only text, href and src native bindings run")
        verify(rui_get_attr(ui_find("native_link"),"href")==model.target)
        verify(rui_get_attr(ui_find("native_icon"),"src")==model.source)
        unsafe { heap_collect(true,false) }
        rui_test_click(ui_find("native_label")); rt_hybrid_frame(model) { native_page(model) }
        verify(model.activated==4)
        verify(rui_warning_count()==0ul)
        ui_reset(); rui_shutdown()
        print("PASS: rich text wrap, baseline, nested formatting, images, links, dynamic/hybrid bindings, templates and GC\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}
