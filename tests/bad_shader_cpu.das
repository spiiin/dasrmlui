options gen2
require dasrmlui/shaders
[ui_shader]
def broken(uv:float2):float4 {
    var values:array<float>
    values |> push(uv.x)
    return float4(values[0])
}
[export]
def main(smoke:bool):int { return 0 }
