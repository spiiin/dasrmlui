options gen2
module macros public
require daslib/ast
require daslib/ast_boost
require daslib/templates_boost
require strings

// Every DSL primitive is a statement. A call used as a value (an initializer,
// argument or operand) is user code that merely shares a primitive's name, so
// the rewriting visitors leave it alone. A user statement with such a name can
// still be told apart by qualifying it: _::height(item).
class private UiStatements : AstVisitor {
    statements : array<uint64>
    def override preVisitExprBlockExpression(blk:ExprBlock?; expr:ExpressionPtr) {
        statements |> push(intptr(expr))
    }
    def override visitExprBlockExpression(blk:ExprBlock?; var expr:ExpressionPtr) : ExpressionPtr {
        pop(statements)
        return expr
    }
    // Nested statements are already popped when their owner is visited.
    def is_statement(call:ExprCall?) : bool {
        return !empty(statements) && statements[length(statements)-1] == intptr(call)
    }
}

class private UiSites : UiStatements {
    serial : int
    prefix : string
    def override visitExprCall(var call : ExprCall?) : ExpressionPtr {
        if (!is_statement(call)) { return call }
        let name = string(call.name)
        if (name == "column" || name == "row" || name == "box" ||
            name == "text" || name == "button" || name == "text_input" ||
            name == "when" || name == "each_keyed" || name == "virtual_each" ||
            name == "flow" || name == "focus_scope" || name == "checkbox" || name == "select_input" ||
            name == "range_input" || name == "radio_input" || name == "text_area" ||
            name == "tabset" || name == "tab_headers" || name == "tab_panels" || name == "tab_panel" ||
            name == "tab_label" || name == "progress_bar" || name == "sprite_image" || name == "document_content" || name == "animated_when" ||
            name == "native_element" || name == "element" || name == "on_event" || name == "document_events" || name == "svg_image" || name == "svg_inline" || name == "lottie") {
            serial += 1
            var args : array<ExpressionPtr>
            args |> push <| qmacro($v("{prefix}:{serial}"))
            for (arg in call.arguments) { args |> push <| clone_expression(arg) }
            clear(call.arguments)
            for (arg in args) { call.arguments |> push(arg) }
            // Collection getter is evaluated in the enclosing function. Do not
            // return an owning array from a block or retain a borrowed array.
            if (name == "each_keyed" && length(call.arguments) == 4) {
                let source = call.arguments[1]
                if (source is ExprMakeBlock) {
                    let body = (source as ExprMakeBlock)._block as ExprBlock
                    if (length(body.list) == 1 && body.list[0] is ExprReturn) {
                        call.arguments[1] = clone_expression((body.list[0] as ExprReturn).subexpr)
                    }
                }
            }
        }
        return call
    }
}

// Watch tokens are hoisted to the dependency phase. They may reference function
// arguments/globals, not locals declared inside the component body.
class private UiDependencies : UiStatements {
    dependencies : array<ExpressionPtr>
    environment:bool
    debugger:bool
    def override visitExprCall(var call : ExprCall?) : ExpressionPtr {
        if (string(call.name) == "ui_watch" && is_statement(call)) {
            for (arg in call.arguments) {
                dependencies |> push <| qmacro(rt_watch($e(arg)))
            }
            return qmacro_block() {}
        }
        let name=string(call.name)
        if ((name=="debugger_visible" || name=="debugger_ready") && !debugger) {
            dependencies |> push <| qmacro(rt_watch_debugger()); debugger=true
        }
        if (name=="ui_dp_ratio" || name=="ui_scale" || name=="ui_theme" || name=="theme_active" || name=="watch_style_environment") {
            if (!environment) { dependencies |> push <| qmacro(rt_watch_environment()); environment=true }
            if (name=="watch_style_environment" && is_statement(call)) { return qmacro_block() {} }
        }
        return call
    }
}

def private static_value(expr : ExpressionPtr) : bool {
    if (expr is ExprConstString || expr is ExprConstInt || expr is ExprConstFloat || expr is ExprConstBool) { return true }
    if (expr is ExprCall) {
        let call = expr as ExprCall
        let name = string(call.name)
        if (name != "px" && name != "dp" && name != "pct" && name != "rgb") { return false }
        for (arg in call.arguments) { if (!static_value(arg)) { return false } }
        return true
    }
    return false
}

