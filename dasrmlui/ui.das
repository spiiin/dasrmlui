options gen2
module ui public
require rml_native public
require dasrmlui/macros public
require strings
require daslib/apply
require math
require daslib/strings_convert
require daslib/strings_boost

enum UiNativeKind {
    Create
    Attribute
    Property
    Resize
    Update
    Paint
    Destroy
}
struct UiNativeEvent { element:uint64; kind:UiNativeKind; name:string; size:float2; time:double }
typedef UiNativeHandler = lambda<(event:UiNativeEvent):void>
// GC roots own captured values. C++ retains only this static dispatcher.
var private native_handlers:table<uint64;UiNativeHandler>
def private native_dispatch(registration,element:uint64; kind:int; name:string) {
    if (kind==7) { native_handlers |> erase(registration); return }
    if (key_exists(native_handlers,registration)) {
        let phase=(kind==0 ? UiNativeKind.Create : kind==1 ? UiNativeKind.Attribute : kind==2 ? UiNativeKind.Property :
            kind==3 ? UiNativeKind.Resize : kind==4 ? UiNativeKind.Update : kind==5 ? UiNativeKind.Paint : UiNativeKind.Destroy)
        let event=UiNativeEvent(element=element,kind=phase,name=name,size=rui_native_size(element),time=rui_native_time())
        invoke(native_handlers[registration],event)
    }
}
def register_native_element(tag:string; handler:UiNativeHandler; intrinsic:float2=float2(0.); continuous:bool=false):uint64 {
    if (handler==null) { panic("Native element requires a handler") }
    let registration=rui_native_register(tag,@@native_dispatch,intrinsic,continuous)
    if (registration==0ul) { panic("Native registration requires an initialized context, a unique lower-case name containing '-', and a finite positive intrinsic size (or 0,0)") }
    native_handlers[registration]=handler
    return registration
}
def register_native_element(tag:string; handler:function<(event:UiNativeEvent):void>; intrinsic:float2=float2(0.); continuous:bool=false):uint64 {
    if (handler==null) { panic("Native element requires a handler") }
    return register_native_element(tag,@(event:UiNativeEvent) { invoke(handler,event) },intrinsic,continuous)
}
def native_registered(tag:string):bool { return rui_native_registration(tag)!=0ul }
def unregister_native_element(tag:string):bool { return rui_native_unregister(tag) }
def native_instance_count(tag:string):int { return rui_native_live(tag) }
def native_handler_count():int { return length(native_handlers) }
def native_invalidate(element:uint64) { rui_native_invalidate(element) }
def native_set_intrinsic(element:uint64; size:float2) {
    if (!rui_native_intrinsic(element,size)) { panic("Native intrinsic size requires a live native element and finite positive dimensions") }
}

struct private UiComponentState {
    seen : int
    dirty : bool
    bindings_dirty : bool
    dependencies : string
    node_keys : array<string>
    children : array<string>
    binding_keys : array<string>
    handler_keys : array<string>
}
struct UiStats { mounts, updates, skips, dispatches, binding_mounts, binding_updates, binding_skips, computed_updates, computed_skips : int }
struct private UiBindingState {
    seen : int
    dependencies : string
    node_keys : array<string>
}
var private bindings : table<string;UiBindingState>
var private conditions : table<string;bool>
var private visited_bindings : array<string>
var private force_bindings = false
var private stats = UiStats()
var private components : table<string; UiComponentState>
var private visited_nodes : array<string>
var private visited_components : array<string>
var private dependency_parts : array<string>
struct UiSignal { id : uint64 }
struct UiAnimation { name,easing:string; seconds:float; iterations:int=1; alternate:bool }
struct private UiAnimationBinding { signature:string; generation:uint64 }
struct private UiPresence { owner:string; handle,generation:uint64; exiting:bool }
var private animation_bindings:table<uint64;UiAnimationBinding>
var private presences:table<string;UiPresence>
struct private UiTemplateDefinition {
    name, source, css_source, markup, css, root_class, root_properties, title, native_tags : string
}
struct private UiTemplateNode { tag,id,classes,properties,attributes,children:string }
var private templates : table<string;UiTemplateDefinition>
var private template_stack : array<UiTemplateNode>
var private template_ids : table<string;bool>
var private template_sheets : array<string>
var private template_building=false
var private template_definition=UiTemplateDefinition()
var private template_previous_style=""
var private template_selected=""
var private template_has_root=false
struct private UiSubscription { signal : uint64; owner, ancestor : string }
var private signal_id : uint64
var private subscriptions : array<UiSubscription>
var private component_stack : array<string>
var private mounting = true
var private active_component = ""
var private first_mount = false
var private unmounting = false
struct private UiTeardown {
    owner, key : string
    cleanup : function<(key:string):void>
}
var private state_leases : array<UiTeardown>
var private teardown_hooks : array<UiTeardown>
var private mount_hooks : table<string;bool>
var private computed_snapshots : table<string;string>
struct UiTrace { owner, site, reason : string }
var private trace_enabled = false
var private traces : array<UiTrace>
var private named_dependencies : table<string;string>
var private trace_dependencies : table<string;table<string;string>>
def ui_trace(enabled:bool) { trace_enabled = enabled; clear(traces); clear(trace_dependencies); clear(named_dependencies) }
def ui_trace_count() : int { return length(traces) }
def ui_trace_at(index:int) : UiTrace { return traces[index] }
def private trace_update(site,reason:string) {
    if (!trace_enabled) { return }
    if (length(traces) == 256) { traces |> erase(0) }
    traces |> push <| UiTrace(owner=active_component,site=site,reason=reason)
}
def rt_named_dependency(name:string; value:auto(T)) {
    let start=length(dependency_parts)
    rt_dependency(value)
    if (trace_enabled) {
        var snapshot=""
        for (i in range(start,length(dependency_parts))) { snapshot += dependency_parts[i] }
        named_dependencies[name]=snapshot
    }
}
def private trace_reason(key,fallback:string):string {
    if (!trace_enabled) { return fallback }
    var changed=""
    let known=key_exists(trace_dependencies,key)
    for (name,value in keys(named_dependencies),values(named_dependencies)) {
        var differs=true
        if (known) {
            let exists=key_exists(trace_dependencies[key],name)
            if (exists) { differs=trace_dependencies[key][name] != value }
        }
        if (differs) {
            if (!empty(changed)) { changed += ", " }
            changed += name
        }
    }
    trace_dependencies[key] := named_dependencies
    return empty(changed) ? fallback : "{fallback}: {changed}"
}

// Slots and component events stay synchronous; no callback outlives a frame.
def slot(content:block) { invoke(content) }
def emit(event:block<(value:auto(T)):void>; value:T) { invoke(event,value) }
def emit(event:block) { invoke(event) }
def rt_volatile_dependency() { dependency_parts |> push <| "callback:{epoch};" }

def rt_local_key(owner,site:string) : string { return "{owner}/state:{site}" }
def rt_local_state(var storage:table<string;array<auto(T)>>; site:string;
                   initialize:block<():T>; cleanup:function<(key:string):void>; body:block<(var local:T&):void>) {
    verify(!empty(active_component) && path == active_component, "state must be declared at component scope, before DOM containers")
    let key = rt_local_key(active_component,site)
    if (!key_exists(storage,key)) {
        verify(first_mount, "state declarations must be unconditional; use a child component inside when/each_keyed")
        var initial = invoke(initialize)
        storage[key] |> push_clone(initial)
        static_if (typeinfo can_delete(initial)) { delete initial }
        state_leases |> push <| UiTeardown(owner=active_component,key=key,cleanup=cleanup)
    }
    invoke(body,storage[key][0])
}
def rt_computed(var storage:table<string;array<auto(T)>>; site:string; dependencies:block;
                volatile_read:bool; evaluate:block<():T>; cleanup:function<(key:string):void>; body:block<(value:T):void>) {
    verify(!empty(active_component) && path == active_component, "computed must be declared at component scope")
    let key = rt_local_key(active_component,site)
    if (!dispatching) {
        let snapshot = dependency_snapshot(dependencies)
        let mounted = key_exists(storage,key)
        verify(mounted || first_mount,"computed declarations must be unconditional; use a child component")
        if (!mounted || volatile_read || force_bindings || computed_snapshots[key] != snapshot) {
            var value = invoke(evaluate)
            if (!mounted) {
                storage[key] |> push_clone(value)
                state_leases |> push <| UiTeardown(owner=active_component,key=key,cleanup=cleanup)
            } else { storage[key][0] := value }
            static_if (typeinfo can_delete(value)) { delete value }
            computed_snapshots[key] = snapshot
            stats.computed_updates += 1
            trace_update(site,trace_reason(key,mounted ? "computed dependency changed" : "computed mount"))
        } else { stats.computed_skips += 1 }
    }
    invoke(body,storage[key][0])
}
def rt_on_mount(site:string; body:block) {
    verify(!empty(active_component) && path == active_component,"on_mount must be declared at component scope")
    let key = "{active_component}/{site}"
    if (first_mount && !key_exists(mount_hooks,key)) {
        mount_hooks[key] = true
        invoke(body)
    }
}
def rt_on_unmount(site:string; cleanup:function<(key:string):void>) {
    verify(!empty(active_component) && path == active_component,"on_unmount must be declared at component scope")
    if (!first_mount) { return }
    teardown_hooks |> push <| UiTeardown(owner=active_component,key=site,cleanup=cleanup)
}
def private retire_component(owner:string) {
    unmounting = true
    var inscope trace_keys:array<string>
    for (key in keys(trace_dependencies)) {
        if (key == owner || find(key,"{owner}/") == 0) { trace_keys |> push(key) }
    }
    for (key in trace_keys) { trace_dependencies |> erase(key) }
    let hook_count = length(teardown_hooks)
    for (offset in range(hook_count)) {
        let i = hook_count-offset-1
        if (teardown_hooks[i].owner == owner) {
            let hook = teardown_hooks[i]
            teardown_hooks |> erase(i)
            invoke(hook.cleanup,owner)
        }
    }
    let lease_count = length(state_leases)
    for (offset in range(lease_count)) {
        let i = lease_count-offset-1
        if (state_leases[i].owner == owner) {
            let lease = state_leases[i]
            state_leases |> erase(i)
            invoke(lease.cleanup,lease.key)
            computed_snapshots |> erase(lease.key)
        }
    }
    var inscope dead_hooks : array<string>
    for (key in keys(mount_hooks)) { if (find(key,"{owner}/") == 0) { dead_hooks |> push(key) } }
    for (key in dead_hooks) { mount_hooks |> erase(key) }
    unmounting = false
}
def private retire_components(var dead:array<string>) {
    dead |> sort() $(a,b) => length(a) > length(b)
    for (owner in dead) { retire_component(owner) }
}

