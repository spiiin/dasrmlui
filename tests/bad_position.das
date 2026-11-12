options gen2
require dasrmlui/ui

// A keyword helper names the accepted values as soon as the style is first
// used, instead of leaving a mistyped one to RmlUi's parser.
[ui_style]
def broken_style() {
    rule(root()) { position("absolut") }
}

[export]
def main(smoke:bool):int {
    use_style(@@broken_style)
    return 0
}