class private UiPhase : UiStatements {
    dispatch : bool
    def override visitExprCall(var call : ExprCall?) : ExpressionPtr {
        if (!is_statement(call)) { return call }
        let name = string(call.name)
        if (dispatch && (name == "progress_bar" || name == "sprite_image" || name == "tab_label" || name == "svg_image" || name == "svg_inline" || name == "lottie")) { return qmacro_block() {} }
        if (name == "text") {
            if (dispatch) { return qmacro_block() {} }
            // Constant captions still need a site on updates (a when/list can
            // mount a new subtree), but don't need to be assigned again.
            if (length(call.arguments) == 3 && call.arguments[2] is ExprConstString) {
                call.name := "rt_static_text"
            }
        }
        if (name == "property" || name == "width" || name == "height" ||
            name == "padding" || name == "padding_x" || name == "padding_y" ||
            name == "margin_top" || name == "margin_bottom" || name == "font_size" ||
            name == "background" || name == "color" || name == "opacity" || name == "disabled" ||
            name == "nav" || name == "nav_up" || name == "nav_right" || name == "nav_down" || name == "nav_left" || name == "nav_id" || name == "tab_stop" || name == "image_color" || name == "svg_decorator" || name == "attribute" || name == "class_if" || name == "pseudo_if") {
            // Updates need no extra guard: the binding around the call already
            // runs a constant once. A guard on the container being new would drop
            // a constant whose if/when branch is first reached after mount.
            if (dispatch) { return qmacro_block() {} }
        }
        return call
    }
}

// Only reads are sampled here, never the getter itself. A field chain is one
// dependency (model.profile.title), not a dependency on the entire model.
def private read_root(expr : ExpressionPtr) : string {
    if (expr is ExprVar) { return string((expr as ExprVar).name) }
    if (expr is ExprField) { return read_root((expr as ExprField).value) }
    return ""
}
class private UiNames : AstVisitor {
    names : table<string;bool>
    def override preVisitExprBlockArgument(blk:ExprBlock?; arg:VariablePtr; lastArg:bool) {
        names[string(arg.name)] = true
    }
    def override preVisitExprLetVariable(expr:ExprLet?; arg:VariablePtr; lastArg:bool) {
        names[string(arg.name)] = true
    }
}
struct private UiReadScope { names : array<string> }
class private UiReads : AstVisitor {
    names : table<string;bool>
    locals : table<string;int>
    scopes : array<UiReadScope>
    reads : table<string;ExpressionPtr>
    field_depth : int
    def override visitExprCall(var call:ExprCall?) : ExpressionPtr {
        let name=string(call.name)
        if (name=="ui_dp_ratio" || name=="ui_scale" || name=="ui_theme" || name=="theme_active") {
            reads["style.environment"] = qmacro(rui_style_revision())
        }
        if (string(call.name) == "tr" || string(call.name) == "ui_locale") {
            reads["locale.revision"] = qmacro(rui_locale_revision())
        }
        if (string(call.name) == "ui_width" || string(call.name) == "ui_height") {
            reads[describe(call)] = clone_expression(call)
        }
        return call
    }
    def override preVisitExprBlock(blk:ExprBlock?) {
        var scope = UiReadScope()
        scopes |> emplace(scope)
    }
    def override visitExprBlock(var blk:ExprBlock?) : ExpressionPtr {
        for (name in scopes[length(scopes)-1].names) {
            locals[name] -= 1
            if (locals[name] == 0) { locals |> erase(name) }
        }
        pop(scopes)
        return blk
    }
    def override preVisitExprBlockArgument(blk:ExprBlock?; arg:VariablePtr; lastArg:bool) {
        let name = string(arg.name)
        locals[name] += 1
        scopes[length(scopes)-1].names |> push(name)
    }
    def override preVisitExprLetVariable(expr:ExprLet?; arg:VariablePtr; lastArg:bool) {
        let name = string(arg.name)
        locals[name] += 1
        scopes[length(scopes)-1].names |> push(name)
    }
    def override preVisitExprLetVariableInit(blk:ExprLet?; arg:VariablePtr; expr:ExpressionPtr) {
        let name = string(arg.name)
        locals[name] -= 1
        if (locals[name] == 0) { locals |> erase(name) }
    }
    def override visitExprLetVariableInit(blk:ExprLet?; arg:VariablePtr; var expr:ExpressionPtr) : ExpressionPtr {
        locals[string(arg.name)] += 1
        return expr
    }
    def override preVisitExprField(expr:ExprField?) {
        if (!empty(read_root(expr))) { field_depth += 1 }
    }
    def override visitExprField(var expr:ExprField?) : ExpressionPtr {
        let root_name = read_root(expr)
        if (!empty(root_name)) {
            field_depth -= 1
            if (field_depth == 0 && key_exists(names,root_name) && !key_exists(locals,root_name)) {
                reads[describe(expr)] = clone_expression(expr)
            }
        }
        return expr
    }
    def override visitExprVar(var expr:ExprVar?) : ExpressionPtr {
        let name = string(expr.name)
        if (field_depth == 0 && key_exists(names,name) && !key_exists(locals,name)) {
            reads[name] = clone_expression(expr)
        }
        return expr
    }
}

