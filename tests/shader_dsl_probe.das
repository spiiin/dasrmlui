options gen2
require dasrmlui/shaders
require math
require strings
require shader_dsl_effects
[ui_shader]
def gradient(uv:float2; time:float; tint:float4):float4 {
    return float4(tint.xyz*(0.5+0.5*sin(time+uv.x*6.)),tint.w)
}
[ui_filter]
def gray(uv:float2; amount:float):float4 {
    let c=sample_source(uv)
    return float4(lerp(c.xyz,float3(dot(c.xyz,float3(0.21,0.72,0.07))),amount),c.w)
}
[ui_shader]
def effect(uv:float2):float4 { return float4(uv,0.5,1.) }
[export]
def main(smoke:bool):int {
    let g=gradient_shader(); let f=gray_filter()
    verify(!g.filter && f.filter)
    verify(g.signature=="tint:c;" && f.signature=="amount:f;")
    verify(find(g.source,"vec4 gradient")>=0 && find(g.source,"u_time, p_tint")>=0)
    verify(find(g.source,"#version")<0 && find(g.source,"void main")<0,"native ABI supplies header and main")
    verify(find(f.source,"texture(_source")>=0 && find(f.source,"_source_bounds")>=0)
    verify(find(effect_shader().source,"return effect(uv)")>=0,"entry may be named effect")
    verify(find(solid_shader().source,"solid_in_shader_dsl_effects")>=0,"imported module entry")
    verify(find(solid_shader().source,"struct Shade")>=0,"helper structs and loops reach the emitter")
    verify(named_param_shader().signature=="edge_width:f;")
    verify(gradient_shader().source==g.source,"descriptor reuses a compile-time string")
    print("PASS: dasGlsl source, descriptors, signatures, module helpers, structs and builtins\n")
    return 0
}