def rt_mounting() : bool { return mounting }
def ui_signal() : UiSignal { signal_id += 1ul; return UiSignal(id=signal_id) }
var private environment_signal=ui_signal()
var private environment_revision:uint64
var private debugger_signal=ui_signal()
var private debugger_revision:uint64
def rt_watch_debugger() { rt_watch(debugger_signal) }
def debugger_init() { verify(rui_debugger_init(),"Could not initialise RmlUi Debugger") }
def debugger_ready():bool { return rui_debugger_ready() }
def debugger_visible():bool { return rui_debugger_visible() }
def debugger_show(visible:bool=true) { verify(rui_debugger_show(visible),"Could not show RmlUi Debugger") }
def debugger_toggle() { debugger_show(!debugger_visible()) }
def debugger_shutdown() { rui_debugger_shutdown() }
// Empty name disables the shortcut. Registration itself does not load the plugin.
def debugger_hotkey(name:string="F8") { verify(rui_debugger_hotkey(name),"Unknown SDL debugger hotkey") }
def rt_watch_environment() { rt_watch(environment_signal) }
// Use explicitly when an ordinary helper hides reads from the AST annotation.
def watch_style_environment() { rt_watch_environment() }
def ui_touch(signal : UiSignal) {
    for (subscription in subscriptions) {
        if (subscription.signal == signal.id && key_exists(components,subscription.ancestor)) {
            components[subscription.ancestor].dirty = true
            if (subscription.owner == subscription.ancestor) {
                components[subscription.ancestor].bindings_dirty = true
            }
        }
    }
}
def rt_watch(signal : UiSignal) {
    verify(signal.id != 0ul, "Initialize watch tokens with ui_signal()")
    for (ancestor in component_stack) {
        subscriptions |> push <| UiSubscription(signal=signal.id,owner=path,ancestor=ancestor)
    }
}

def ui_stats() : UiStats { return stats }
def ui_clear_stats() { stats = UiStats() }

def private dependency_snapshot(dependencies:block) : string {
    clear(dependency_parts)
    if (trace_enabled) { clear(named_dependencies) }
    invoke(dependencies)
    return build_string() $(var writer) {
        for (part in dependency_parts) { writer |> write(part) }
    }
}

// A binding owns only its leaf nodes, never borrowed closures. Structural
// traversal still runs, but unchanged expressions are not evaluated.
def rt_binding(site:string; dependencies:block; volatile_read, input:bool; body:block) {
    if (dispatching) { invoke(body); return }
    let key = "{path}/binding:{site}"
    let snapshot = dependency_snapshot(dependencies)
    let mounted = key_exists(bindings,key)
    var changed = !mounted || volatile_read || force_bindings
    if (mounted) { changed = changed || bindings[key].dependencies != snapshot }
    // Rejected/normalized input must be restored even if its model field is unchanged.
    if (input) {
        for (event in events) {
            if (event.handle == current) { changed = true }
        }
    }
    visited_bindings |> push(key)
    if (changed) {
        trace_update(site,trace_reason(key,!mounted ? "mount" : (force_bindings ? "explicit signal" : (input && !empty(events) ? "input or dependency changed" : (volatile_read ? "opaque getter" : "dependency changed")))))
        let start = length(visited_nodes)
        invoke(body)
        var state = UiBindingState(seen=epoch,dependencies=snapshot)
        for (i in range(start,length(visited_nodes))) { state.node_keys |> push(visited_nodes[i]) }
        if (mounted) { bindings |> erase(key); stats.binding_updates += 1 }
        else { stats.binding_mounts += 1 }
        bindings[key] <- state
    } else {
        stats.binding_skips += 1
        bindings[key].seen = epoch
        for (node_key in bindings[key].node_keys) {
            nodes[node_key].seen = epoch
            let n = nodes[node_key]
            visited_nodes |> push(node_key)
            order |> push(n.handle)
            parents[n.handle] = n.parent
        }
    }
}
def rt_condition(site:string; dependencies:block; volatile_read:bool; getter:block<():bool>) : bool {
    let key = "{path}/binding:{site}"
    var value = conditions?[key] ?? false
    if (!dispatching) {
        rt_binding(site,dependencies,volatile_read,false) { value = invoke(getter) }
        conditions[key] = value
    }
    return value
}

// Collision-free, length-delimited value snapshots. These checks do not run
// UI getters. Structures/arrays are walked by content, never by their address.
def rt_dependency(value : string) { dependency_parts |> push <| "s{length(value)}:{value};" }
def rt_dependency(value : int | uint | int64 | uint64 | bool | int8 | uint8 | int16 | uint16) { dependency_parts |> push <| "{value};" }
def rt_dependency(value : float) { dependency_parts |> push <| "{value:.9g};" }
def rt_dependency(value : double) { dependency_parts |> push <| "{value:.17g};" }
def rt_dependency(value : float2) { dependency_parts |> push <| "{value.x:.9g},{value.y:.9g};" }
def rt_dependency(value : float3) { dependency_parts |> push <| "{value.x:.9g},{value.y:.9g},{value.z:.9g};" }
def rt_dependency(value : float4) { dependency_parts |> push <| "{value.x:.9g},{value.y:.9g},{value.z:.9g},{value.w:.9g};" }
def rt_dependency(value : int2 | int3 | int4 | uint2 | uint3 | uint4 | range | urange | range64 | urange64) { dependency_parts |> push <| "{value};" }
def rt_dependency(value : array<auto(T)>) {
    dependency_parts |> push <| "a{length(value)}["
    for (item in value) { _::rt_dependency(item) }
    dependency_parts |> push <| "]"
}
def rt_dependency(value : auto(T)) {
    static_if (typeinfo is_struct(type<T>) || typeinfo is_tuple(type<T>)) {
        dependency_parts |> push <| "("
        apply(value) $(field_name, field) { _::rt_dependency(field) }
        dependency_parts |> push <| ")"
    } static_elif (typeinfo is_enum(type<T>)) {
        dependency_parts |> push <| "e{value};"
    } else {
        static_assert(false, "UI dependency type unsupported: pass scalar/enum/vector/struct/array values, or an explicit version")
    }
}

struct UiNode {
    handle, parent : uint64
    seen : int
    tag, name : string
}
struct UiEvent {
    handle : uint64
    kind, value : string
    generation : uint64
    listener, target, source : uint64
    phase, key_code, modifiers : int
    button : int = -1
    key : string
    interruptible : bool
    mouse, screen, wheel : float2
    parameters : table<string;string>
}
// Phase: 1 capture, 2 target, 4 bubble. Modifiers: Ctrl=1, Shift=2, Alt=4, Meta=8.
// A modifier filter ignores Caps/Num/Scroll lock; -1 matches any combination.
struct UiEventOptions { use_capture, stop, stop_immediate : bool; key:string; modifiers:int = -1; enabled:bool = true }
struct private UiHandler { handle,token:uint64; seen:int; signature:string }
var private handlers:table<string;UiHandler>
var private visited_handlers:array<string>
def event_parameter(event:UiEvent; name:string; fallback:string=""):string { return event.parameters?[name] ?? fallback }
def event_ctrl(event:UiEvent):bool { return (event.modifiers & 1)!=0 }
def event_shift(event:UiEvent):bool { return (event.modifiers & 2)!=0 }
def event_alt(event:UiEvent):bool { return (event.modifiers & 4)!=0 }
def event_meta(event:UiEvent):bool { return (event.modifiers & 8)!=0 }
var private nodes : table<string; UiNode>
var private order : array<uint64>
var private parents : table<uint64; uint64>
var private calls : table<string; int>
var private events : array<UiEvent>
var private path = ""
var private current : uint64
var private depth = 0
var private root_depth = 0
var private epoch = 0
var private dispatching = false
var private style = ""
var private styles : table<string; string>
// Sheets cascade in the order they were first used. A table iterates in hash
// order once it outgrows its small packed form, so the order is kept apart.
var private style_order : array<string>
var private css_dirty = true
struct private UiVirtual { owner:string; scroll:float; first,last:int }
var private virtuals : table<uint64;UiVirtual>
struct private UiFocusRequest { owner,name:string; key:int = -1 }
var private focus_requests : array<UiFocusRequest>
var private focus_returns : table<uint64;uint64>
struct private UiDraft { text,model,error:string; dirty:bool }
var private drafts : table<uint64;UiDraft>
var private option_snapshots : table<uint64;string>
var private style_build = ""
var private style_defining=false
var private keyframes_building=false
var private keyframe_building=false
var private keyframe_last:float = -1.
var private keyframe_count:int
var private keyframe_properties=""
var private rule_selector = ""
var private rule_build = ""

def rt_component(name : string; dependencies, mount_body, update_body, dispatch_body : block) {
    verify(!unmounting, "Unmount hooks cannot create UI components")
    verify(!template_building,"[ui_template] is static; mount components in document_content")
    let old_path = path
    let old_style = style
    let old_depth = root_depth
    let old_force = force_bindings
    let old_component = active_component
    let old_first_mount = first_mount
    let counter_key = "{path}/component:{name}"
    let index = calls?[counter_key] ?? 0
    calls[counter_key] = index + 1
    path = "{counter_key}:{index}"
    style = ""
    root_depth = depth
    let component_path = path
    active_component = component_path
    first_mount = false
    if (dispatching) {
        // Only ancestors of the target need event traversal. No borrowed
        // closures, model pointers or item references survive a frame.
        var interested = false
        if (key_exists(components,component_path)) {
            for (key in components[component_path].handler_keys) {
                let token=handlers?[key]?.token ?? 0ul
                for (event in events) { if (token!=0ul && event.listener==token) { interested=true } }
            }
            for (key in components[component_path].node_keys) {
                let handle = nodes?[key]?.handle ?? 0ul
                for (event in events) {
                    if (event.handle == handle) { interested = true }
                }
            }
        }
        if (interested) {
            components[component_path].dirty = true
            stats.dispatches += 1
            invoke(dispatch_body)
        }
    } else {
        component_stack |> push(component_path)
        // Replace subscriptions without keeping references into a mutable table.
        let subscription_count = length(subscriptions)
        for (offset in range(subscription_count)) {
            let i = subscription_count-offset-1
            if (subscriptions[i].owner == component_path) { subscriptions |> erase(i) }
        }
        let snapshot = dependency_snapshot($() {
            rt_named_dependency("viewport.width",rui_width())
            rt_named_dependency("viewport.height",rui_height())
            rt_named_dependency("locale.revision",rui_locale_revision())
            invoke(dependencies)
        })
        let mounted = key_exists(components,component_path)
        force_bindings = mounted ? components[component_path].bindings_dirty : false
        var changed = !mounted
        if (mounted) {
            let dirty = components[component_path].dirty
            changed = dirty || components[component_path].dependencies != snapshot
        }
        visited_components |> push(component_path)
        if (changed) {
            trace_update(name,trace_reason(component_path,!mounted ? "component mount" : "arguments or invalidation"))
            let node_start = length(visited_nodes)
            let child_start = length(visited_components)
            let binding_start = length(visited_bindings)
            let handler_start = length(visited_handlers)
            if (!mounted) { first_mount = true; stats.mounts += 1; invoke(mount_body) }
            else { stats.updates += 1; invoke(update_body) }
            // Reacquire after nested calls: inserting children can rehash.
            var state = UiComponentState(seen=epoch,dependencies=snapshot)
            for (i in range(node_start,length(visited_nodes))) { state.node_keys |> push(visited_nodes[i]) }
            for (i in range(child_start,length(visited_components))) { state.children |> push(visited_components[i]) }
            for (i in range(binding_start,length(visited_bindings))) { state.binding_keys |> push(visited_bindings[i]) }
            for (i in range(handler_start,length(visited_handlers))) { state.handler_keys |> push(visited_handlers[i]) }
            if (mounted) { components |> erase(component_path) }
            components[component_path] <- state
        } else {
            stats.skips += 1
            components[component_path].seen = epoch
            for (key in components[component_path].node_keys) {
                nodes[key].seen = epoch
                let n = nodes[key]
                visited_nodes |> push(key)
                order |> push(n.handle)
                parents[n.handle] = n.parent
            }
            for (key in components[component_path].children) {
                components[key].seen = epoch
                visited_components |> push(key)
            }
            for (key in components[component_path].binding_keys) {
                bindings[key].seen = epoch
                visited_bindings |> push(key)
            }
            for (key in components[component_path].handler_keys) {
                handlers[key].seen=epoch
                visited_handlers |> push(key)
            }
        }
        pop(component_stack)
    }
    path = old_path
    style = old_style
    root_depth = old_depth
    force_bindings = old_force
    active_component = old_component
    first_mount = old_first_mount
}

