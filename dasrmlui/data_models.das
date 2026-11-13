options gen2
module data_models public
require rml_native public
require daslib/apply
require daslib/rtti

struct UiDataModel { handle:uint64 }
struct UiDataArgument { text:string; integer:int64; number:double; boolean:bool }
struct UiDataEvent { name:string; kind:string; target:uint64; arguments:array<UiDataArgument> }

def ui_data_model(name:string):UiDataModel { return UiDataModel(handle=rui_data_create(name)) }
def ui_data_alive(model:UiDataModel):bool { return rui_data_alive(model.handle) }
def ui_data_close(model:UiDataModel):bool { return rui_data_remove(model.handle) }
def ui_data_exists(name:string):bool { return rui_data_context_has(name) }
def ui_data_model_count():int { return rui_data_context_count() }
def ui_data_debugger():bool { return rui_debugger_models() }

def rt_data_emit(stage,parent:uint64; name,value:string) {
    let node=rui_data_node(stage,parent,name,0); rui_data_string(stage,node,value)
}
def rt_data_emit(stage,parent:uint64; name:string; value:bool) {
    let node=rui_data_node(stage,parent,name,1); rui_data_bool(stage,node,value)
}
def rt_data_emit(stage,parent:uint64; name:string; value:int | uint | int8 | uint8 | int16 | uint16 | int64) {
    let node=rui_data_node(stage,parent,name,2); rui_data_int(stage,node,int64(value))
}
def rt_data_emit(stage,parent:uint64; name:string; value:uint64) {
    verify(value<=9223372036854775807ul,"DataModel: unsigned integer exceeds native signed range")
    let node=rui_data_node(stage,parent,name,2); rui_data_int(stage,node,int64(value))
}
def rt_data_emit(stage,parent:uint64; name:string; value:float | double) {
    let node=rui_data_node(stage,parent,name,3); rui_data_number(stage,node,double(value))
}
def rt_data_emit(stage,parent:uint64; name:string; value:auto(T)) {
    static_if (typeinfo is_array(value)) {
        let node=rui_data_node(stage,parent,name,4)
        for (item in value) { _::rt_data_emit(stage,node,"",item) }
    } static_elif (typeinfo is_struct(value)) {
        let node=rui_data_node(stage,parent,name,5)
        apply(value) $(member,field) { _::rt_data_emit(stage,node,member,field) }
    } static_elif (typeinfo is_enum(value)) {
        _::rt_data_emit(stage,parent,name,int64(value))
    } else {
        static_assert(false,"DataModel supports scalar values, structs and arrays; pointers/closures are not bindings")
    }
}
def private data_write(model:UiDataModel; path:string; value:auto; binding,writable:bool) {
    let stage=rui_data_begin(model.handle,path,binding,writable)
    try { rt_data_emit(stage,0ul,"",value); rui_data_commit(stage) } recover {
        let message=string(this_context().last_exception)
        rui_data_abort(stage); panic(message)
    }
}
// Native-owned copies. Set is atomic and dirties the containing root variable.
def ui_data_bind(model:UiDataModel; name:string; value:auto; writable:bool=false) { data_write(model,name,value,true,writable) }
def ui_data_set(model:UiDataModel; path:string; value:auto) { data_write(model,path,value,false,false) }
def ui_data_text(model:UiDataModel; path:string):string { return rui_data_get_string(model.handle,path) }
def ui_data_int(model:UiDataModel; path:string):int64 { return rui_data_get_int(model.handle,path) }
def ui_data_number(model:UiDataModel; path:string):double { return rui_data_get_number(model.handle,path) }
def ui_data_bool(model:UiDataModel; path:string):bool { return rui_data_get_bool(model.handle,path) }
def ui_data_size(model:UiDataModel; path:string):int { return rui_data_size(model.handle,path) }
def ui_data_dirty(model:UiDataModel; name:string) { rui_data_dirty(model.handle,name) }
def ui_data_dirty_all(model:UiDataModel) { rui_data_dirty_all(model.handle) }
def ui_data_is_dirty(model:UiDataModel; name:string):bool { return rui_data_is_dirty(model.handle,name) }
def ui_data_on(model:UiDataModel; name:string) { rui_data_on(model.handle,name) }

// Snapshot the queue length. Events raised by this block wait for the next drain.
// The block and its captures are borrowed only for this call, never held by C++.
def ui_data_events(model:UiDataModel; body:block<(event:UiDataEvent):void>) {
    let count=rui_data_event_begin(model.handle)
    try {
        for (i in range(count)) {
            if (!ui_data_alive(model) || !rui_data_event_next(model.handle)) { break }
            var inscope event=UiDataEvent(name=rui_data_event_name(model.handle),kind=rui_data_event_type(model.handle),target=rui_data_event_target(model.handle))
            for (arg in range(rui_data_event_count(model.handle))) {
                event.arguments |> push(UiDataArgument(text=rui_data_event_string(model.handle,arg),number=rui_data_event_number(model.handle,arg),
                    integer=rui_data_event_int(model.handle,arg),boolean=rui_data_event_bool(model.handle,arg)))
            }
            invoke(body,event)
        }
    } recover {
        let message=string(this_context().last_exception)
        rui_data_event_end(model.handle); panic(message)
    }
    rui_data_event_end(model.handle)
}

def ui_load_rml(path:string; visible:bool=true):uint64 { return rui_document_file(path,visible) }