class private UiBindings : UiStatements {
    names : table<string;bool>
    serial : int
    prefix : string
    def override visitExprCall(var call:ExprCall?) : ExpressionPtr {
        if (!is_statement(call)) { return call }
        let name = string(call.name)
        let text_binding = name == "text" || name == "sprite_image" || name == "tab_label" || name == "progress_bar" || name == "svg_image" || name == "svg_inline" || name == "lottie"
        let input_binding = name == "bind_value" || name == "bind_checked" || name == "bind_int" || name == "bind_float" || name == "bind_edit" || name == "bind_range" || name == "bind_radio" || name == "bind_tab"
        let condition_binding = name == "when"
        // button(site,name,body) has no caption to bind; its body is plain content.
        let caption_binding = name == "button" && length(call.arguments) == 4
        // The arguments read below must exist. With fewer, leave the call for
        // the compiler, which reports the missing overload at the user's line.
        var required = 0
        if (name == "bind_int" || name == "bind_float" || name == "bind_range") { required = 4 }
        elif (name == "bind_edit" || name == "bind_radio") { required = 3 }
        elif (condition_binding) { required = 2 }
        elif (input_binding) { required = 1 }
        if (length(call.arguments) < required) { return call }
        let property_binding = (name == "property" || name == "width" || name == "height" ||
            name == "padding" || name == "padding_x" || name == "padding_y" ||
            name == "margin_top" || name == "margin_bottom" || name == "font_size" ||
            name == "background" || name == "color" || name == "opacity" || name == "disabled" ||
            name == "nav" || name == "nav_up" || name == "nav_right" || name == "nav_down" || name == "nav_left" || name == "nav_id" || name == "tab_stop" || name == "image_color" || name == "svg_decorator" || name == "attribute" || name == "class_if" || name == "pseudo_if")
        if (!text_binding && !input_binding && !condition_binding && !property_binding && !caption_binding) { return call }
        serial += 1
        let site = "{prefix}:binding:{serial}"
        var reads = new UiReads()
        reads.names := names
        // Setter/body blocks are deliberately excluded from dependencies.
        var expressions : array<ExpressionPtr>
        // The part name (argument 1) is a dependency too: it selects the style class.
        if (text_binding) { for (i in range(1,length(call.arguments))) { expressions |> push(call.arguments[i]) } }
        elif (input_binding) {
            expressions |> push(call.arguments[0])
            if (name == "bind_int" || name == "bind_float") {
                expressions |> push(call.arguments[1]); expressions |> push(call.arguments[2]); expressions |> push(call.arguments[3])
            }
            elif (name == "bind_edit") { expressions |> push(call.arguments[1]); expressions |> push(call.arguments[2]) }
            elif (name == "bind_radio") { expressions |> push(call.arguments[1]); expressions |> push(call.arguments[2]) }
            elif (name == "bind_range") { expressions |> push(call.arguments[1]); expressions |> push(call.arguments[2]); expressions |> push(call.arguments[3]) }
        }
        elif (condition_binding) { expressions |> push(call.arguments[1]) }
        elif (caption_binding) { expressions |> push(call.arguments[2]) }
        else { for (arg in call.arguments) { expressions |> push(arg) } }
        var constant = true
        for (expr in expressions) {
            if (!static_value(expr)) { constant = false }
            make_visitor(*reads) $(adapter) { visit(expr,adapter) }
        }
        var checks : array<ExpressionPtr>
        // Stable ordering is important for concatenated dependency snapshots.
        var inscope read_names : array<string>
        for (key in keys(reads.reads)) { read_names |> push(key) }
        sort(read_names)
        for (key in read_names) { checks |> push <| qmacro(rt_named_dependency($v(key),$e(reads.reads[key]))) }
        let volatile_read = empty(checks) && !constant
        if (input_binding && !(call.arguments[0] is ExprMakeBlock)) {
            let value = clone_expression(call.arguments[0])
            call.arguments[0] = qmacro <| $() { return $e(value) }
        }
        if (condition_binding) {
            let expr = call.arguments[1]
            let getter = expr is ExprMakeBlock ? clone_expression(expr) : qmacro <| $() { return $e(expr) }
            call.arguments[1] = qmacro(rt_condition($v(site), $() { $b(checks) }, $v(volatile_read), $e(getter)))
            return call
        }
        if (caption_binding) {
            let expr = call.arguments[2]
            // Keep the container/body traversal independent of its caption.
            return qmacro(rt_button($e(call.arguments[0]), $e(call.arguments[1]), $v(site),
                $() { $b(checks) }, $v(volatile_read), $() { return $e(expr) }, $e(call.arguments[3])))
        }
        return qmacro_expr() {
            rt_binding($v(site), $() { $b(checks) }, $v(volatile_read), $v(input_binding)) {
                $e(call)
            }
        }
    }
}