def private node_begin(site, tag, part_name, extra_class : string; input_type:string = "text") : uint64 {
    let key = "{path}/{site}"
    var n = nodes?[key] ?? UiNode()
    if (!dispatching) {
        if (n.handle == 0ul || !rui_alive(n.handle)) {
            let root_class = depth == root_depth ? "{style}__root" : ""
            let part_class = empty(part_name) ? "" : "{style}__{part_name}"
            let classes = "{extra_class} {root_class} {part_class}"
            n.handle = rui_create(current, tag, classes, tag == "input" ? input_type : "")
            verify(n.handle != 0ul, "RmlUi element creation failed")
            n.parent = current
            n.tag = tag
            n.name = part_name
        }
        verify(n.tag == tag, "A UI site changed its element type")
        verify(n.seen != epoch, "Repeated UI site: use each_keyed instead of a plain loop")
        if (n.name != part_name) {
            // A computed part name restyles the same element; the site is its identity.
            if (!empty(n.name)) { rui_class(n.handle,"{style}__{n.name}",false) }
            if (!empty(part_name)) { rui_class(n.handle,"{style}__{part_name}",true) }
            n.name = part_name
        }
        n.seen = epoch
        nodes[key] = n
        visited_nodes |> push(key)
        order |> push(n.handle)
        parents[n.handle] = current
    }
    return n.handle
}

def private container(site, tag, name, cls : string; body : block; input_type:string = "text") {
    let old_path = path
    let old_current = current
    let old_mounting = mounting
    let previous = nodes?["{path}/{site}"] ?? UiNode()
    mounting = previous.handle == 0ul || !rui_alive(previous.handle)
    current = node_begin(site, tag, name, cls,input_type)
    path = "{path}/{site}"
    depth += 1
    invoke(body)
    depth -= 1
    current = old_current
    mounting = old_mounting
    path = old_path
}
def column(site, name : string; body : block) { container(site,"div",name,"ru-column",body) }
def column(site : string; body : block) { column(site,"",body) }
def row(site, name : string; body : block) { container(site,"div",name,"ru-row",body) }
def row(site : string; body : block) { row(site,"",body) }
// RmlUi has no built-in sheet, so a bare div is inline and ignores its size
// unless a flex parent blockifies it. A box is a block wherever it stands.
def box(site, name : string; body : block) { container(site,"div",name,"ru-box",body) }
def box(site:string; body:block) { box(site,"",body) }
def native_element(site,name,tag:string; body:block) {
    if (!native_registered(tag)) { panic("native_element: tag is not registered") }
    container(site,tag,name,"",body)
}
def native_element(site,name,tag:string) { native_element(site,name,tag) {} }
// Names that end up inside a tag, a class or a selector.
def private plain_name(text:string):bool {
    if (empty(text)) { return false }
    for (ch in text) {
        if (!is_alpha(ch) && !is_number(ch) && ch != '-' && ch != '_') { return false }
    }
    return true
}
// Any RmlUi tag: img, label, form, p. RmlUi has no built-in sheet, so the
// element is inline until a rule says otherwise. A site keeps its tag for life.
def element(site,name,tag:string; body:block) {
    verify(plain_name(tag),"element: a tag is letters, digits, '-' or '_'")
    container(site,tag,name,"",body)
}
def element(site,name,tag:string) { element(site,name,tag) {} }
// The document/template owns the target; reconciliation owns only our children.
// Attach listeners to the document itself, including native show/hide and custom events.
def document_events(site:string; document:uint64; body:block) {
    if (!rui_alive(document)) { return }
    let old_current=current; let old_path=path
    current=document; path="{path}/document-events:{site}:{document}"
    invoke(body)
    current=old_current; path=old_path
}
def on_event(site,kind:string; config:UiEventOptions; body:block<(event:UiEvent):void>) {
    let key="{path}/event:{site}"
    if (dispatching) {
        if (!config.enabled) { return }
        let token=handlers?[key]?.token ?? 0ul
        for (event in events) {
            if (token!=0ul && event.listener==token && event.handle==current && event.kind==kind) { invoke(body,event) }
        }
        return
    }
    verify(!empty(kind),"on_event requires a non-empty event name")
    verify(config.modifiers>=-1 && config.modifiers<=15,"on_event modifiers must be -1 or a Ctrl/Shift/Alt/Meta mask")
    if (!config.enabled) { return }
    let signature="{current}/{kind}/{config.use_capture}/{config.stop}/{config.stop_immediate}/{config.key}/{config.modifiers}"
    var token=handlers?[key]?.token ?? 0ul
    if ((handlers?[key]?.signature ?? "")!=signature || !rui_listener_alive(token)) {
        token=rui_relisten(token,current,kind,config.use_capture,config.stop,config.stop_immediate,config.key,config.modifiers)
    }
    handlers[key]=UiHandler(handle=current,token=token,seen=epoch,signature=signature)
    visited_handlers |> push(key)
}
def on_event(site,kind:string; body:block<(event:UiEvent):void>) { on_event(site,kind,UiEventOptions(),body) }

