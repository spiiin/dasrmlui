options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

var definitions:int
let literal_text="<div id=\"injected\">A & B</div>"
let literal_attribute="\"quoted\" & <value>"
[ui_style]
def chrome_style() {
    rule(root()) { property("position","absolute"); width(px(320)); height(px(240)); property("margin","0px"); padding(px(0)) }
    rule(part("move")) { property("display","block"); height(px(30)) }
}
[ui_style]
def other_style() { rule(root()) { width(px(170)) } }
[ui_template]
def test_frame() {
    definitions+=1
    use_style(@@chrome_style)
    window_frame("frame") {
        move_handle("move") { title_slot("title") }
        column("static_column") {
            width(px(123))
            row("static_row") {
                box("metadata") {
                    attribute("data-info",literal_attribute)
                    text("literal",literal_text)
                }
            }
        }
        slot("body") { padding(px(7)) }
        resize_handle("resize") { width(px(10)); height(px(10)) }
    }
}
[ui_template]
def second_frame() {
    window_frame("frame") {
        width(px(200)); height(px(120))
        slot("body")
    }
}
[ui_component(legacy=true)]
def injected_content(document:uint64; message:string) {
    document_content(document,"body") { text("message",message) }
}
[export]
def main(smoke:bool):int {
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Template DSL tests",800,600,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        for (generation in range(2)) {
            verify(rui_init(window,renderer,800,600)); verify(rui_default_font())
            use_style(@@other_style)
            let previous=part("probe")
            let generated=template_markup(@@test_frame)
            verify(find(generated,"<template")>=0 && find(generated,"move_target=\"#document\"")>=0)
            verify(find(generated,"&lt;div")>=0 && find(generated,"&amp;")>=0)
            verify(part("probe")==previous,"template compilation must preserve caller style")
            let first=open_template(@@test_frame,literal_text,float2(10.,20.))
            let second=open_template(@@test_frame,"Second",float2(360.,30.))
            let independent=open_template(@@second_frame,"No title slot",float2(20.,300.))
            verify(definitions==generation+1,"definition cached across instances")
            verify(part("probe")==previous,"cached template must preserve caller style")
            var message="Dynamic content"
            ui_legacy_frame() { injected_content(first,message) }
            let content=ui_find("message")
            verify(rui_document_element(first,"move")!=rui_document_element(second,"move"),"document-local ids")
            verify(rui_document_element(first,"injected")==0ul,"literal text/title must not become markup")
            verify(rui_get_attr(rui_document_element(first,"metadata"),"data-info")==literal_attribute)
            verify(find(rui_inner_markup(rui_document_element(first,"title")),"&lt;div")>=0)
            verify(rui_get_attr(rui_document_element(first,"move"),"move_target")=="#document")
            verify(rui_get_attr(rui_document_element(first,"resize"),"size_target")=="#document")
            verify(rui_bounds(first).z==320. && rui_bounds(second).z==320. && rui_bounds(independent).z==200.,"template stylesheet and inline properties")
            verify(rui_bounds(rui_document_element(first,"static_column")).z==123.)
            unsafe { heap_collect(true,false) }
            message="Updated after GC"
            ui_legacy_frame() { injected_content(first,message) }
            verify(ui_find("message")==content && rui_inner_markup(content)==message)
            rui_close_document(second)
            verify(rui_alive(first) && !rui_alive(second) && rui_alive(independent),"closing one instance leaves others alive")
            ui_reset()
            rui_close_document(first); rui_close_document(independent); rui_shutdown()
        }
        print("PASS: native template generation, cache, scoped styles, escaping, content, GC, restart\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}

