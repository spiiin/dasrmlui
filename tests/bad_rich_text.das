options gen2
require dasrmlui/ui
[ui_component(legacy=true)]
def invalid() { link("missing_target") {} }
[export]
def main(smoke:bool):int { return 0 }