def document_content(site:string; document:uint64; target:string; body:block) {
    let host=rui_document_element(document,target)
    if (host==0ul) { panic("document_content: missing target '{target}'") }
    if (!empty(rui_get_attr(document,"data-rui-template"))) {
        if (rui_get_attr(host,"data-rui-slot")!="true") { panic("document_content: target '{target}' is not a declared template slot") }
    }
    let old_current=current
    let old_path=path
    // Destination identity belongs in the path: changing a slot remounts its
    // children instead of reusing nodes whose parent is still the old slot.
    current=host; path="{path}/{site}:document:{document}:slot:{host}"
    invoke(body)
    current=old_current; path=old_path
}
def tr(key:string):string { return rui_translate("[{key}]") }
def ui_locale():string { return rui_locale() }
def set_locale(language:string) { rui_set_locale(language) }
def text_input(site, name : string; body : block) { container(site,"input",name,"",body) }
def checkbox(site,name:string; body:block) { container(site,"input",name,"",body,"checkbox") }
def select_input(site,name:string; body:block) { container(site,"select",name,"",body) }
def range_input(site,name:string; body:block) { container(site,"input",name,"",body,"range") }
def radio_input(site,name:string; body:block) { container(site,"input",name,"",body,"radio") }
def text_area(site,name:string; body:block) { container(site,"textarea",name,"",body) }
def tabset(site,name:string; body:block) { container(site,"tabset",name,"",body) }
def tab_headers(site:string; body:block) { container(site,"tabs","","",body) }
def tab_panels(site:string; body:block) { container(site,"panels","","",body) }
def tab_panel(site,name:string; body:block) { container(site,"panel",name,"ru-column",body) }
def tab_label(site,name,caption:string) {
    let handle=node_begin(site,"tab",name,"")
    if (!dispatching) { rui_text(handle,caption) }
}
def sprite_image(site,name,sprite_id:string) {
    let handle=node_begin(site,"img",name,"")
    if (!dispatching) { rui_attr(handle,"sprite",sprite_name(sprite_id)) }
}
def svg_image(site,name,source:string; crop:bool=false) {
    let handle=node_begin(site,"svg",name,"")
    if (!dispatching) { rui_attr(handle,"src",source); rui_attr_if(handle,"crop-to-content",crop) }
}
def private validate_svg_size(size:float2) {
    if (!(size.x>0. && size.y>0. && is_finite(size.x) && is_finite(size.y))) {
        panic("Inline SVG viewport dimensions must be finite and positive")
    }
}
def svg_inline(site,name,fragment:string; viewport:float2; crop:bool=false) {
    validate_svg_size(viewport)
    let handle=node_begin(site,"svg",name,"")
    if (!dispatching) { rui_svg_inline(handle,fragment,viewport.x,viewport.y,crop) }
}
def lottie(site,name,source:string) {
    let handle=node_begin(site,"lottie",name,"")
    if (!dispatching) { rui_attr(handle,"src",source) }
}
def progress_bar(site,name:string; value:float; maximum:float=1.0; direction:string="right") {
    verify(maximum>0.0,"progress_bar: maximum must be positive")
    let handle=node_begin(site,"progress",name,"")
    if (!dispatching) {
        rui_attr(handle,"max","{maximum}")
        rui_attr(handle,"value","{clamp(value,0.0,maximum)}")
        rui_attr(handle,"direction",direction)
    }
}
def ui_width() : float { return rui_width() }
def ui_height() : float { return rui_height() }
def ui_dp_ratio():float { return rui_dp_ratio() }
def ui_scale():float { return rui_ui_scale() }
def set_ui_scale(scale:float) { verify(rui_set_ui_scale(scale),"UI scale must be finite and positive") }
def ui_theme():string { return rui_theme() }
def theme_active(name:string):bool { return rui_theme_active(name) }
def set_theme(name:string) { rui_set_theme(name) }
def activate_theme(name:string; active:bool=true) { rui_activate_theme(name,active) }
def flow(site,name:string; breakpoint:float; body:block) {
    container(site,"div",name,"ru-row") {
        property("flex-direction",ui_width() < breakpoint ? "column" : "row")
        property("align-items","stretch")
        invoke(body)
    }
}
def request_focus(name:string; key:int = -1) {
    focus_requests |> push <| UiFocusRequest(owner=active_component,name=name,key=key)
}
def focus_scope(site,name:string; body:block) {
    container(site,"div",name,"") {
        if (!dispatching && mounting) {
            var previous = 0ul
            for (n in values(nodes)) { if (rui_focused(n.handle)) { previous = n.handle } }
            focus_returns[current] = previous
            rui_attr(current,"data-rui-focus-scope","true")
        }
        invoke(body)
    }
}
def on_key(key:string; body:block) {
    if (!dispatching) { rui_watch(current,"keydown"); return }
    for (event in events) {
        if (event.listener == 0ul && event.handle == current && event.kind == "keydown" && event.value == key) { invoke(body) }
    }
}
def on_submit(body:block) { on_key("Enter",body) }
def text(site, name, value : string) {
    let handle = node_begin(site,"span",name,"")
    if (!dispatching) { rui_text(handle,value) }
}
def text(site, name : string; getter : block<():string>) { text(site,name,invoke(getter)) }
def rt_static_text(site, name, value : string) {
    let n = nodes?["{path}/{site}"] ?? UiNode()
    let fresh = n.handle == 0ul || !rui_alive(n.handle)
    let handle = node_begin(site,"span",name,"")
    if (fresh) { rui_text(handle,value) }
}
def button(site, name, caption : string; body : block) {
    container(site,"button",name,"") {
        if (!dispatching) { rui_text(current,caption) }
        invoke(body)
    }
}
// No caption: the body supplies the content, for example an icon.
def button(site, name : string; body : block) { container(site,"button",name,"",body) }
def rt_button(site, name, binding_site:string; dependencies:block; volatile_read:bool;
              caption:block<():string>; body:block) {
    container(site,"button",name,"") {
        if (!dispatching) {
            rt_binding(binding_site,dependencies,volatile_read,false) { rui_text(current,invoke(caption)) }
        }
        invoke(body)
    }
}
def on_click(body : block) {
    if (!dispatching) { rui_watch(current,"click"); return }
    for (event in events) {
        if (event.listener == 0ul && event.handle == current && event.kind == "click" && rui_alive(current)) { invoke(body) }
    }
}
def draggable(payload:string) {
    if (!dispatching) { rui_property(current,"drag","clone"); rui_attr(current,"data-rui-payload",payload) }
}
def on_drop(body:block<(payload:string):void>) {
    if (!dispatching) { rui_watch(current,"dragdrop"); return }
    for (event in events) {
        if (event.listener == 0ul && event.handle == current && event.kind == "dragdrop") { invoke(body,event.value) }
    }
}
def bind_value(getter : block<():string>; setter : block<(value:string):void>) {
    if (!dispatching) {
        rui_watch(current,"change")
        rui_value(current,invoke(getter))
    } else {
        for (event in events) {
            if (event.listener == 0ul && event.handle == current && event.kind == "change" && rui_alive(current)) {
                invoke(setter,event.value)
            }
        }
    }
}
def bind_value(value : string; setter : block<(value:string):void>) {
    bind_value($() => value,setter)
}
def bind_range(getter:block<():float>; minimum,maximum,step:float; setter:block<(value:float):void>) {
    verify(minimum<maximum && step>0.0,"bind_range: invalid limits or step")
    if (!dispatching) {
        rui_watch(current,"change")
        rui_attr(current,"min","{minimum}"); rui_attr(current,"max","{maximum}"); rui_attr(current,"step","{step}")
        rui_value(current,"{clamp(invoke(getter),minimum,maximum)}")
    } else {
        for (event in events) {
            if (event.listener == 0ul && event.handle == current && event.kind == "change") {
                let parsed=try_to_float(event.value)
                if (is_ok(parsed)) { invoke(setter,clamp(unwrap(parsed),minimum,maximum)) }
            }
        }
    }
}
def bind_radio(getter:block<():string>; group,option:string; setter:block<(value:string):void>) {
    verify(!empty(option),"bind_radio: option must not be empty")
    if (!dispatching) {
        rui_watch(current,"change")
        rui_attr(current,"name","{active_component}:{group}"); rui_attr(current,"value",option)
        rui_attr_if(current,"checked",invoke(getter) == option)
    } else {
        for (event in events) {
            if (event.listener == 0ul && event.handle == current && event.kind == "change" && event.value == option) { invoke(setter,option) }
        }
    }
}
// Declare after headers/panels so the native tabset can validate the index.
def bind_tab(getter:block<():int>; setter:block<(value:int):void>) {
    if (!dispatching) { rui_watch(current,"tabchange"); rui_set_tab(current,invoke(getter)) }
    else {
        for (event in events) {
            if (event.listener == 0ul && event.handle == current && event.kind == "tabchange") {
                let parsed=try_to_int(event.value)
                if (is_ok(parsed)) { invoke(setter,unwrap(parsed)) }
            }
        }
    }
}
// A rejected draft stays editable and never silently changes the model to zero.
def private edit_text(model,commit:string; validate:block<(value:string):string>; setter:block<(value:string):void>) {
    verify(commit == "change" || commit == "blur" || commit == "Enter","Unknown field commit mode")
    var draft = drafts?[current] ?? UiDraft(text=model,model=model)
    if (!dispatching) {
        rui_watch(current,"change"); rui_watch(current,"blur"); rui_watch(current,"keydown")
        if (draft.model != model || (!draft.dirty && empty(draft.error))) { draft = UiDraft(text=model,model=model) }
        draft.error=invoke(validate,draft.text)
        rui_value(current,draft.text)
        rui_pseudo(current,"invalid",!empty(draft.error))
    } else {
        for (event in events) {
            if (event.listener!=0ul || event.handle != current) { continue }
            let changed = event.kind == "change"
            if (changed) {
                draft.text = event.value; draft.dirty = true
                draft.error = invoke(validate,draft.text)
            }
            if (event.kind == "keydown" && event.value == "Escape") {
                draft = UiDraft(text=model,model=model)
            } elif (draft.dirty && ((changed && commit == "change") || event.kind == commit ||
                        (event.kind == "keydown" && event.value == commit))) {
                draft.error = invoke(validate,draft.text)
                if (empty(draft.error)) { invoke(setter,draft.text); draft.dirty = false }
            }
        }
    }
    drafts[current] = draft
}
def bind_edit(getter:block<():string>; commit:string; validate:block<(value:string):string>; setter:block<(value:string):void>) {
    edit_text(invoke(getter),commit,validate,setter)
}
def bind_int(getter:block<():int>; minimum,maximum:int; commit:string; setter:block<(value:int):void>) {
    verify(minimum <= maximum,"bind_int: invalid range")
    edit_text("{invoke(getter)}",commit,$(text:string):string {
        let parsed = try_to_int(text)
        if (is_err(parsed)) { return "Enter a whole number" }
        let value = unwrap(parsed)
        if (value < minimum || value > maximum) { return "Use a value from {minimum} to {maximum}" }
        return ""
    },$(text:string) { invoke(setter,unwrap(try_to_int(text))) })
}
def bind_float(getter:block<():float>; minimum,maximum:float; commit:string; setter:block<(value:float):void>) {
    verify(minimum <= maximum,"bind_float: invalid range")
    edit_text("{invoke(getter)}",commit,$(text:string):string {
        let parsed = try_to_float(text)
        if (is_err(parsed)) { return "Enter a number" }
        let value = unwrap(parsed)
        // The conjunction also rejects NaN; finite bounds reject infinity.
        if (!(value >= minimum && value <= maximum)) { return "Use a value from {minimum} to {maximum}" }
        return ""
    },$(text:string) { invoke(setter,unwrap(try_to_float(text))) })
}
def bind_checked(getter:block<():bool>; setter:block<(value:bool):void>) {
    if (!dispatching) { rui_watch(current,"change"); rui_attr_if(current,"checked",invoke(getter)) }
    else {
        for (event in events) {
            if (event.listener == 0ul && event.handle == current && event.kind == "change") { invoke(setter,event.value == "true") }
        }
    }
}
struct UiOption { value,caption:string }
def select_options(items:array<UiOption>) {
    if (dispatching) { return }
    let snapshot = dependency_snapshot($() { rt_dependency(items) })
    if (key_exists(option_snapshots,current) && option_snapshots[current] == snapshot) { return }
    let value = rui_get_value(current)
    rui_options_clear(current)
    for (item in items) { rui_option(current,item.caption,item.value) }
    rui_value(current,value)
    option_snapshots[current] = snapshot
}
def field_error(name:string; key:int = -1) : string {
    let handle = find_owned(name,key)
    return drafts?[handle]?.error ?? ""
}
def field_pending(name:string; key:int = -1) : bool {
    let handle=find_owned(name,key)
    return drafts?[handle]?.dirty ?? false
}
def private find_owned(name:string; item_key:int):uint64 {
    for (key,n in keys(nodes),values(nodes)) {
        if (n.name == name && (empty(active_component) || find(key,"{active_component}/") == 0) &&
            (item_key == -1 || find(key,":key:{item_key}/") >= 0)) { return n.handle }
    }
    return 0ul
}
def when(site : string; condition : bool; body : block) {
    if (condition) {
        let old = path
        path = "{path}/{site}:when"
        invoke(body)
        path = old
    }
}
def when(site : string; condition : block<():bool>; body : block) {
    when(site,invoke(condition),body)
}
def private start_animation(handle:uint64; animation:UiAnimation):uint64 {
    let generation=rui_animation_start(handle,animation.name,animation.seconds,animation.easing,animation.iterations,animation.alternate)
    verify(generation!=0ul,"Could not start animation")
    return generation
}
// Driven by model values; changing revision replays the same animation.
def animate(animation:UiAnimation; revision:int=0; enabled:bool=true) {
    if (dispatching) { return }
    let signature="{animation.name}/{animation.seconds}/{animation.easing}/{animation.iterations}/{animation.alternate}/{revision}/{enabled}"
    let old=animation_bindings?[current] ?? UiAnimationBinding()
    if (old.signature==signature) { return }
    var generation=0ul
    if (enabled) { generation=start_animation(current,animation) }
    else { rui_animation_cancel(current) }
    animation_bindings[current]=UiAnimationBinding(signature=signature,generation=generation)
}
def on_animation_end(body:block<(name:string):void>) {
    if (!dispatching) { rui_watch(current,"animation_done"); return }
    for (event in events) { if (event.listener==0ul && event.handle==current && event.kind=="animation_done") { invoke(body,event.value) } }
}
def on_transition_end(body:block<(property_name:string):void>) {
    if (!dispatching) { rui_watch(current,"transitionend"); return }
    for (event in events) { if (event.listener==0ul && event.handle==current && event.kind=="transitionend") { invoke(body,event.value) } }
}
def private exit_focus(handle:uint64) {
    let focused=rui_focus_node()
    if (!rui_contains(handle,focused)) { return }
    var outer=0ul
    for (scope in keys(focus_returns)) {
        if (rui_contains(handle,scope) && rui_contains(scope,focused) && (outer==0ul || rui_contains(scope,outer))) { outer=scope }
    }
    if (outer!=0ul) {
        let previous=focus_returns[outer]
        if (rui_enabled(previous) && !rui_contains(handle,previous)) { rui_focus(previous) }
    }
}
def animated_when(site,name:string; visible:bool; enter,leave:UiAnimation; body:block) {
    verify(leave.iterations==1,"Exit animation must run exactly once")
    let key="{path}/presence:{site}"
    let existing=key_exists(presences,key)
    if (!existing && !visible) { return }
    var presence=presences?[key] ?? UiPresence(owner=active_component)
    if (dispatching) {
        if (existing && !presence.exiting) { container(site,"div",name,"ru-column",body) }
        return
    }
    if (existing && presence.exiting && !visible && rui_animation_status(presence.handle)==3 &&
        rui_animation_generation(presence.handle)==presence.generation) {
        presences |> erase(key)
        return
    }
    let changed = !existing || presence.exiting==visible
    container(site,"div",name,"ru-column") {
        presence.handle=current
        if (changed) {
            if (!visible) { exit_focus(current) }
            rui_attr_if(current,"disabled",!visible)
            rui_property(current,"pointer-events",visible ? "auto" : "none")
            presence.exiting=!visible
            presence.generation=start_animation(current,visible ? enter : leave)
        }
        invoke(body)
    }
    presences[key]=presence
}
def each_keyed(site : string; items : array<auto(T)>;
               key_of : block<(item:T):int>; body : block<(item:T):void>) {
    var inscope snapshot := items
    var inscope unique : table<int; bool>
    for (item in snapshot) {
        let key = invoke(key_of,item)
        verify(!key_exists(unique,key), "each_keyed: duplicate key")
        unique[key] = true
    }
    let old = path
    for (item in snapshot) {
        let key = invoke(key_of,item)
        path = "{old}/{site}:key:{key}"
        invoke(body,item)
    }
    path = old
}

