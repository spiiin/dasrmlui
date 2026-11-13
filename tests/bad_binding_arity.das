options gen2
require dasrmlui/ui

struct Model { units:int }

// Missing limits, commit mode and setter: the compiler must name the overload
// at this line instead of the annotation failing on an argument index.
[ui_component(legacy=true)]
def screen(var model:Model) {
    text_input("units") { bind_int(model.units) }
}

[export]
def main(smoke:bool):int { return 0 }
