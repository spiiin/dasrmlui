options gen2
require dasrmlui/ui
[ui_component]
def screen(model:UiDataModel) {
    native_data("form",model) { native_data("nested",model) { text("caption","Hello") } }
}
[export]
def main(smoke:bool):int { return 0 }