// Fixed-height virtualization. Only the visible slice is cloned and mounted.
// Item state lives while mounted; durable row state belongs in the model.
def virtual_each(site,name:string; items:array<auto(T)>; row_height,viewport_height:float;
                 key_of:block<(item:T):int>; body:block<(item:T):void>; overscan:int = 2) {
    verify(row_height > 0.0 && viewport_height > 0.0 && overscan >= 0,"virtual_each: invalid dimensions")
    container(site,"div",name,"ru-column",$() {
        let count = length(items)
        var view = virtuals?[current] ?? UiVirtual(owner=active_component)
        if (!dispatching) {
            property("height","{viewport_height}px")
            property("overflow-y","auto")
            property("overflow-x","hidden")
            property("flex-shrink","0")
            let maximum = max(0.0,float(count)*row_height-viewport_height)
            view.scroll = min(max(0.0,rui_scroll_top(current)),maximum)
            rui_scroll_to(current,view.scroll)
            view.first = max(0,int(view.scroll/row_height)-overscan)
            view.last = min(count,int((view.scroll+viewport_height)/row_height)+1+overscan)
            virtuals[current] = view
        }
        var inscope snapshot : array<T>
        var inscope unique : table<int;bool>
        for (item in items) {
            let key = invoke(key_of,item)
            verify(!key_exists(unique,key),"virtual_each: duplicate key")
            unique[key] = true
        }
        for (i in range(view.first,min(view.last,count))) { snapshot |> push_clone(items[i]) }
        container("virtual-top","div","","",$() {
            property("height","{float(view.first)*row_height}px"); property("flex-shrink","0")
        })
        let old_path = path
        for (item in snapshot) {
            let key = invoke(key_of,item)
            path = "{old_path}:key:{key}"
            container("virtual-row","div","","ru-column",$() {
                property("height","{row_height}px"); property("flex-shrink","0")
                property("overflow","hidden")
                invoke(body,item)
            })
        }
        path = old_path
        container("virtual-bottom","div","","",$() {
            property("height","{float(max(0,count-view.last))*row_height}px"); property("flex-shrink","0")
        })
    })
}
def private invalidate_owner(owner:string) {
    for (key,value in keys(components),values(components)) {
        if (key == owner || find(owner,"{key}/") == 0) { value.dirty = true }
    }
}
def private wake_animation_exits():bool {
    var changed=false
    var dead:array<string>
    for (key,presence in keys(presences),values(presences)) {
        if (!rui_alive(presence.handle)) { dead |> push(key); continue }
        let status=rui_animation_status(presence.handle)
        verify(status!=4,"Invalid presence keyframes or easing")
        if (presence.exiting && status==3 && rui_animation_generation(presence.handle)==presence.generation) {
            invalidate_owner(presence.owner); changed=true
        }
    }
    for (key in dead) { presences |> erase(key) }
    var dead_handles:array<uint64>
    for (handle in keys(animation_bindings)) {
        if (!rui_alive(handle)) { dead_handles |> push(handle) }
        else { verify(rui_animation_status(handle)!=4,"Invalid animation keyframes or easing") }
    }
    for (handle in dead_handles) { animation_bindings |> erase(handle) }
    return changed
}

// Inherited text defaults of every document. A native template carries them in
// its own sheet too: RmlUi lays a document out while loading it, before the DSL
// stylesheet is attached, and text without a font is reported and not measured.
var private base_font = "LatoLatin"
var private base_text_css = "font-family: LatoLatin; font-size: 16px; color: #e8edf6;"
// The defaults match rui_default_font. An application with its own font loads
// the file with rui_font and names its family here, once, at startup: a
// template document that is already open keeps the defaults it was loaded with.
def set_base_text(family:string; size:UiLength=UiLength(value=16.,unit="px"); color:UiColor=UiColor(r=232,g=237,b=246)) {
    verify(!empty(family) && find(family,";")<0 && find(family,"\{")<0 && find(family,"\}")<0 &&
        find(family,"\"")<0 && find(family,"\n")<0 && find(family,"\r")<0,"Invalid base font family")
    verify(size.value>0.,"Base font size must be positive")
    base_font = family
    base_text_css = "font-family: {family}; font-size: {size.value}{size.unit}; color: rgb({color.r},{color.g},{color.b});"
    css_dirty = true
}
def base_font_family():string { return base_font }
def private begin_pass() {
    path = ""
    current = rui_root()
    depth = 0
    root_depth = 0
    style = ""
    mounting = true
    force_bindings = false
    clear(component_stack)
    clear(calls)
}
def private reconcile(body : block) {
    if (debugger_revision!=rui_debugger_revision()) {
        debugger_revision=rui_debugger_revision()
        ui_touch(debugger_signal)
    }
    if (environment_revision!=rui_style_revision()) {
        environment_revision=rui_style_revision()
        ui_touch(environment_signal)
    }
    dispatching = false
    epoch += 1
    clear(order)
    clear(parents)
    clear(visited_nodes)
    clear(visited_components)
    clear(visited_bindings)
    clear(visited_handlers)
    begin_pass()
    invoke(body)
    var inscope dead : array<string>
    for (key,value in keys(components),values(components)) {
        if (value.seen != epoch) { dead |> push(key) }
    }
    retire_components(dead)
    clear(dead)
    for (key,value in keys(handlers),values(handlers)) { if (value.seen!=epoch) { dead |> push(key) } }
    for (key in dead) { rui_unlisten(handlers[key].token); handlers |> erase(key) }
    clear(dead)
    for (key, value in keys(nodes), values(nodes)) {
        if (value.seen != epoch) { dead |> push(key) }
    }
    // Resolve the outermost disappearing focus scope before removing any node.
    // Nested scope teardown must not restore focus to an already removed sibling.
    let focused=rui_focus_node()
    var restore_focus=0ul
    var restore_depth=2147483647
    for (key in dead) {
        let handle=nodes[key].handle
        if (key_exists(focus_returns,handle) && rui_contains(handle,focused) && length(key) < restore_depth) {
            restore_focus=focus_returns[handle]; restore_depth=length(key)
        }
    }
    for (key in dead) {
        let handle = nodes[key].handle
        focus_returns |> erase(handle)
        virtuals |> erase(handle)
        drafts |> erase(handle); option_snapshots |> erase(handle)
        rui_remove(handle)
        erase(nodes,key)
    }
    clear(dead)
    for (key, value in keys(components), values(components)) {
        if (value.seen != epoch) { dead |> push(key) }
    }
    for (key in dead) { components |> erase(key) }
    clear(dead)
    for (key, value in keys(bindings), values(bindings)) {
        if (value.seen != epoch) { dead |> push(key) }
    }
    for (key in dead) { bindings |> erase(key); conditions |> erase(key); trace_dependencies |> erase(key) }
    let subscription_count = length(subscriptions)
    for (offset in range(subscription_count)) {
        let i = subscription_count-offset-1
        if (!key_exists(components,subscriptions[i].owner)) { subscriptions |> erase(i) }
    }
    var inscope next : table<uint64;uint64>
    for (i in range(length(order))) {
        let handle = order[length(order)-i-1]
        let parent = parents[handle]
        let before = next?[parent] ?? 0ul
        rui_before(handle,before)
        next[parent] = handle
    }
    if (css_dirty) {
        var css = "body \{ {base_text_css} margin: 0px; height: 100%; overflow-y: auto; \}\n.ru-column \{ display: flex; flex-direction: column; \}\n.ru-row \{ display: flex; flex-direction: row; align-items: center; \}\n.ru-box \{ display: block; \}\nbutton \{ cursor: pointer; \}\n"
        // RmlUi supplies no default control stylesheet. Without explicit sizes
        // an invisible scrollbar slider can cover the entire scroll viewport.
        css += "scrollbarvertical \{ width: 12px; \} scrollbarhorizontal \{ height: 12px; \} scrollbarvertical slidertrack \{ width: 12px; \} scrollbarhorizontal slidertrack \{ height: 12px; \} scrollbarvertical sliderbar \{ width: 10px; min-height: 24px; background-color: #64748b; \} scrollbarhorizontal sliderbar \{ height: 10px; min-width: 24px; background-color: #64748b; \} scrollbarvertical sliderarrowdec, scrollbarvertical sliderarrowinc \{ height: 0px; \} scrollbarhorizontal sliderarrowdec, scrollbarhorizontal sliderarrowinc \{ width: 0px; \}\n"
        for (name in style_order) { css += styles[name] }
        rui_css(css)
        css_dirty = false
    }
    rui_update()
    if (rui_enabled(restore_focus)) { rui_focus(restore_focus) }
    for (request in focus_requests) {
        for (key,n in keys(nodes),values(nodes)) {
            if (n.name == request.name && (empty(request.owner) || find(key,"{request.owner}/") == 0) &&
                (request.key == -1 || find(key,":key:{request.key}/") >= 0)) {
                if (rui_enabled(n.handle)) { rui_focus(n.handle) }
                break
            }
        }
    }
    clear(focus_requests)
}
def ui_frame(body : block) {
    for (handle,view in keys(virtuals),values(virtuals)) {
        if (rui_alive(handle) && rui_scroll_top(handle) != view.scroll) { invalidate_owner(view.owner) }
    }
    // Freeze the incoming queue. Events generated by layout wait until the
    // next frame. Process commands in arrival order, not traversal order.
    var inscope pending : array<UiEvent>
    while (rui_next_event()) {
        var event=UiEvent(handle=rui_event_node(),kind=rui_event_type(),value=rui_event_value(),generation=rui_event_generation(),
            listener=rui_event_listener(),target=rui_event_target(),source=rui_event_source(),phase=rui_event_phase(),
            key_code=rui_event_key_code(),key=rui_event_key(),modifiers=rui_event_modifiers(),button=rui_event_button(),
            interruptible=rui_event_interruptible(),mouse=rui_event_mouse(),screen=rui_event_screen(),wheel=rui_event_wheel())
        for (i in range(rui_event_parameter_count())) { event.parameters[rui_event_parameter_name(i)]=rui_event_parameter_value(i) }
        pending |> push_clone(event)
    }
    for (event in pending) {
        if (!rui_event_allowed(event.handle,event.kind)) { continue }
        if (event.listener!=0ul && (!rui_listener_alive(event.listener) || !rui_event_allowed(event.target,event.kind))) { continue }
        if (event.kind=="animation_done" && event.generation!=rui_animation_generation(event.handle)) { continue }
        clear(events)
        events |> push_clone(event)
        dispatching = true
        begin_pass()
        invoke(body)
        // Retire removed incarnations before delivering the next event.
        reconcile(body)
    }
    clear(events)
    reconcile(body)
    // Complete exits before rendering: native CSS animations restore base values
    // when they finish, so deferring removal to the next frame would flash.
    if (wake_animation_exits()) { reconcile(body) }
    rui_native_check()
}
def ui_reset() {
    verify(empty(active_component) && !unmounting, "ui_reset must run outside component rendering and teardown")
    var inscope dead : array<string>
    for (key in keys(components)) { dead |> push(key) }
    retire_components(dead)
    for (handler in values(handlers)) { rui_unlisten(handler.token) }
    clear(handlers); clear(visited_handlers)
    for (value in values(nodes)) { rui_remove(value.handle) }
    clear(nodes); clear(order); clear(parents); clear(calls); clear(events); clear(styles); clear(style_order)
    clear(templates); clear(template_stack); clear(template_ids); clear(template_sheets)
    template_selected=""; template_building=false; template_definition=UiTemplateDefinition()
    clear(components); clear(visited_nodes); clear(visited_components)
    clear(bindings); clear(conditions); clear(visited_bindings)
    clear(subscriptions); clear(component_stack); clear(dependency_parts)
    clear(state_leases); clear(teardown_hooks); clear(mount_hooks)
    clear(computed_snapshots); clear(traces)
    clear(trace_dependencies); clear(named_dependencies)
    clear(virtuals); clear(focus_requests); clear(focus_returns)
    clear(drafts); clear(option_snapshots)
    clear(presences); clear(animation_bindings)
    style_defining=false; keyframes_building=false; keyframe_building=false; in_media=false; in_spritesheet=false
    ui_clear_stats()
    epoch = 0; css_dirty = true; dispatching = false
    rui_native_check()
}
def ui_find(part_name : string; item_key : int = -1) : uint64 {
    for (key, value in keys(nodes), values(nodes)) {
        if (value.name == part_name && (item_key == -1 || find(key,":key:{item_key}/") >= 0)) {
            return value.handle
        }
    }
    return 0ul
}