struct private UiLocalSpec {
    storage, site : string
    arg : VariablePtr
    computed : bool
}
class private UiLifetime : UiStatements {
    prefix : string
    serial : int
    locals : array<UiLocalSpec>
    names : table<string;bool>
    def override preVisitExprCall(call:ExprCall?) {
        let computed = string(call.name) == "computed"
        if ((string(call.name) != "state" && !computed) || !is_statement(call)) { return }
        verify(length(call.arguments) == 2 && call.arguments[1] is ExprMakeBlock,
            "state(initial) requires a block with one explicitly typed mutable argument")
        let block_expr = (call.arguments[1] as ExprMakeBlock)._block as ExprBlock
        verify(length(block_expr.arguments) == 1, "state requires one explicitly typed mutable block argument")
        serial += 1
        let site = "{prefix}:state:{serial}"
        let storage = "__ui_state_{hash(site)}"
        var value_type = clone_type(block_expr.arguments[0]._type)
        value_type.flags.constant = false
        value_type.flags.ref = false
        var cache_type = qmacro_type(type<table<string;array<$t(value_type)>>>)
        verify(add_global_var(compiling_module(),storage,cache_type,call.at,true), "Failed to create local state storage")
        let release_name = "{storage}__release"
        var release_fn = qmacro_function(release_name) $(key:string) { $i(storage) |> erase(key) }
        release_fn.flags |= FunctionFlags.generated | FunctionFlags.privateFunction
        verify(compiling_module() |> add_function(release_fn))
        locals |> push <| UiLocalSpec(storage=storage,site=site,arg=clone_variable(block_expr.arguments[0]),computed=computed)
    }
    def override visitExprCall(var call:ExprCall?) : ExpressionPtr {
        if (!is_statement(call)) { return call }
        let name = string(call.name)
        if (name == "state" || name == "computed") {
            let spec = locals[length(locals)-1]
            pop(locals)
            let release_name = "{spec.storage}__release"
            if (spec.computed) {
                var reads = new UiReads()
                reads.names := names
                make_visitor(*reads) $(adapter) { visit(call.arguments[0],adapter) }
                var checks : array<ExpressionPtr>
                var inscope ordered : array<string>
                for (key in keys(reads.reads)) { ordered |> push(key) }
                sort(ordered)
                for (key in ordered) { checks |> push <| qmacro(rt_named_dependency($v(key),$e(reads.reads[key]))) }
                let value = call.arguments[0]
                let getter = value is ExprMakeBlock ? clone_expression(value) : qmacro <| $() { var result := $e(value); return <- result }
                return qmacro(rt_computed($i(spec.storage),$v(spec.site),$() { $b(checks) },
                    $v(empty(checks) && !static_value(value)),$e(getter),@@$i(release_name),$e(call.arguments[1])))
            }
            return qmacro(rt_local_state($i(spec.storage),$v(spec.site),
                $() { var initial := $e(call.arguments[0]); return <- initial },
                @@$i(release_name),$e(call.arguments[1])))
        }
        if (name == "on_mount" && !empty(call.arguments)) {
            serial += 1
            return qmacro(rt_on_mount($v("{prefix}:mount:{serial}"),$e(call.arguments[0])))
        }
        if (name == "on_unmount") {
            verify(length(call.arguments) == 1 && call.arguments[0] is ExprMakeBlock,
                "on_unmount requires a block; capture owned local state or globals")
            serial += 1
            let site = "{prefix}:unmount:{serial}"
            let hook_name = "__ui_unmount_{hash(site)}"
            var body = qmacro_block() { invoke($e(call.arguments[0])) }
            // Rebind state from owned storage at teardown; never save a stack
            // closure, borrowed item reference, or a stale copy of local state.
            for (offset in range(length(locals))) {
                let spec = locals[length(locals)-offset-1]
                var arguments : array<VariablePtr>
                arguments |> push <| clone_variable(spec.arg)
                body = qmacro_block() {
                    invoke($($a(arguments)) { $e(body) }, $i(spec.storage)[rt_local_key(owner,$v(spec.site))][0])
                }
            }
            var hook = qmacro_function(hook_name) $(owner:string) { $e(body) }
            hook.flags |= FunctionFlags.generated | FunctionFlags.privateFunction
            verify(compiling_module() |> add_function(hook))
            return qmacro(rt_on_unmount($v(site),@@$i(hook_name)))
        }
        return call
    }
}

