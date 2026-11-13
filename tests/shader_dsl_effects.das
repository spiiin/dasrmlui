options gen2
module shader_dsl_effects public
require dasrmlui/shaders public

let HALF=0.5
struct Shade { rgb:float3; alpha:float }
def shade(tint:float4; amount:float):Shade {
    var color=float3(0.)
    for (i in range(2)) { color+=tint.xyz*amount*HALF }
    return Shade(rgb=color,alpha=tint.w)
}
[ui_shader]
def solid(tint:float4; amount:float):float4 {
    let c=shade(tint,amount)
    return float4(c.rgb,c.alpha)
}
[ui_shader]
def edge(uv,size:float2; edge:float):float4 {
    return uv.x*size.x<edge ? float4(1.,0.,0.,1.) : float4(0.,1.,0.,1.)
}
[ui_shader]
def clock(time:float):float4 { return float4(fract(time*0.25),0.,0.,1.) }
[ui_filter]
def swap(uv:float2):float4 { let c=sample_source(uv); return float4(c.z,c.y,c.x,c.w) }
[ui_filter]
def red(uv:float2; amount:float):float4 { var c=sample_source(uv); c.x*=amount; return c }
[ui_filter]
def shift(uv,texel:float2):float4 { return sample_source(uv-float2(4.,0.)*texel) }
[ui_shader]
def named_param(edge_width:float):float4 { return float4(edge_width) }

def install_shader_fixture() {
    register_shader("test-solid",solid_shader(),array<UiEffectParam>(effect_color_param("tint",rgb(40,200,100)),effect_number_param("amount",1.)))
    register_shader("test-edge",edge_shader(),array<UiEffectParam>(effect_length_param("edge",dp(4))))
    register_shader("test-clock",clock_shader())
    register_filter("test-swap",swap_filter())
    register_filter("test-red",red_filter(),array<UiEffectParam>(effect_number_param("amount",0.5)))
    register_filter("test-shift",shift_filter(),8.)
    // Schema checks happen before creating native registrations or GL programs.
    let counts=gpu_effect_counts()
    var caught=false
    try { register_shader("test-invalid-dsl",solid_shader()) } recover { caught=true }
    verify(caught && gpu_effect_counts()==counts)
    caught=false
    try { register_shader("test-invalid-dsl",clock_shader(),array<UiEffectParam>(effect_number_param("extra",1.))) } recover { caught=true }
    verify(caught && gpu_effect_counts()==counts)
    caught=false
    try { register_shader("test-invalid-dsl",solid_shader(),array<UiEffectParam>(effect_number_param("tint",1.),effect_number_param("amount",1.))) } recover { caught=true }
    verify(caught && gpu_effect_counts()==counts)
    caught=false
    try { register_filter("test-invalid-dsl",clock_shader()) } recover { caught=true }
    verify(caught && gpu_effect_counts()==counts)
    caught=false
    try { register_shader("test-invalid-dsl",swap_filter()) } recover { caught=true }
    verify(caught && gpu_effect_counts()==counts)
    caught=false
    try { register_shader("test-invalid-dsl",named_param_shader(),array<UiEffectParam>(effect_number_param("edge-width",1.),effect_number_param("edge-width",2.))) } recover { caught=true }
    verify(caught && gpu_effect_counts()==counts)
    register_shader("test-dsl-name",named_param_shader(),array<UiEffectParam>(effect_number_param("edge-width",1.)))
    verify(unregister_shader("test-dsl-name") && gpu_effect_counts()==counts)
    unsafe { heap_collect(true,false) }
}
