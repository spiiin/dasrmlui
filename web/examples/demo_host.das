options gen2
module demo_host public
require dasrmlui/ui public

def run_demo(title,screenshot:string; smoke:bool; render:block; check:block<(frame:int):void>):int {
    var frame=0
    let result=rui_web_run(title,$(dt:float) {},$() {
        invoke(render); frame+=1; ui_collect_garbage(8,frame%120==0)
    })
    ui_reset(); rui_shutdown()
    return result
}