// Style declarations are ordinary typed calls, evaluated once per sheet.
struct UiLength { value : float; unit : string }
struct UiColor { r,g,b : int }
def private native_rgba(ink:UiColor; alpha:float):uint4 {
    return uint4(uint(clamp(ink.r,0,255)),uint(clamp(ink.g,0,255)),uint(clamp(ink.b,0,255)),uint(clamp(alpha,0.,1.)*255.))
}
// XY is local content-box position in pixels; ZW is normalized texture UV.
// All arrays are copied by native_mesh, including when the mesh is temporary.
struct UiNativeMesh {
    vertices:array<float4>
    colors:array<uint4>
    indices:array<int>
}
def mesh_vertex(var mesh:UiNativeMesh; position:float2; ink:UiColor; uv:float2=float2(0.); alpha:float=1.):int {
    let index=length(mesh.vertices)
    mesh.vertices |> push(float4(position.x,position.y,uv.x,uv.y))
    mesh.colors |> push(native_rgba(ink,alpha))
    return index
}
def mesh_triangle(var mesh:UiNativeMesh; a,b,c:int) {
    mesh.indices |> push(a); mesh.indices |> push(b); mesh.indices |> push(c)
}
def mesh_quad(var mesh:UiNativeMesh; bounds:float4; ink:UiColor; uv:float4=float4(0.,0.,1.,1.); alpha:float=1.) {
    if (bounds.z<=0. || bounds.w<=0.) { return }
    let a=mesh_vertex(mesh,float2(bounds.x,bounds.y),ink,float2(uv.x,uv.y),alpha)
    let b=mesh_vertex(mesh,float2(bounds.x+bounds.z,bounds.y),ink,float2(uv.z,uv.y),alpha)
    let c=mesh_vertex(mesh,float2(bounds.x+bounds.z,bounds.y+bounds.w),ink,float2(uv.z,uv.w),alpha)
    let d=mesh_vertex(mesh,float2(bounds.x,bounds.y+bounds.w),ink,float2(uv.x,uv.w),alpha)
    mesh_triangle(mesh,a,b,c); mesh_triangle(mesh,a,c,d)
}
def native_mesh(element:uint64; mesh:UiNativeMesh; texture:uint64=0ul) {
    rui_native_mesh(element,mesh.vertices,mesh.colors,mesh.indices,texture)
}
def native_texture_load(element:uint64; source:string):uint64 { return rui_native_texture_load(element,source) }
def native_texture_rgba(element:uint64; size:int2; pixels:array<uint4>):uint64 { return rui_native_texture_rgba(element,size,pixels) }
def native_texture_size(element,texture:uint64):int2 { return rui_native_texture_size(element,texture) }
def native_texture_release(element,texture:uint64):bool { return rui_native_texture_release(element,texture) }
// Diagnostic count includes textures retained by already-submitted geometry.
def native_texture_resources():int { return rui_native_texture_resources() }
def native_rect(element:uint64; bounds:float4; ink:UiColor; alpha:float=1.) {
    var inscope mesh:UiNativeMesh
    mesh_quad(mesh,bounds,ink,float4(0.,0.,1.,1.),alpha)
    native_mesh(element,mesh)
}
def native_triangle(element:uint64; a,b,c:float2; ink:UiColor; alpha:float=1.) {
    var inscope mesh:UiNativeMesh
    let ia=mesh_vertex(mesh,a,ink,float2(0.),alpha)
    let ib=mesh_vertex(mesh,b,ink,float2(0.),alpha)
    let ic=mesh_vertex(mesh,c,ink,float2(0.),alpha)
    mesh_triangle(mesh,ia,ib,ic); native_mesh(element,mesh)
}
def native_image(element,texture:uint64; bounds:float4; uv:float4=float4(0.,0.,1.,1.); alpha:float=1.) {
    verify(texture!=0ul,"native_image requires a texture")
    var inscope mesh:UiNativeMesh
    mesh_quad(mesh,bounds,UiColor(r=255,g=255,b=255),uv,alpha)
    native_mesh(element,mesh,texture)
}
def native_line(element:uint64; a,b:float2; thickness:float; ink:UiColor; alpha:float=1.) {
    let delta=b-a; let distance=length(delta)
    if (distance<=0. || thickness<=0.) { return }
    let n=float2(-delta.y,delta.x)*(thickness*0.5/distance)
    var inscope mesh:UiNativeMesh
    mesh_vertex(mesh,a+n,ink,float2(0.),alpha); mesh_vertex(mesh,b+n,ink,float2(0.),alpha)
    mesh_vertex(mesh,b-n,ink,float2(0.),alpha); mesh_vertex(mesh,a-n,ink,float2(0.),alpha)
    mesh_triangle(mesh,0,1,2); mesh_triangle(mesh,0,2,3)
    native_mesh(element,mesh)
}
struct UiMediaQuery { condition:string }
def px(value : float) : UiLength { return UiLength(value=value,unit="px") }
def px(value : int) : UiLength { return px(float(value)) }
def dp(value:float):UiLength { return UiLength(value=value,unit="dp") }
def dp(value:int):UiLength { return dp(float(value)) }
def pct(value : float) : UiLength { return UiLength(value=value,unit="%") }
def pct(value : int) : UiLength { return pct(float(value)) }
def rgb(r,g,b : int) : UiColor { return UiColor(r=r,g=g,b=b) }
def rt_style_cached(name:string) : bool { return key_exists(styles,name) }
def rt_style_begin(name:string) { style = name; style_build = ""; style_defining=true }
def rt_style_end() {
    if (!key_exists(styles,style)) { style_order |> push(style) }
    styles[style] = style_build; css_dirty = true; style_defining=false
}
def rt_style_use(name:string) {
    style = name
    if (template_building) {
        var present=false
        for (sheet in template_sheets) { if (sheet==name) { present=true } }
        if (!present) { template_sheets |> push(name) }
    }
}
def use_style(fn : function<():void>) { invoke(fn) }
def root() : string { return ".{style}__root" }
def part(name:string) : string { return ".{style}__{name}" }
def hover(selector:string) : string { return "{selector}:hover" }
def disabled_state(selector:string) : string { return "{selector}:disabled" }
// Selectors for class_if and pseudo_if. with_pseudo also reaches the states RmlUi
// maintains itself: focus, active, checked.
def private state_class(name:string) : string { return "{style}__is_{name}" }
def with_class(selector,name:string) : string { return "{selector}.{state_class(name)}" }
def with_pseudo(selector,name:string) : string { return "{selector}:{name}" }
def sprite_name(name:string):string { return "{style}__sprite_{name}" }
var private in_spritesheet=false
var private in_media=false
var private sheet_serial:int
def private media_identifier(name:string) {
    verify(!empty(name) && find(name,"(")<0 && find(name,")")<0 && find(name,"\{")<0 && find(name,"\}")<0 &&
        find(name,";")<0 && find(name,"\n")<0 && find(name,"\r")<0,"Invalid media identifier")
}
def media_min_width(value:UiLength):UiMediaQuery { return UiMediaQuery(condition="(min-width: {value.value}{value.unit})") }
def media_max_width(value:UiLength):UiMediaQuery { return UiMediaQuery(condition="(max-width: {value.value}{value.unit})") }
def media_min_height(value:UiLength):UiMediaQuery { return UiMediaQuery(condition="(min-height: {value.value}{value.unit})") }
def media_max_height(value:UiLength):UiMediaQuery { return UiMediaQuery(condition="(max-height: {value.value}{value.unit})") }
def media_min_resolution(value:float):UiMediaQuery {
    verify(value>0.,"Resolution must be positive")
    return UiMediaQuery(condition="(min-resolution: {value}x)")
}
def media_orientation(value:string):UiMediaQuery {
    verify(value=="portrait" || value=="landscape","Invalid media orientation")
    return UiMediaQuery(condition="(orientation: {value})")
}
def media_theme(name:string):UiMediaQuery { media_identifier(name); return UiMediaQuery(condition="(theme: {name})") }
def media_and(left,right:UiMediaQuery):UiMediaQuery {
    verify(find(left.condition,"not ")!=0 && find(right.condition,"not ")!=0,"Combine positive media queries first, then negate the whole query")
    return UiMediaQuery(condition="{left.condition} and {right.condition}")
}
def media_not(query:UiMediaQuery):UiMediaQuery {
    verify(find(query.condition,"not ")!=0,"Media query is already negated")
    return UiMediaQuery(condition="not {query.condition}")
}
def media(condition:string; body:block) {
    verify(style_defining && !in_media && !in_spritesheet && !keyframes_building && empty(rule_selector),"media must be outside rules; nested media is not supported")
    verify(!empty(condition) && find(condition,"\{")<0 && find(condition,"\}")<0,"Invalid media condition")
    style_build += "@media {condition} \{\n"; in_media=true
    invoke(body)
    in_media=false; style_build += "\}\n"
}
def media(query:UiMediaQuery; body:block) { media(query.condition,body) }
def theme(name:string; body:block) { media(media_theme(name),body) }
def spritesheet(source:string; resolution:float; body:block) {
    verify(!in_spritesheet && empty(rule_selector),"spritesheet must be declared outside rules")
    verify(resolution>0.,"Spritesheet resolution must be positive")
    verify(find(source,"\"") < 0 && find(source,"\n") < 0,"Invalid spritesheet path")
    sheet_serial+=1
    style_build += "@spritesheet {style}__atlas_{sheet_serial} \{ src: \"{source}\"; resolution: {resolution}x;\n"
    in_spritesheet=true
    invoke(body)
    in_spritesheet=false
    style_build += "\}\n"
}
def spritesheet(source:string; body:block) { spritesheet(source,1.,body) }
def sprite(name:string; x,y,w,h:int) {
    verify(in_spritesheet && x>=0 && y>=0 && w>0 && h>0,"sprite requires a spritesheet and a valid rectangle")
    style_build += "{sprite_name(name)}: {x}px {y}px {w}px {h}px;\n"
}
// Outer and inner names refer to sprites in the current style scope.
def ninepatch(outer,inner:string; paint_area:string="padding-box") {
    verify(paint_area=="padding-box" || paint_area=="border-box" || paint_area=="content-box","Invalid ninepatch paint area")
    property("decorator","ninepatch({sprite_name(outer)}, {sprite_name(inner)}) {paint_area}")
}
def ninepatch(outer,inner:string; edge:UiLength; paint_area:string="padding-box") {
    verify(edge.value>=0.,"Ninepatch edge must not be negative")
    verify(paint_area=="padding-box" || paint_area=="border-box" || paint_area=="content-box","Invalid ninepatch paint area")
    property("decorator","ninepatch({sprite_name(outer)}, {sprite_name(inner)}, {edge.value}{edge.unit}) {paint_area}")
}
def rule(selector:string; body:block) {
    rule_selector = selector; rule_build = ""
    invoke(body)
    style_build += "{rule_selector} \{ {rule_build} \}\n"
    rule_selector = ""
}
def property(name,value:string) {
    if (keyframe_building) { keyframe_properties += "{name}: {value}; " }
    elif (!empty(rule_selector)) { rule_build += "{name}: {value}; " }
    elif (template_building) { rt_template_property(name,value) }
    elif (!dispatching) { rui_property(current,name,value) }
}
def attribute(name,value:string) {
    if (template_building) { rt_template_attribute(name,value) }
    elif (!dispatching) { rui_attr(current,name,value) }
}

