options gen2
require dasrmlui/macros

var phase, dependency_checks, bodies, texts, retained : int
def rt_dependency(value:int) { dependency_checks += 1 }
def rt_named_dependency(name:string; value:int) { rt_dependency(value) }
def rt_binding(site:string; deps:block; volatile_read,input:bool; body:block) { invoke(body) }
def rt_component(name:string; deps, mount_body, update_body, dispatch_body:block) {
    invoke(deps)
    if (phase == 0) { invoke(mount_body) }
    elif (phase == 1) { invoke(update_body) }
    else { invoke(dispatch_body) }
}
def text(site,name,value:string) { texts += 1 }
def rt_static_text(site,name,value:string) { retained += 1 }
def record(value:int) { bodies += value }
[ui_component(dump=true)]
def probe(value:int) { record(value); text("hello","macro works") }
[export]
def main(smoke:bool):int {
    probe(1)
    phase = 1; probe(2)
    phase = 2; probe(3)
    verify(bodies == 6 && dependency_checks == 3)
    verify(texts == 1 && retained == 1, "Generated update must retain static text; dispatch must omit it")
    print("PASS: generated mount/update/dispatch and argument forwarding\n")
    return 0
}

