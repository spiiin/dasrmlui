options gen2
module gl_demo_host public
require dasrmlui/ui public
require math

def run_gl_demo(title,screenshot:string; smoke:bool; tick:block<(delta:float):void>; render:block; check:block<(frame:int):void>):int {
    var frame=0
    let result=rui_web_run(title,tick,$() {
        invoke(render); frame+=1; ui_collect_garbage(8,frame%120==0)
    })
    ui_reset(); rui_shutdown()
    return result
}
