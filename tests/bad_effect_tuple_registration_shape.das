options gen2
require dasrmlui/ui
[export]
def main(smoke:bool):int {
    register_filter("test-effect","source",(1.,2.))
    return 0
}
