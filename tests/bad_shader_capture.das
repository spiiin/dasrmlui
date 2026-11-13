options gen2
require dasrmlui/shaders
var cpu_gain=0.5
def helper():float { return cpu_gain }
[ui_shader]
def broken(uv:float2):float4 { return float4(uv,helper(),1.) }
[export]
def main(smoke:bool):int { return 0 }
