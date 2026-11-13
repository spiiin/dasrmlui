options gen2
require dasrmlui/ui
[ui_component]
def screen() { text_input("edit") { data_value("person.name") } }
[export]
def main(smoke:bool):int { return 0 }
