options gen2
require dasrmlui/shaders
[ui_shader]
def broken(var amount:float):float4 { amount+=1.; return float4(amount) }
[export]
def main(smoke:bool):int { return 0 }
