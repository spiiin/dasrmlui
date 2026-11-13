options gen2
require dasrmlui/shaders
[ui_filter]
def broken(amount:float=0.5):float4 { return float4(amount) }
[export]
def main(smoke:bool):int { return 0 }
