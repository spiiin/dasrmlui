options gen2
options persistent_heap
options gc
options stack = 65536
require examples/demo_host
require strings

struct Passport { name:string="Alex"; samples:int=2 }
def entry(key,en,de,ru:string) {
    rui_translation("en",key,en); rui_translation("de",key,de); rui_translation("ru",key,ru)
}
def translations() {
    entry("title","A passport to discovery","Ein Pass zur Entdeckung","Паспорт исследователя")
    entry("intro","Your language. Your next adventure.","Deine Sprache. Dein nächstes Abenteuer.","Ваш язык. Ваше следующее приключение.")
    entry("name","Explorer name","Name des Forschers","Имя исследователя")
    entry("hello","Welcome aboard, %name%!","Willkommen an Bord, %name%!","Добро пожаловать на борт, %name%!")
    entry("one","sample","Probe","образец")
    entry("few","samples","Proben","образца")
    entry("many","samples","Proben","образцов")
    entry("collection","Collected samples","Gesammelte Proben","Собранные образцы")
    entry("add","Collect one more","Eine weitere sammeln","Собрать ещё один")
    entry("reset","Reset collection","Sammlung zurücksetzen","Сбросить коллекцию")
    entry("hint","Switch language without losing your draft.","Sprache wechseln, Entwurf behalten.","Меняйте язык — введённые данные сохраняются.")
    rui_translation("en","fallback","English fallback / missing translation")
}
def sample_phrase(count:int; language:string):string {
    var key=count==1 ? "one" : "many"
    if (language=="ru") {
        let last=count%10; let hundred=count%100
        if (last==1 && hundred!=11) { key="one" }
        elif (last>=2 && last<=4 && (hundred<12 || hundred>14)) { key="few" }
    }
    return "{count} {tr(key)}"
}
[ui_style]
def passport_style() {
    rule(part("shell")) { padding(px(40)); background(rgb(244,239,232)); color(rgb(50,53,75)); min_height(px(740)); property("font-family",get_platform_name() == "windows" ? "Segoe UI" : "DejaVu Sans") }
    rule(part("heading")) { font_size(px(36)); margin_bottom(px(12)) }
    rule(part("muted")) { color(rgb(119,110,122)); margin_bottom(px(20)) }
    rule(part("card")) { padding(px(28)); width(px(720)); background(rgb(255,253,249)); border(px(1),rgb(221,209,203)); border_radius(px(12)); margin_top(px(18)) }
    rule(part("caption")) { font_size(px(18)); margin_bottom(px(10)) }
    rule(part("name")) { width(px(600)); padding(px(12)); background(rgb(246,239,236)); color(rgb(62,49,66)); border(px(1),rgb(186,165,174)); margin_bottom(px(22)) }
    rule(part("greeting")) { font_size(px(26)); color(rgb(159,76,106)); margin_bottom(px(22)) }
    rule(part("count")) { font_size(px(32)); margin_bottom(px(20)) }
    rule(part("shell")+" button") { padding(px(12)); background(rgb(139,82,105)); color(rgb(255,246,237)); margin_right(px(12)); margin_bottom(px(12)); border_radius(px(6)) }
    rule(part("shell")+" button:hover") { background(rgb(170,106,132)) }
}
[ui_component]
def passport(var model:Passport) {
    use_style(@@passport_style)
    on_mount() {
        translations()
        // Installed Windows font, not redistributed in the repository.
        verify(rui_font(get_platform_name() == "windows" ? "C:/Windows/Fonts/segoeui.ttf" : "assets/DejaVuSans.ttf"),"Could not load the localization font")
    }
    column("shell") {
        width(px(ui_width()-80.))
        text("heading",tr("title"))
        text("muted",tr("intro"))
        row() {
            button("english","English") { on_click() { set_locale("en") } }
            button("german","Deutsch") { on_click() { set_locale("de") } }
            button("russian","Русский") { on_click() { set_locale("ru") } }
        }
        column("card") {
            text("caption",tr("name"))
            text_input("name") { bind_value(model.name) $(value:string) { model.name=value } }
            text("greeting",replace(tr("hello"),"%name%",model.name))
            text("caption",tr("collection"))
            text("count",sample_phrase(model.samples,ui_locale()))
            row() {
                button("add",tr("add")) { on_click() { model.samples+=1 } }
                button("reset",tr("reset")) { on_click() { model.samples=0 } }
            }
            text("muted",tr("hint"))
            text("muted",tr("fallback"))
        }
    }
}
[export]
def main(smoke:bool):int {
    var initial=Passport()
    var field=0ul
    var state=ui_state(initial)
    return run_demo("dasrmlui - Explorer passport","logs/localization.png",smoke,$() { ui_frame(state) $(model:Passport) { passport(model) } }) $(frame:int) {
        ui_edit(state) $(var model:Passport) {
            if (frame==0) {
                field=ui_find("name"); rui_focus(field); rui_test_text(" Li")
                // External locale change must invalidate bindings even without model changes.
                set_locale("ru")
            }
            elif (frame==1) {
                verify(ui_find("name")==field && rui_focused(field) && find(model.name,"Li")>=0)
                verify(find(rui_markup(),"Паспорт исследователя")>=0)
                verify(sample_phrase(1,"ru")=="1 образец" && sample_phrase(2,"ru")=="2 образца" && sample_phrase(5,"ru")=="5 образцов")
                verify(sample_phrase(11,"ru")=="11 образцов" && sample_phrase(21,"ru")=="21 образец")
                verify(tr("unknown")=="[unknown]" && tr("fallback")=="English fallback / missing translation")
                rui_test_click(ui_find("add"))
            }
            elif (frame==2) { verify(model.samples==3); rui_test_click(ui_find("german")) }
            elif (frame==3) { verify(ui_locale()=="de" && find(rui_markup(),"Ein Pass zur Entdeckung")>=0 && ui_find("name")==field); verify(sample_phrase(2,"de")=="2 Proben"); rui_test_click(ui_find("reset")) }
            elif (frame==4) { verify(model.samples==0); rui_test_click(ui_find("english")) }
            elif (frame==5) {
                verify(ui_locale()=="en" && find(rui_markup(),"A passport to discovery")>=0)
                // Also exercise the actual native RML parser translation hook.
                // Raw RML is laid out while it loads, before DSL styles reach it, so it names its own font.
                let doc=rui_document("<rml><head/><body style=\"font-family: LatoLatin;\"><div id=\"translated\">[title]</div></body></rml>","translation-test.rml")
                verify(doc!=0ul && rui_inner_markup(rui_document_element(doc,"translated"))=="A passport to discovery","native TranslateString during RML parse")
                rui_close_document(doc)
            }
            elif (frame==6) { rui_focus(field); set_locale("ru") }
            elif (frame==7) { verify(ui_find("name")==field && model.name==rui_get_value(field) && rui_focused(field)); verify(find(rui_markup(),"Паспорт исследователя")>=0,"external locale change without model mutation"); print("PASS: locale invalidation, UTF-8, plurals, fallback, stable input\n") }
        }
    }
}
