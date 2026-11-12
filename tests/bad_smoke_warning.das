options gen2
options persistent_heap
options gc
options stack = 65536
require examples/demo_host

// Guards the guard: the demo host must fail a smoke run in which RmlUi
// reported a warning. Here the cause is a mistyped property name.
[ui_component]
def screen() {
    column("screen") {
        property("widht","10px")
        text("caption","A mistyped property")
    }
}

[export]
def main(smoke:bool):int {
    return run_demo("dasrmlui - smoke warning","logs/bad_smoke_warning.png",smoke,$() { screen() }) $(frame:int) {}
}
