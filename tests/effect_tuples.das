options gen2
options persistent_heap
options gc
options stack = 65536
require examples/gl_demo_host
require shader_dsl_effects
require strings

struct Tuning { amount:float=1.; violet:bool }
tuple EmptyEffect {}
struct Model { tuning:Tuning=Tuning(); amount:float=0.5; glass:float=0.6; progress:float=0.7; chain:float=0.8; unrelated:int }
var evaluations:int[5]
var mounts,created,destroyed:int
var painted_amount:float
var painted_asset:string

def measured(value:float; index:int):float { evaluations[index]+=1; return value }
def assert_counts(a,b,c,d,e:int) {
    verify(evaluations[0]==a && evaluations[1]==b && evaluations[2]==c && evaluations[3]==d && evaluations[4]==e,
        "only the binding whose tuple reads changed may evaluate")
    verify(mounts==1,"tuple edits must not remount the component")
}
def decorator(event:UiDecoratorEvent) {
    if (event.kind==UiDecoratorKind.Create) { created+=1 }
    elif (event.kind==UiDecoratorKind.Destroy) { destroyed+=1 }
    else {
        painted_amount=decorator_number(event.canvas,"amount")
        painted_asset=decorator_string(event.canvas,"asset")
        let ink=decorator_color(event.canvas,"fill")
        verify(abs(ink.alpha-0.5)<0.01)
        verify(decorator_length(event.canvas,"edge",event.size.x)==20.)
        native_rect(event.canvas,float4(0.,0.,event.size.x,event.size.y),ink.ink,ink.alpha)
    }
}
def install() {
    register_shader("tuple-solid",solid_shader(),(tint=rgb(40,200,100),amount=1.))
    register_filter("tuple-red",red_filter(),(amount=0.5),4.)
    register_decorator("tuple-paper",(fill=effect_color(rgb(40,200,100),0.5),edge=pct(25),amount=1,asset="default"),@@decorator)
    // Capturing handlers and the ordinary static function overload both accept tuples.
    let seed="owned"
    register_decorator("tuple-captured",(amount=1.),@(event:UiDecoratorEvent) { verify(seed=="owned") })
    unsafe { heap_collect(true,false) }
    verify(unregister_decorator("tuple-captured"))
    // Empty tuples, omitted arguments and explicit arrays retain their meanings.
    let empty_params=EmptyEffect()
    register_filter("tuple-empty",swap_filter(),empty_params,2.)
    verify(filter_effect("tuple-empty",empty_params).value==filter_effect("tuple-empty").value)
    verify(unregister_filter("tuple-empty"))
    register_shader("tuple-hyphen",named_param_shader(),(edge_width=1.))
    let counts=gpu_effect_counts()
    var caught=false
    try { filter_effect("tuple-red",(typo=1.)) } recover { caught=true }
    verify(caught,"unknown tuple fields are checked against the registered schema")
    caught=false
    try { filter_effect("tuple-red",(amount=rgb(1,2,3))) } recover { caught=true }
    verify(caught,"a supported value type must still match the registered parameter")
    caught=false
    try { register_shader("tuple-invalid",solid_shader(),(tint=1.,amount=1.)) } recover { caught=true }
    verify(caught && gpu_effect_counts()==counts)
    caught=false
    try { register_filter("tuple-invalid",red_filter(),(typo=1.)) } recover { caught=true }
    verify(caught && gpu_effect_counts()==counts)
    caught=false
    try { register_filter("tuple-invalid","unused",(asset="unsupported")) } recover { caught=true }
    verify(caught && gpu_effect_counts()==counts)
    let normal=filter_effect("tuple-red",(amount=0.5)).value
    verify(normal==filter_effect("tuple-red",array<UiEffectArg>(effect_arg("amount",0.5))).value)
}
[ui_style]
def sheet() {
    rule("body") { width(px(1200)); height(px(820)); background(rgb(0,0,0)) }
    rule("div") { width(px(80)); height(px(40)); background(rgb(40,200,100)) }
}
[ui_component]
def screen(var model:Model) {
    on_mount() { mounts+=1 }
    use_style(@@sheet)
    box("shader") {
        custom_shader("tuple-solid",(amount=measured(model.tuning.amount,0),tint=model.tuning.violet ? rgb(180,90,230) : rgb(40,200,100)),"content-box")
    }
    box("filter") { custom_filter("tuple-red",(amount=measured(model.amount,1))) }
    box("backdrop") { custom_backdrop_filter("tuple-red",(amount=measured(model.glass,2))) }
    box("decorator") { custom_decorator("tuple-paper",(amount=measured(model.progress,3),asset="named tuple"),"border-box") }
    box("chain") {
        custom_filters(array<UiFilterEffect>(filter_effect("tuple-red",(amount=measured(model.chain,4))),filter_effect("tuple-red",(amount=0.5))))
    }
    box("constant") { custom_shader("tuple-hyphen",(edge_width=2.)) }
    box("constant-color") { custom_shader("tuple-solid",(tint=effect_color(rgb(40,200,100),0.5))) }
}
[export]
def main(smoke:bool):int {
    var state=ui_state(Model())
    var installed=false
    var original,changed:string
    let result=run_gl_demo("Named effect tuples","logs/effect_tuples.png",true,$(dt:float) {
        if (!installed) { install(); installed=true }
    },$() { ui_frame(state) $(model:Model) { screen(model) } },$(frame:int) {
        if (frame==0) {
            assert_counts(1,1,1,1,1)
            verify(painted_amount==0.7 && painted_asset=="named tuple","decorator tuple overrides reach the renderer")
            verify(find(rui_local_property(ui_find("constant"),"decorator"),"tuple-hyphen(2)")>=0)
            original=rui_local_property(ui_find("shader"),"decorator")
            ui_clear_stats()
        } elif (frame==1) {
            assert_counts(1,1,1,1,1); verify(ui_stats().binding_updates==0)
            ui_edit(state) $(var model:Model) { model.unrelated++ }
        } elif (frame==2) {
            assert_counts(1,1,1,1,1); verify(ui_stats().binding_updates==0)
            ui_edit(state) $(var model:Model) { model.tuning.amount=0.25 }
        } elif (frame==3) {
            assert_counts(2,1,1,1,1); verify(ui_stats().binding_updates==1)
            changed=rui_local_property(ui_find("shader"),"decorator"); verify(changed!=original)
            ui_clear_stats()
            ui_edit(state) $(var model:Model) { model.tuning.amount=0.25 }
        } elif (frame==4) {
            assert_counts(2,1,1,1,1); verify(ui_stats().binding_updates==0)
            ui_edit(state) $(var model:Model) { model.tuning.violet=true }
        } elif (frame==5) {
            assert_counts(3,1,1,1,1); verify(ui_stats().binding_updates==1)
            verify(rui_local_property(ui_find("shader"),"decorator")!=changed)
            ui_clear_stats(); ui_edit(state) $(var model:Model) { model.amount=0.2 }
        } elif (frame==6) {
            assert_counts(3,2,1,1,1); verify(ui_stats().binding_updates==1)
            ui_clear_stats(); ui_edit(state) $(var model:Model) { model.glass=0.3 }
        } elif (frame==7) {
            assert_counts(3,2,2,1,1); verify(ui_stats().binding_updates==1)
            ui_clear_stats(); ui_edit(state) $(var model:Model) { model.progress=0.4 }
        } elif (frame==8) {
            assert_counts(3,2,2,2,1); verify(ui_stats().binding_updates==1 && painted_amount==0.4)
            ui_clear_stats(); ui_edit(state) $(var model:Model) { model.chain=0.1 }
        } elif (frame==9) {
            assert_counts(3,2,2,2,2); verify(ui_stats().binding_updates==1)
            ui_clear_stats(); unsafe { heap_collect(true,false) }
        } else { assert_counts(3,2,2,2,2); verify(ui_stats().binding_updates==0) }
    })
    verify(created>0 && created==destroyed && decorator_handler_count()==0 && gpu_effect_counts()==int2(0))
    print("PASS: named effect tuples, registration, schema errors, isolated dependencies, equal writes, idle and GC\n")
    return result
}
