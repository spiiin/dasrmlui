options gen2
module shader_lab_effects public
require dasrmlui/shaders public
require math

[ui_shader]
def aurora(uv:float2; size:float2; time:float; speed:float; tint:float4):float4 {
    let q=(uv-float2(0.5))*float2(size.x/size.y,1.)
    let t=time*speed*0.4
    let r=length(q)
    let a=atan2(q.y,q.x)
    let wave=sin(18.*r-3.*a+t*3.+sin(a*3.-t)*1.4)
    let ribbon=pow(0.5+0.5*wave,5.)
    let glow=exp(-4.*abs(r-0.27))
    let hue=lerp(tint.xyz,float3(0.95,0.26,0.5),0.5+0.5*sin(a+t))
    var col=float3(0.025,0.035,0.08)+hue*(ribbon*0.9+glow*0.16)
    col*=1.-smoothstep(0.18,0.8,r)
    col+=float3(0.02,0.04,0.08)*step(0.96,fract(uv.y*size.y/6.))
    return float4(col,1.)
}

[ui_filter]
def prism(uv:float2; texel:float2; split:float):float4 {
    let offset=float2(split,0.)*texel
    let center=sample_source(uv)
    let left=sample_source(uv-offset)
    let right=sample_source(uv+offset)
    return float4(left.x,center.y,right.z,max(center.w,max(left.w,right.w)))
}

[ui_filter]
def glass(uv:float2; texel:float2; radius:float):float4 {
    let d=texel*radius
    let c=(sample_source(uv)+sample_source(uv+float2(d.x,0.))+
        sample_source(uv-float2(d.x,0.))+sample_source(uv+float2(0.,d.y))+
        sample_source(uv-float2(0.,d.y)))*0.2
    let l=dot(c.xyz,float3(0.21,0.72,0.07))
    return float4(lerp(float3(l),c.xyz,0.2)*0.65+float3(0.08,0.12,0.2),c.w)
}

def install_effects() {
    register_shader("lab-aurora",aurora_shader(),array<UiEffectParam>(
        effect_number_param("speed",1.),effect_color_param("tint",rgb(46,232,210))))
    register_filter("lab-prism",prism_filter(),array<UiEffectParam>(effect_length_param("split",dp(6))),20.)
    register_filter("lab-glass",glass_filter(),array<UiEffectParam>(effect_length_param("radius",dp(5))))
}