// Direct mappings to native RmlUi navigation properties, in styles, templates or components.
enum UiNav {
    None
    Auto
    Horizontal
    Vertical
    TreeOrder
}
struct UiNavTarget { id:string }
def private validate_nav_id(id:string) {
    if (empty(id) || find(id,"#")>=0 || find(id," ")>=0 || find(id,"\t")>=0 || find(id,"\n")>=0 || find(id,"\r")>=0) {
        panic("Navigation ID must be non-empty, without # or whitespace")
    }
}
def nav_to(id:string):UiNavTarget { validate_nav_id(id); return UiNavTarget(id=id) }
def nav_id(id:string) { validate_nav_id(id); attribute("id",id) }
def private nav_value(mode:UiNav):string {
    if (mode==UiNav.Auto) { return "auto" }
    if (mode==UiNav.Horizontal) { return "horizontal" }
    if (mode==UiNav.Vertical) { return "vertical" }
    if (mode==UiNav.TreeOrder) { return "tree-order" }
    return "none"
}
def nav(mode:UiNav=UiNav.Auto) { property("nav",nav_value(mode)) }
def nav_up(mode:UiNav) { property("nav-up",nav_value(mode)) }
def nav_up(target:UiNavTarget) { property("nav-up","#{target.id}") }
def nav_right(mode:UiNav) { property("nav-right",nav_value(mode)) }
def nav_right(target:UiNavTarget) { property("nav-right","#{target.id}") }
def nav_down(mode:UiNav) { property("nav-down",nav_value(mode)) }
def nav_down(target:UiNavTarget) { property("nav-down","#{target.id}") }
def nav_left(mode:UiNav) { property("nav-left",nav_value(mode)) }
def nav_left(target:UiNavTarget) { property("nav-left","#{target.id}") }
def tab_stop(enabled:bool=true) { property("tab-index",enabled ? "auto" : "none") }
def document_nav(document:uint64; mode:UiNav=UiNav.Auto) {
    if (!dispatching) { rui_property(document,"nav",nav_value(mode)) }
}
def width(value:UiLength) { property("width","{value.value}{value.unit}") }
def width(getter:block<():UiLength>) { width(invoke(getter)) }
def height(value:UiLength) { property("height","{value.value}{value.unit}") }
def padding(value:UiLength) { property("padding","{value.value}{value.unit}") }
def padding_x(value:UiLength) { property("padding-left","{value.value}{value.unit}"); property("padding-right","{value.value}{value.unit}") }
def padding_y(value:UiLength) { property("padding-top","{value.value}{value.unit}"); property("padding-bottom","{value.value}{value.unit}") }
def margin_top(value:UiLength) { property("margin-top","{value.value}{value.unit}") }
def margin_bottom(value:UiLength) { property("margin-bottom","{value.value}{value.unit}") }
def font_size(value:UiLength) { property("font-size","{value.value}{value.unit}") }
def background(value:UiColor) { property("background-color","rgb({value.r},{value.g},{value.b})") }
def color(value:UiColor) { property("color","rgb({value.r},{value.g},{value.b})") }
def image_color(value:UiColor) { property("image-color","rgb({value.r},{value.g},{value.b})") }
def svg_decorator(source:string; crop:bool=false; paint_area:string="padding-box") {
    if (find(source,"\"")>=0 || find(source,"\n")>=0 || find(source,"\r")>=0 || find(source,"\\")>=0) {
        panic("SVG decorator source must use forward slashes and contain no quotes or line breaks")
    }
    if (paint_area!="padding-box" && paint_area!="border-box" && paint_area!="content-box") { panic("Invalid SVG decorator paint area") }
    property("decorator","svg(\"{source}\" {crop ? "crop-to-content" : "crop-none"}) {paint_area}")
}
def opacity(value:float) { property("opacity","{value}") }
def disabled(getter:block<():bool>) { if (!dispatching) { rui_attr_if(current,"disabled",invoke(getter)) } }
// A class or pseudo-class that follows a condition. Unlike an inline property,
// a change of either makes RmlUi run the element's transitions. The class is
// scoped to the current style; select it with with_class(part(...), name).
def class_if(name:string; enabled:bool) {
    verify(plain_name(name),"class_if: a name is letters, digits, '-' or '_'")
    if (template_building) {
        verify(!empty(template_stack),"class_if needs a template node")
        if (enabled) { template_stack[length(template_stack)-1].classes += " {state_class(name)}" }
    } elif (!dispatching) { rui_class(current,state_class(name),enabled) }
}
// Use a name of your own: RmlUi sets hover, active, focus, checked and disabled itself.
def pseudo_if(name:string; enabled:bool) {
    verify(plain_name(name),"pseudo_if: a name is letters, digits, '-' or '_'")
    verify(!template_building,"[ui_template] is static; put pseudo_if in [ui_component] content")
    if (!dispatching) { rui_pseudo(current,name,enabled) }
}

def animation_name(name:string):string { return "{style}__animation_{name}" }
def motion(name:string; seconds:float; easing:string="cubic-out"; iterations:int=1; alternate:bool=false):UiAnimation {
    verify(seconds>0. && (iterations>0 || iterations == -1),"Invalid animation duration or iterations")
    return UiAnimation(name=animation_name(name),seconds=seconds,easing=easing,iterations=iterations,alternate=alternate)
}
def keyframes(name:string; body:block) {
    verify(style_defining && !keyframes_building && empty(rule_selector),"keyframes belong outside rules in [ui_style]")
    keyframes_building=true; keyframe_last=-1.; keyframe_count=0
    style_build += "@keyframes {animation_name(name)} \{\n"
    invoke(body)
    verify(keyframe_count>=2 && keyframe_last==100.,"keyframes must include 0 and 100 percent")
    style_build += "\}\n"; keyframes_building=false
}
def keyframe(percent:float; body:block) {
    verify(keyframes_building && !keyframe_building && percent>=0. && percent<=100. && percent>keyframe_last,"keyframes require increasing percentages in [0,100]")
    verify(keyframe_count>0 || percent==0.,"keyframes must start at zero percent")
    keyframe_building=true; keyframe_properties=""
    invoke(body)
    verify(!empty(keyframe_properties),"Keyframe cannot be empty")
    style_build += "{percent}% \{ {keyframe_properties} \}\n"
    keyframe_building=false; keyframe_last=percent; keyframe_count+=1
}

// Native template serialization. Strings, attributes and inline styles are
// escaped at this boundary; callers never need to concatenate RML themselves.
def private template_escape(value:string):string {
    return replace(replace(replace(replace(value,"&","&amp;"),"<","&lt;"),">","&gt;"),"\"","&quot;")
}
def rt_template_cached(name:string):bool { return key_exists(templates,name) }
def rt_template_begin(name:string) {
    verify(!template_building,"[ui_template] definitions cannot be nested")
    template_building=true; template_has_root=false
    template_previous_style=style; style=name
    clear(template_stack); clear(template_ids); clear(template_sheets)
    template_definition=UiTemplateDefinition(name=name,source="dasrui_{name}.rml",css_source="dasrui_{name}.rcss")
}
def rt_template_use(name:string) {
    verify(!template_building,"[ui_template] definitions cannot be nested")
    verify(key_exists(templates,name),"Unknown template definition")
    template_selected=name
}
def rt_template_property(name,value:string) {
    verify(!empty(template_stack),"Template properties need a node")
    template_stack[length(template_stack)-1].properties += "{name}: {value}; "
}
def rt_template_attribute(name,value:string) {
    verify(!empty(template_stack),"Template attributes need a node")
    // Names are syntax, not values. Keep the builder responsible for identity.
    verify(!empty(name) && find(name," ")<0 && find(name,"\"")<0 && find(name,"'")<0 &&
        find(name,"<")<0 && find(name,">")<0 && find(name,"=")<0 && find(name,"\n")<0 && find(name,"\t")<0 && find(name,"\r")<0,
        "Invalid template attribute name")
    verify(name!="id" && name!="class" && name!="style" && name!="template" && name!="data-rui-slot" && name!="data-rui-template",
        "Template identity, styles and slot markers are managed by the builder")
    template_stack[length(template_stack)-1].attributes += " {name}=\"{template_escape(value)}\""
}
def private template_node(tag,name,classes:string; body:block) {
    verify(template_building,"Template nodes require [ui_template]")
    let is_root=tag=="body"
    if (is_root) {
        verify(!template_has_root && empty(template_stack),"[ui_template] requires exactly one window_frame")
        template_has_root=true
    } else { verify(!empty(template_stack),"Template nodes must be inside window_frame") }
    if (!empty(name)) {
        if (key_exists(template_ids,name)) { panic("[ui_template]: duplicate node name '{name}'") }
        verify(find(name,"#")<0,"Template node names cannot contain #")
        template_ids[name]=true
    }
    let part_class=empty(name) ? "" : "{style}__{name}"
    let root_class=is_root ? "{style}__root" : ""
    template_stack |> push <| UiTemplateNode(tag=tag,id=name,classes="{classes} {root_class} {part_class}")
    invoke(body)
    let item=template_stack[length(template_stack)-1]
    pop(template_stack)
    if (is_root) {
        verify(empty(item.attributes),"Use properties on window_frame; attributes belong on child nodes")
        template_definition.root_class=item.classes
        template_definition.root_properties=item.properties
        template_definition.markup=item.children
    } else {
        let id_attr=empty(item.id) ? "" : " id=\"{template_escape(item.id)}\""
        let markup="<{item.tag}{id_attr} class=\"{template_escape(item.classes)}\" style=\"{template_escape(item.properties)}\"{item.attributes}>{item.children}</{item.tag}>"
        template_stack[length(template_stack)-1].children += markup
    }
}
def window_frame(name:string; body:block) { template_node("body",name,"",body) }
def move_handle(name:string; body:block) {
    template_node("handle",name,"") { attribute("move_target","#document"); invoke(body) }
}
def resize_handle(name:string; body:block) {
    template_node("handle",name,"") { attribute("size_target","#document"); invoke(body) }
}
def resize_handle(name:string) { resize_handle(name,$() {}) }
// Overloads are distinct from slot(block), the component composition helper.
def slot(name:string; body:block) {
    verify(template_building && !empty(name),"[ui_template] slot requires a non-empty name")
    template_node("div",name,"") {
        invoke(body)
        verify(empty(template_stack[length(template_stack)-1].children),"slot accepts styles/attributes; put dynamic children in document_content")
        template_stack[length(template_stack)-1].attributes += " data-rui-slot=\"true\""
    }
}
def slot(name:string) { slot(name,$() {}) }
def title_slot(name:string; body:block) {
    verify(template_building && !empty(name) && empty(template_definition.title),"[ui_template] accepts at most one named title_slot")
    template_definition.title=name
    template_node("span",name,"",body)
}
def title_slot(name:string) { title_slot(name,$() {}) }
def rt_template_column(name:string; body:block) { template_node("div",name,"ru-column",body) }
def rt_template_column(body:block) { rt_template_column("",body) }
def rt_template_row(name:string; body:block) { template_node("div",name,"ru-row",body) }
def rt_template_row(body:block) { rt_template_row("",body) }
def rt_template_box(name:string; body:block) { template_node("div",name,"ru-box",body) }

