options gen2
module live_state public
require live_host public
require math
require daslib/json_boost public
require dasrmlui/state_types

// Store contains JSON text, never VM pointers. Prefix participates in LiveHost's
// Shift+F5/full-reset policy. Reading a snapshot does not consume or mutate it.
def private rt_live_key(key:string):string { return "__live_vars_ui/{key}" }

// Use field names, independently of application JSON annotations.
def rt_live_json(value:auto):JsonValue? {
    static_if (typeinfo is_pointer(value) || typeinfo is_lambda(value) || typeinfo is_function(value)) {
        panic("Live UI state cannot contain pointers or callbacks")
        return null
    } static_elif (typeinfo is_struct(value) || typeinfo is_tuple(value) || typeinfo is_variant(value)) {
        var fields:table<string;JsonValue?>
        apply(value) $(name:string; field) { fields[name]=rt_live_json(field) }
        static_if (typeinfo is_variant(value)) {
            fields["$variant"]=JV(variant_index(value))
            fields["$type"]=JV(typeinfo typename(type<typedecl(value) -const -&>))
        }
        return JV(fields)
    } static_elif (typeinfo is_array(value) || typeinfo is_dim(value)) {
        var items:array<JsonValue?>
        for (item in value) { items |> push(rt_live_json(item)) }
        return JV(items)
    } else { return _::JV(value) }
}

def rt_live_json(value:table<auto(K);auto(V)>):JsonValue? {
    var items:array<JsonValue?>
    for (key,item in keys(value),values(value)) {
        items |> push(JV({"key" => rt_live_json(key), "value" => rt_live_json(item)}))
    }
    return JV(items)
}

def rt_live_save(key:string; version:int; value:auto) {
    if (!is_live_mode()) { return }
    var json=rt_live_json(value)
    var envelope=JV({"version" => JV(version), "value" => json})
    live_store_string(rt_live_key(key),write_json(envelope))
    delete_json(envelope)
}

def rt_live_forget(key:string) { if (is_live_mode()) { live_store_string(rt_live_key(key),"") } }

// Same-version changes are merged by field name, keeping the current initializer
// for absent fields. For an incompatible change increment the explicit version.
def rt_live_merge(var value:auto&; saved:JsonValue const?) {
    if (saved==null) { return }
    static_if (typeinfo is_struct(value) || typeinfo is_tuple(value)) {
        if (!(saved.value is _object)) { return }
        apply(value) $(name:string; var field) {
            let old=(saved.value as _object)?[name] ?? null
            if (old!=null) { rt_live_merge(field,old) }
        }
    } static_elif (typeinfo is_array(value)) {
        if (!(saved.value is _array)) { return }
        clear(value)
        for (old in saved.value as _array) {
            var item := default<typedecl(value[0]) -const -&>
            rt_live_merge(item,old)
            value |> push_clone(item)
            static_if (typeinfo can_delete(item)) { delete item }
        }
    } static_elif (typeinfo is_dim(value)) {
        if (!(saved.value is _array)) { return }
        for (i in range(min(length(value),length(saved.value as _array)))) { rt_live_merge(value[i],(saved.value as _array)[i]) }
    } static_elif (typeinfo is_variant(value)) {
        // Keep raw variant layout out of the store. Validate tag/type before the
        // upstream JSON converter creates the newly owned value.
        let index=saved?["$variant"] ?? -1
        let info=typeinfo rtti_typeinfo(value)
        if (index<0 || index>=int(info.argCount) || (saved?["$type"] ?? "")!=typeinfo typename(type<typedecl(value) -const -&>)) {
            panic("Live state variant changed; increment the schema and provide ui_migrate")
        }
        var restored := default<typedecl(value) -const -&>
        unsafe { set_variant_index(restored,index) }
        apply(restored) $(name:string; var field) { rt_live_merge(field,saved?[name]) }
        move_to_ref(value,restored)
    } static_elif (typeinfo is_pointer(value) || typeinfo is_lambda(value) || typeinfo is_function(value)) {
        panic("Live UI state cannot contain pointers or callbacks")
    } else {
        // Scalar/vector conversions preserve defaults on a mismatched JSON kind.
        value = _::from_JV(saved,decltype_noref(value),value)
    }
}

def rt_live_merge(var value:table<auto(K);auto(V)>; saved:JsonValue const?) {
    if (saved==null || !(saved.value is _array)) { return }
    clear(value)
    for (old in saved.value as _array) {
        var key := default<K>
        var item := default<V>
        rt_live_merge(key,old?["key"])
        rt_live_merge(item,old?["value"])
        value |> insert_clone(key,item)
        static_if (typeinfo can_delete(item)) { delete item }
    }
}

// Overload in the application for each versioned model/local state type.
// Return false to reject the reload; the host restores the last good program.
[unused_argument(saved,old_version,value)]
def ui_migrate(saved:JsonValue const?; old_version:int; var value:auto&):bool { return false }

def rt_live_restore(key:string; version:int; var value:auto&) {
    if (!is_live_mode()) { return }
    var text:string
    if (!live_load_string(rt_live_key(key),text) || empty(text)) { return }
    var error:string
    var envelope=read_json(text,error)
    if (envelope==null || !empty(error)) { panic("Invalid live state snapshot: {key}") }
    let old_version=envelope?["version"] ?? 0
    let saved=envelope?["value"]
    if (old_version==version) { rt_live_merge(value,saved) }
    else {
        let accepted=_::ui_migrate(saved,old_version,value)
        if (!accepted) { delete_json(envelope); panic("Live state migration rejected: {key} ({old_version} -> {version})") }
    }
    delete_json(envelope)
}

typedef UiLiveSave = lambda<():void>
var private live_roots:table<string;UiLiveSave>

def rt_live_attach(key:string; version:int; state:$UiState<auto(T)>?) {
    if (!is_live_mode()) { return }
    if (key_exists(live_roots,key)) { panic("Duplicate live ui_state key: {key}; use an explicit unique name") }
    live_roots[key] = @() {
        state->read() $(value:T) { rt_live_save("root/{key}",version,value) }
    }
}

def rt_live_save_roots() { for (save in values(live_roots)) { invoke(save) } }