[function_macro(name="ui_component")]
class private UiComponent : AstFunctionAnnotation {
    def override apply(var func : FunctionPtr; var group : ModuleGroup;
                       var args : AnnotationArgumentList; var errors : das_string) : bool {
        var signature = ""
        for (arg in func.arguments) { signature += "{describe(arg._type)};" }
        let identity = "{hash(string(func.at.fileInfo.name))}_{func.name}_{hash(signature)}"
        var original_names = new UiNames()
        for (arg in func.arguments) { original_names.names[string(arg.name)] = true }
        make_visitor(*original_names) $(adapter) { visit(func.body,adapter) }
        var lifetime = new UiLifetime(prefix=identity)
        lifetime.names := original_names.names
        make_visitor(*lifetime) $(adapter) { visit(func.body,adapter) }
        var visitor = new UiSites(prefix=identity)
        make_visitor(*visitor) $(adapter) { visit(func.body, adapter) }
        var deps = new UiDependencies()
        make_visitor(*deps) $(adapter) { visit(func.body, adapter) }
        var names = new UiNames()
        for (arg in func.arguments) { names.names[string(arg.name)] = true }
        make_visitor(*names) $(adapter) { visit(func.body,adapter) }
        var bindings = new UiBindings(prefix=identity)
        bindings.names := names.names
        make_visitor(*bindings) $(adapter) { visit(func.body,adapter) }
        var checks : array<ExpressionPtr>
        var actuals : array<ExpressionPtr>
        for (arg in func.arguments) {
            if (arg._type.baseType == Type.tBlock || arg._type.baseType == Type.tFunction || arg._type.baseType == Type.tLambda) {
                // A borrowed slot/callback can capture changing values. Traverse
                // when visited instead of retaining or comparing its stack frame.
                checks |> push <| qmacro(rt_volatile_dependency())
            } else {
                checks |> push <| qmacro(rt_named_dependency($v(string(arg.name)),$i(arg.name)))
            }
            actuals |> push <| qmacro($i(arg.name))
        }
        for (dep in deps.dependencies) { checks |> push(dep) }
        let mount_name = "{func.name}__mount"
        let update_name = "{func.name}__update"
        let dispatch_name = "{func.name}__dispatch"
        for (phase in range(3)) {
            var companion = clone_function(func)
            clear(companion.annotations)
            companion.name := phase == 0 ? mount_name : (phase == 1 ? update_name : dispatch_name)
            companion.flags |= FunctionFlags.generated | FunctionFlags.privateFunction
            if (phase != 0) {
                var rewrite = new UiPhase(dispatch=phase == 2)
                make_visitor(*rewrite) $(adapter) { visit(companion.body, adapter) }
            }
            if (!(compiling_module() |> add_function(companion))) {
                errors := "[ui_component] generated function name collision"
                return false
            }
            let dump = find_arg(args,"dump")
            if (dump is tBool && dump as tBool) { print("{describe(companion)}\n") }
        }
        func.body = qmacro_block() {
            rt_component($v(identity), $() { $b(checks) },
                $() { $c(mount_name)($a(actuals)) },
                $() { $c(update_name)($a(actuals)) }) {
                $c(dispatch_name)($a(actuals))
            }
        }
        return true
    }
}

