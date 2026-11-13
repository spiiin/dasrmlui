options gen2
require dasrmlui/ui
def paint(event:UiDecoratorEvent) {}
[export]
def main(smoke:bool):int {
    register_decorator("test-effect",(amount=true),@@paint)
    return 0
}
