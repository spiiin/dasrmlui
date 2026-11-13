options gen2
// dasGlsl treats glsl_* globals as externally supplied shader builtins.
module glsl_ui_builtins shared public
require daslib/shader_lingua_franca public
require math public

var _source:sampler2D
var _source_bounds:float4
var _viewport:float2

// Native filter input uses premultiplied RGBA and bottom-left framebuffer UV.
// Public sampling returns straight RGBA in the local, top-left filter region.
def sample_source(uv:float2):float4 {
    if (uv.x<0. || uv.y<0. || uv.x>1. || uv.y>1.) { return float4(0.) }
    let pixel=clamp(_source_bounds.xy+uv*_source_bounds.zw,_source_bounds.xy+float2(0.5),_source_bounds.xy+_source_bounds.zw-float2(0.5))
    let color=texture(_source,float2(pixel.x/_viewport.x,1.-pixel.y/_viewport.y))
    return color.w>0. ? float4(color.xyz/color.w,color.w) : float4(0.)
}