[function_macro(name="ui_style")]
class private UiStyle : AstFunctionAnnotation {
    def override apply(var func : FunctionPtr; var group : ModuleGroup;
                       var args : AnnotationArgumentList; var errors : das_string) : bool {
        if (!empty(func.arguments)) {
            errors := "[ui_style] requires a parameterless function; dynamic properties belong in [ui_component]"
            return false
        }
        let original = clone_expression(func.body)
        let identity = "{hash(string(func.at.fileInfo.name))}_{func.name}"
        let name = "s_{hash(identity)}"
        func.body = qmacro_block() {
            if (!rt_style_cached($v(name))) {
                rt_style_begin($v(name))
                $e(original)
                rt_style_end()
            }
            rt_style_use($v(name))
        }
        return true
    }
}

// Template bodies are static descriptions, not retained component callbacks.
// Reuse familiar container calls, but lower them to the RML builder rather than
// the live DOM/reconciliation runtime. Properties remain the typed style API.
class private UiTemplateBody : UiStatements {
    invalid : string
    def override visitExprReturn(var expr:ExprReturn?) : ExpressionPtr {
        invalid="[ui_template] describes a complete static frame; return statements are not supported"
        return expr
    }
    def override visitExprCall(var call:ExprCall?) : ExpressionPtr {
        if (!is_statement(call)) { return call }
        let name=string(call.name)
        if (name=="native_element" || name=="element" || name=="column" || name=="row" || name=="box" || name=="text" || name=="svg_image" || name=="svg_inline" || name=="lottie") {
            call.name := "rt_template_{name}"
        } elif (name=="state" || name=="computed" || name=="when" || name=="animated_when" || name=="animate" || name=="each_keyed" ||
                name=="virtual_each" || name=="document_content" || name=="on_mount" ||
                name=="on_unmount" || name=="pseudo_if" || find(name,"bind_")==0 || find(name,"on_")==0) {
            invalid="[ui_template] is static; put {name} in [ui_component] content"
        }
        return call
    }
}
[function_macro(name="ui_template")]
class private UiTemplate : AstFunctionAnnotation {
    def override apply(var func:FunctionPtr; var group:ModuleGroup;
                       var args:AnnotationArgumentList; var errors:das_string):bool {
        if (!empty(func.arguments)) {
            errors := "[ui_template] requires a parameterless function; pass instance values to open_template"
            return false
        }
        var rewrite=new UiTemplateBody()
        make_visitor(*rewrite) $(adapter) { visit(func.body,adapter) }
        if (!empty(rewrite.invalid)) { errors := rewrite.invalid; return false }
        let original=clone_expression(func.body)
        let identity="{hash(string(func.at.fileInfo.name))}_{func.name}"
        let name="t_{hash(identity)}"
        func.body=qmacro_block() {
            if (!rt_template_cached($v(name))) {
                rt_template_begin($v(name))
                $e(original)
                rt_template_end()
            }
            rt_template_use($v(name))
        }
        return true
    }
}

