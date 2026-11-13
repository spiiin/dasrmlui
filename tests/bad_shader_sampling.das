options gen2
require dasrmlui/shaders
def helper(uv:float2):float4 { return sample_source(uv) }
[ui_shader]
def broken(uv:float2):float4 { return helper(uv) }
[export]
def main(smoke:bool):int { return 0 }
