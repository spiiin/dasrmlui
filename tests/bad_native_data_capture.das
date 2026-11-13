options gen2
require dasrmlui/ui
[ui_component]
def screen(model:UiDataModel; caption:string) {
    native_data("form",model) { text("caption",caption) }
}
[export]
def main(smoke:bool):int { return 0 }
