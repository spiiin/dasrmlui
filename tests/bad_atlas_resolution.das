options gen2
require dasrmlui/ui
[ui_style]
def invalid_style() { spritesheet("unused.png",0.) { sprite("invalid",0,0,10,10) } }
[export]
def main(smoke:bool):int { use_style(@@invalid_style); return 0 }
