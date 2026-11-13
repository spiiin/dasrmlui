options gen2
require dasrmlui/ui
[ui_component]
def screen(model:UiDataModel) {
    native_data("form",model) { when(true) { text("caption","Hello") } }
}
[export]
def main(smoke:bool):int { return 0 }
