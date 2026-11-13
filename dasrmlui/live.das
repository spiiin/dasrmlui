options gen2
module live public
require dasrmlui/ui public
require live/live_vars public

def ui_live_window(title:string; width:int=1100; height:int=760; gl3:bool=false) {
    verify(is_live_mode(),"Run this script with --watch")
    verify(rui_live_open(title,width,height,gl3),"Unable to create SDL3/RmlUi live window (renderer mode cannot change on reload)")
}
