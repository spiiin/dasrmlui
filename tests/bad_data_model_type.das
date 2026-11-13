options gen2
require dasrmlui/ui

[export]
def main(smoke:bool):int {
    let model=UiDataModel()
    var pointer:int?
    ui_data_bind(model,"unsupported",pointer)
    return 0
}
