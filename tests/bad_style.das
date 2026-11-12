options gen2
require dasrmlui/ui

[ui_style]
def invalid_style() {
    rule(root()) { width(rgb(255,0,0)) }
}
[export]
def main(smoke:bool) : int { return 0 }
