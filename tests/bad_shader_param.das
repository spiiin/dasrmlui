options gen2
require dasrmlui/shaders
[ui_shader]
def broken(amount:int):float4 { return float4(float(amount)) }
[export]
def main(smoke:bool):int { return 0 }