// The rest of the typed style API. Each helper only forwards to property(), so
// it works wherever property() does: rules, keyframes, templates, components.
// A length and a colour are different types, and a keyword is checked against
// the values RmlUi accepts, so a slip fails at compile time or on first use
// instead of surfacing as a parser warning.
def em(value:float):UiLength { return UiLength(value=value,unit="em") }
def em(value:int):UiLength { return em(float(value)) }
def rem(value:float):UiLength { return UiLength(value=value,unit="rem") }
def rem(value:int):UiLength { return rem(float(value)) }
def vw(value:float):UiLength { return UiLength(value=value,unit="vw") }
def vw(value:int):UiLength { return vw(float(value)) }
def vh(value:float):UiLength { return UiLength(value=value,unit="vh") }
def vh(value:int):UiLength { return vh(float(value)) }
def private css_length(value:UiLength):string { return "{value.value}{value.unit}" }
// RCSS takes alpha as 0..255; the API takes 0..1 like the other colour helpers.
def private css_color(value:UiColor; alpha:float=1.):string {
    if (alpha >= 1.) { return "rgb({value.r},{value.g},{value.b})" }
    return "rgba({value.r},{value.g},{value.b},{int(clamp(alpha,0.,1.)*255.)})"
}
def background(value:UiColor; alpha:float) { property("background-color",css_color(value,alpha)) }
def color(value:UiColor; alpha:float) { property("color",css_color(value,alpha)) }

def min_width(value:UiLength) { property("min-width",css_length(value)) }
def min_height(value:UiLength) { property("min-height",css_length(value)) }
def max_width(value:UiLength) { property("max-width",css_length(value)) }
def max_height(value:UiLength) { property("max-height",css_length(value)) }

def margin(value:UiLength) { property("margin",css_length(value)) }
def margin_left(value:UiLength) { property("margin-left",css_length(value)) }
def margin_right(value:UiLength) { property("margin-right",css_length(value)) }
def margin_x(value:UiLength) { property("margin-left",css_length(value)); property("margin-right",css_length(value)) }
def margin_y(value:UiLength) { property("margin-top",css_length(value)); property("margin-bottom",css_length(value)) }
def padding_left(value:UiLength) { property("padding-left",css_length(value)) }
def padding_right(value:UiLength) { property("padding-right",css_length(value)) }
def padding_top(value:UiLength) { property("padding-top",css_length(value)) }
def padding_bottom(value:UiLength) { property("padding-bottom",css_length(value)) }
def gap(value:UiLength) { property("gap",css_length(value)) }
def letter_spacing(value:UiLength) { property("letter-spacing",css_length(value)) }

def border_radius(value:UiLength) { property("border-radius",css_length(value)) }
def border_width(value:UiLength) { property("border-width",css_length(value)) }
def border_color(value:UiColor; alpha:float=1.) { property("border-color",css_color(value,alpha)) }
def private border_side(side:string; thickness:UiLength; ink:UiColor; alpha:float) {
    property(side,"{css_length(thickness)} {css_color(ink,alpha)}")
}
def border(thickness:UiLength; ink:UiColor; alpha:float=1.) { border_side("border",thickness,ink,alpha) }
def border_top(thickness:UiLength; ink:UiColor; alpha:float=1.) { border_side("border-top",thickness,ink,alpha) }
def border_right(thickness:UiLength; ink:UiColor; alpha:float=1.) { border_side("border-right",thickness,ink,alpha) }
def border_bottom(thickness:UiLength; ink:UiColor; alpha:float=1.) { border_side("border-bottom",thickness,ink,alpha) }
def border_left(thickness:UiLength; ink:UiColor; alpha:float=1.) { border_side("border-left",thickness,ink,alpha) }

def position(kind:string) {
    verify(kind == "static" || kind == "relative" || kind == "absolute" || kind == "fixed",
        "position: use static, relative, absolute or fixed")
    property("position",kind)
}
def left(value:UiLength) { property("left",css_length(value)) }
def top(value:UiLength) { property("top",css_length(value)) }
def right(value:UiLength) { property("right",css_length(value)) }
def bottom(value:UiLength) { property("bottom",css_length(value)) }
def z_index(value:int) { property("z-index","{value}") }
def display(kind:string) {
    verify(kind == "none" || kind == "block" || kind == "inline" || kind == "inline-block" || kind == "flow-root" ||
        kind == "flex" || kind == "inline-flex" || kind == "table" || kind == "inline-table" || kind == "table-row" ||
        kind == "table-row-group" || kind == "table-column" || kind == "table-column-group" || kind == "table-cell",
        "display: not a display value RmlUi knows")
    property("display",kind)
}
def flex_grow(value:float) { property("flex-grow","{value}") }
def flex_shrink(value:float) { property("flex-shrink","{value}") }
def rt_template_box(body:block) { rt_template_box("",body) }
def rt_template_native_element(name,tag:string; body:block) {
    if (!native_registered(tag)) { panic("native_element: tag is not registered") }
    template_definition.native_tags+="{tag};"
    template_node(tag,name,"",body)
}
def rt_template_native_element(name,tag:string) { rt_template_native_element(name,tag) {} }
def rt_template_element(name,tag:string; body:block) {
    verify(plain_name(tag) && tag != "body" && tag != "head" && tag != "template",
        "element: this tag cannot be a node of a template frame")
    template_node(tag,name,"",body)
}
def rt_template_element(name,tag:string) { rt_template_element(name,tag) {} }
def rt_template_text(name,value:string) {
    template_node("span",name,"") { template_stack[length(template_stack)-1].children=template_escape(value) }
}
def rt_template_svg_image(name,source:string; crop:bool=false) {
    template_node("svg",name,"") {
        attribute("src",source)
        if (crop) { attribute("crop-to-content","") }
    }
}
def rt_template_svg_inline(name,fragment:string; viewport:float2; crop:bool=false) {
    validate_svg_size(viewport)
    template_node("svg",name,"") {
        attribute("xmlns","http://www.w3.org/2000/svg")
        attribute("width","{viewport.x}"); attribute("height","{viewport.y}")
        attribute("viewBox","0 0 {viewport.x} {viewport.y}")
        if (crop) { attribute("crop-to-content","") }
        template_stack[length(template_stack)-1].children=fragment
    }
}
def rt_template_lottie(name,source:string) { template_node("lottie",name,"") { attribute("src",source) } }
def rt_template_end() {
    verify(template_building && template_has_root && empty(template_stack),"[ui_template] requires one completed window_frame")
    template_definition.css=".ru-column \{ display:flex; flex-direction:column; \} .ru-row \{ display:flex; flex-direction:row; align-items:center; \} .ru-box \{ display:block; \}\n"
    for (sheet in template_sheets) { template_definition.css += styles[sheet] }
    let t=template_definition
    template_definition.markup="<template name=\"{t.name}\"><head><link type=\"text/css\" href=\"{t.css_source}\"/></head><body>{t.markup}</body></template>"
    templates[t.name]=template_definition
    style=template_previous_style; template_building=false
}
def private template_select(fn:function<():void>):UiTemplateDefinition {
    verify(!template_building,"Cannot instantiate a document while defining a template")
    template_selected=""
    invoke(fn)
    verify(!empty(template_selected),"open_template requires an [ui_template] function")
    for (tag in split(templates[template_selected].native_tags,";")) {
        if (!empty(tag) && !native_registered(tag)) { panic("native_element: cached template tag is not registered") }
    }
    return templates[template_selected]
}
// Useful for inspecting the actual native template emitted by the DSL.
def template_markup(fn:function<():void>):string { return template_select(fn).markup }
enum UiModal {
    None
    Modal
    Keep
}
enum UiDocumentFocus {
    None
    Document
    Keep
    Auto
}
struct UiDocumentOptions { visible:bool=true; modal:UiModal=UiModal.None; focus:UiDocumentFocus=UiDocumentFocus.Auto; scroll:bool=true }
def show_document(document:uint64; config:UiDocumentOptions=UiDocumentOptions()) {
    if (config.visible) { rui_show_document(document,int(config.modal),int(config.focus),config.scroll) }
    else { rui_hide_document(document) }
}
def hide_document(document:uint64) { rui_hide_document(document) }
def close_document(document:uint64) { rui_close_document(document) }
def bring_to_front(document:uint64) { rui_document_front(document,true) }
def send_to_back(document:uint64) { rui_document_front(document,false) }
def position_document(document:uint64; position:float2) { rui_document_position(document,position.x,position.y) }
def focus_next(document:uint64; reverse:bool=false) { rui_focus_next(document,reverse) }
def document_visible(document:uint64):bool { return rui_visible(document) }
def document_modal(document:uint64):bool { return rui_document_modal(document) }
def show_popup(document:uint64; position:float2) {
    verify(rui_show_popup(document,position.x,position.y),"show_popup requires a live document")
}
def open_template(fn:function<():void>; title:string; position:float2; config:UiDocumentOptions=UiDocumentOptions()):uint64 {
    let t=template_select(fn)
    // The text defaults are added here rather than cached with the definition,
    // so a document opened after set_base_text loads with the current ones.
    rui_resource(t.css_source,"body \{ {base_text_css} \}\n{t.css}")
    rui_resource(t.source,t.markup)
    let properties="{t.root_properties} left:{position.x}px; top:{position.y}px;"
    let document=rui_document_load("<rml><head><title>{template_escape(title)}</title><link type=\"text/template\" href=\"{t.source}\"/></head>"+
        "<body class=\"{template_escape(t.root_class)}\" template=\"{t.name}\" data-rui-template=\"{t.name}\" style=\"{template_escape(properties)}\"/></rml>","dasrui_document.rml",false)
    verify(document!=0ul,"Could not instantiate native template")
    if (!empty(t.title)) { rui_text(rui_document_element(document,t.title),title) }
    show_document(document,config)
    return document
}


