options gen2
require dasrmlui/ui

// A radius is a length. Passing a colour must not compile.
[ui_style]
def broken_style() {
    rule(root()) { border_radius(rgb(1,2,3)) }
}

[export]
def main(smoke:bool):int { return 0 }
