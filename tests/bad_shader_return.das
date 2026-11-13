options gen2
require dasrmlui/shaders
[ui_shader]
def broken(uv:float2):float3 { return float3(uv,1.) }
[export]
def main(smoke:bool):int { return 0 }
