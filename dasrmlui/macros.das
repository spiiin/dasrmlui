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

// Rich text is an ordinary native inline tree, lowered before site/dependency
// generation. In particular, a link/image body must never become one binding.
class private UiRichText : UiStatements {
    invalid:string
    def override visitExprCall(var call:ExprCall?):ExpressionPtr {
        if (!is_statement(call)) { return call }
        let name=string(call.name)
        if (name=="href" || name=="image_source") {
            if (length(call.arguments)==1) { return qmacro(attribute($v(name=="href" ? "href" : "src"),$e(call.arguments[0]))) }
            invalid="{name} requires one string value"; return call
        }
        let format=find("|rich_text|span|strong|emphasis|underline|strike|","|{name}|")>=0
        let media=name=="inline_image" || name=="inline_sprite"
        let linked=name=="link"
        let br=name=="line_break"
        if (!format && !media && !linked && !br) { return call }
        var part=qmacro("")
        var content=qmacro_block() {}
        var prefix:array<ExpressionPtr>
        if (br) {
            if (length(call.arguments)>1) { invalid="line_break accepts an optional name"; return call }
            if (length(call.arguments)==1) { part=clone_expression(call.arguments[0]) }
        } elif (format) {
            let n=length(call.arguments)
            if ((n!=1 && n!=2) || !(call.arguments[n-1] is ExprMakeBlock)) { invalid="{name} requires an optional name and a content block"; return call }
            if (n==2) { part=clone_expression(call.arguments[0]) }
            content=clone_expression((call.arguments[n-1] as ExprMakeBlock)._block)
        } else {
            let n=length(call.arguments)
            if (n<2 || n>3 || (n==3 && !(call.arguments[2] is ExprMakeBlock)) || (linked && n!=3)) {
                invalid="{name} requires name, target and a content/style block (optional for images)"; return call
            }
            part=clone_expression(call.arguments[0])
            if (n==3) { content=clone_expression((call.arguments[2] as ExprMakeBlock)._block) }
            let target=clone_expression(call.arguments[1])
            if (name=="inline_sprite") { prefix |> push <| qmacro(attribute("sprite",sprite_name($e(target)))) }
            else { prefix |> push <| qmacro(attribute($v(linked ? "href" : "src"),$e(target))) }
        }
        if (!br) { prefix |> push <| qmacro(display($v(name=="rich_text" ? "block" : "inline"))) }
        if (name=="strong") { prefix |> push <| qmacro(font_weight("bold")) }
        if (name=="emphasis") { prefix |> push <| qmacro(font_style("italic")) }
        if (name=="underline" || name=="strike" || linked) { prefix |> push <| qmacro(text_decoration($v(name=="strike" ? "line-through" : "underline"))) }
        if (linked) {
            prefix |> push <| qmacro(property("focus","auto"))
            prefix |> push <| qmacro(property("tab-index","auto"))
            prefix |> push <| qmacro(property("cursor","pointer"))
        }
        let tag=br ? "br" : media ? "img" : linked ? "a" : name=="rich_text" ? "div" : "span"
        return qmacro_expr() {
            element($e(part),$v(tag)) {
                $b(prefix)
                $e(content)
            }
        }
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
        if (name != "px" && name != "dp" && name != "pct" && name != "rgb" &&
            name != "em" && name != "rem" && name != "vw" && name != "vh") { return false }
        for (arg in call.arguments) { if (!static_value(arg)) { return false } }
        return true
    }
    return false
}

// Typed style helpers that only forward to property(). Both the phase rewrite
// and the binding wrapper ask here, so a new helper is listed once.
def private typed_property(name:string) : bool {
    return (name == "min_width" || name == "min_height" || name == "max_width" || name == "max_height" ||
        name == "margin" || name == "margin_left" || name == "margin_right" || name == "margin_x" || name == "margin_y" ||
        name == "padding_left" || name == "padding_right" || name == "padding_top" || name == "padding_bottom" ||
        name == "gap" || name == "letter_spacing" ||
        name == "border" || name == "border_top" || name == "border_right" || name == "border_bottom" || name == "border_left" ||
        name == "border_radius" || name == "border_width" || name == "border_color" ||
        name == "position" || name == "left" || name == "top" || name == "right" || name == "bottom" || name == "z_index" ||
        name == "display" || name == "flex_grow" || name == "flex_shrink" ||
        name == "font_weight" || name == "font_style" || name == "text_decoration" || name == "line_height" ||
        name == "white_space" || name == "word_break" || name == "vertical_align" || name == "text_align")
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
        if (typed_property(name) || name == "property" || name == "width" || name == "height" ||
            name == "padding" || name == "padding_x" || name == "padding_y" ||
            name == "margin_top" || name == "margin_bottom" || name == "font_size" ||
            name == "background" || name == "color" || name == "opacity" || name == "disabled" ||
            name == "nav" || name == "nav_up" || name == "nav_right" || name == "nav_down" || name == "nav_left" || name == "nav_id" || name == "tab_stop" || name == "image_color" || name == "svg_decorator" || name == "custom_decorator" || name == "custom_shader" || name == "custom_filter" || name == "custom_backdrop_filter" || name == "custom_filters" || name == "custom_backdrop_filters" || name == "attribute" || name == "class_if" || name == "pseudo_if") {
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

class private UiHybridKeys : AstVisitor {
    def override visitExprCall(var call:ExprCall?):ExpressionPtr {
        if (string(call.name)!="each_keyed" || length(call.arguments)!=4 || !(call.arguments[2] is ExprMakeBlock)) { return call }
        var blk=(call.arguments[2] as ExprMakeBlock)._block as ExprBlock
        var reads=new UiReads()
        for (arg in blk.arguments) { reads.names[string(arg.name)]=true }
        for (expr in blk.list) { make_visitor(*reads) $(adapter) { visit(expr,adapter) } }
        var statements:array<ExpressionPtr>
        for (expr in values(reads.reads)) { statements |> push <| qmacro(rt_hybrid_watch($e(expr))) }
        for (expr in blk.list) { statements |> push(expr) }
        clear(blk.list)
        for (expr in statements) { blk.list |> push(expr) }
        return call
    }
}
class private UiHybridDependencies : AstVisitor {
    def override visitExprCall(var call:ExprCall?):ExpressionPtr {
        if (string(call.name)=="rt_named_dependency" && length(call.arguments)==2) {
            let source=call.arguments[1]
            if (source is ExprVar || source is ExprField || source is ExprAt) { call.name := "rt_hybrid_dependency" }
        }
        return call
    }
}
// A global variable that a component reads is tracked like the model. The read
// registers the variable as a source of the pass, so a write that the
// annotations rewrite (a handler, [ui_action]) is reported by itself, and any
// other write is one ui_changed away. Looked up afresh for every component: a
// global declared further down the file is visible only to what follows it.
var private global_lookup : table<string;bool>
def private global_variable(name:string):bool {
    if (empty(name)) { return false }
    if (key_exists(global_lookup,name)) { return global_lookup[name] }
    var found=false
    program_for_each_module(compiling_program()) $(mod) {
        for_each_global(mod) $(value) { if (string(value.name)==name) { found=true } }
    }
    global_lookup[name]=found
    return found
}
class private UiGlobalNames : AstVisitor {
    names, found:table<string;bool>
    def override visitExprVar(var expr:ExprVar?):ExpressionPtr {
        let name=string(expr.name)
        if (!key_exists(names,name) && global_variable(name)) { found[name]=true }
        return expr
    }
}
// Reads of globals inside an expression: outermost field chains, as in UiReads.
def private global_reads(expr:ExpressionPtr; names:table<string;bool>; var reads:array<ExpressionPtr>) {
    var globals=new UiGlobalNames()
    globals.names := names
    make_visitor(*globals) $(adapter) { visit(expr,adapter) }
    if (empty(globals.found)) { return }
    var visitor=new UiReads()
    visitor.names := globals.found
    make_visitor(*visitor) $(adapter) { visit(expr,adapter) }
    for (value in values(visitor.reads)) {
        if (value is ExprVar || value is ExprField) { reads |> push(value) }
    }
}
// What makes one read of a global tracked: its variable becomes a source of the
// pass, the read itself a reason for the next one.
def private global_checks(var reads:array<ExpressionPtr>; var checks:array<ExpressionPtr>) {
    for (value in reads) {
        checks |> push <| qmacro(rt_hybrid_global($i(read_root(value))))
        checks |> push <| qmacro(rt_hybrid_watch($e(value)))
    }
}
class private UiHybridControl : AstVisitor {
    names, roots, arguments:table<string;bool>
    def override preVisitExprBlockArgument(blk:ExprBlock?; arg:VariablePtr; lastArg:bool) { roots[string(arg.name)]=true }
    def condition(expr:ExpressionPtr):ExpressionPtr {
        var reads=new UiReads()
        reads.names := names
        make_visitor(*reads) $(adapter) { visit(expr,adapter) }
        var checks:array<ExpressionPtr>
        // A condition that reads nothing the component owns is an opaque getter:
        // evaluated on every pass, refreshed by ui_changed or ui_touch.
        var opaque=false
        var globals:array<ExpressionPtr>
        global_reads(expr,names,globals)
        global_checks(globals,checks)
        for (value in values(reads.reads)) {
            if (value is ExprVar || value is ExprField || value is ExprAt) {
                checks |> push <| qmacro(rt_hybrid_watch($e(value)))
                // A bare argument is decided at run time: its call site may cover it.
                let bare=value is ExprVar && !key_exists(arguments,read_root(value))
                if (bare || !key_exists(roots,read_root(value))) { opaque=true }
            }
        }
        return qmacro(rt_hybrid_control($() { $b(checks) },$v(opaque),$()=> $e(expr)))
    }
    def override visitExprIfThenElse(var expr:ExprIfThenElse?):ExpressionPtr { expr.cond=condition(expr.cond); return expr }
    def override visitExprWhile(var expr:ExprWhile?):ExpressionPtr { expr.cond=condition(expr.cond); return expr }
}
// Primitives that UiBindings wraps in a binding. The binding carries their
// dependencies, so on the fast path they behave like text or property.
def private hybrid_bound_leaf(name:string):bool {
    return find("|sprite_image|tab_label|progress_bar|svg_image|svg_inline|lottie|nav|nav_up|nav_right|nav_down|nav_left|nav_id|tab_stop|image_color|svg_decorator|custom_decorator|custom_shader|custom_filter|custom_backdrop_filter|custom_filters|custom_backdrop_filters|pseudo_if|","|{name}|")>=0
}
def private hybrid_container(name:string):bool {
    return find("|column|row|box|element|native_element|flow|button|text_input|checkbox|text_area|select_input|range_input|radio_input|tabset|tab_headers|tab_panels|tab_panel|focus_scope|document_content|document_events|rt_native_data|","|{name}|")>=0
}
// Primitives outside a binding whose effect is fixed by their arguments.
def private hybrid_argument_leaf(name:string):bool {
    return find("|animate|select_options|draggable|document_nav|request_focus|","|{name}|")>=0
}
def private ui_component_function(name:string):bool {
    var found=false
    var other=false
    program_for_each_module(compiling_program()) $(mod) {
        for_each_function(mod,name) $(fn) {
            found=true
            if (find_annotation(fn,"ui_component")==null) { other=true }
        }
    }
    return found && !other
}
def private enumeration_name(name:string):bool {
    var found=false
    program_for_each_module(compiling_program()) $(mod) {
        for_each_enumeration(mod) $(value) { if (string(value.name)==name) { found=true } }
    }
    return found
}
// A value fixed at compile time: literals, the style constructors, enumeration
// constants and operators over them. Deliberately not a call to user code.
def private constant_argument(expr:ExpressionPtr):bool {
    if (static_value(expr) || expr is ExprAddr || find(string(expr.__rtti),"ExprConst")==0) { return true }
    if (expr is ExprField) {
        let owner=(expr as ExprField).value
        return owner is ExprVar && enumeration_name(string((owner as ExprVar).name))
    }
    if (expr is ExprOp1) { return constant_argument((expr as ExprOp1).subexpr) }
    if (expr is ExprOp2) { return constant_argument((expr as ExprOp2).left) && constant_argument((expr as ExprOp2).right) }
    if (expr is ExprOp3) {
        let choice=expr as ExprOp3
        return constant_argument(choice.subexpr) && constant_argument(choice.left) && constant_argument(choice.right)
    }
    return false
}
// What one argument of a call depends on: reads of the component's own names
// and of globals, appended to `reads`. An argument that reads neither and is
// not a constant is an opaque getter: evaluated on every pass, and refreshed
// when the application reports a change with ui_changed or ui_touch.
def private argument_reads(expr:ExpressionPtr; names:table<string;bool>; var reads:array<ExpressionPtr>) {
    if (constant_argument(expr)) { return }
    var visitor=new UiReads()
    visitor.names := names
    make_visitor(*visitor) $(adapter) { visit(expr,adapter) }
    for (value in values(visitor.reads)) {
        if (value is ExprVar || value is ExprField) { reads |> push(value) }
    }
    global_reads(expr,names,reads)
}
// A plain function called from a component is opaque unless its body shows
// that what it does to the element is fixed by its arguments and by globals it
// reads directly: it sets style and properties, branches and calls functions of
// the same kind. Anything else (a site, a block, a call it cannot see into) is left
// to the conservative pass.
class private UiTransparent : UiStatements {
    names, globals:table<string;bool>
    depth:int
    opaque:bool
    def override visitExprCall(var call:ExprCall?):ExpressionPtr {
        if (!is_statement(call)) { return call }
        let name=string(call.name)
        let setters="|use_style|use_live_style|property|attribute|class_if|pseudo_if|width|height|padding|padding_x|padding_y|margin_top|margin_bottom|font_size|background|color|opacity|disabled|"
        if (!typed_property(name) && find(setters,"|{name}|")<0 && !transparent_helper(name,depth+1,globals)) { opaque=true }
        return call
    }
    // A global read in the body is handed to the call site, which tracks it.
    // A name that is neither is something the annotation cannot place.
    def override visitExprVar(var expr:ExprVar?):ExpressionPtr {
        let name=string(expr.name)
        if (key_exists(names,name) || enumeration_name(name)) { return expr }
        if (global_variable(name)) { globals[name]=true } else { opaque=true }
        return expr
    }
    def override visitExprInvoke(var call:ExprInvoke?):ExpressionPtr { opaque=true; return call }
    def override visitExprCallMacro(var call:ExprCallMacro?):ExpressionPtr { opaque=true; return call }
}
def private transparent_body(var fn:FunctionPtr; depth:int; var globals:table<string;bool>):bool {
    if (fn.body==null || find_annotation(fn,"ui_component")!=null || find_annotation(fn,"ui_action")!=null) { return false }
    // The primitives themselves are listed by name, never analysed as helpers.
    if (fn._module!=null && (string(fn._module.name)=="ui" || string(fn._module.name)=="$")) { return false }
    var check=new UiTransparent(depth=depth)
    for (arg in fn.arguments) {
        if (arg._type.baseType == Type.tBlock || arg._type.baseType == Type.tFunction || arg._type.baseType == Type.tLambda) { return false }
        check.names[string(arg.name)]=true
    }
    var declared=new UiNames()
    make_visitor(*declared) $(adapter) { visit(fn.body,adapter) }
    for (name in keys(declared.names)) { check.names[name]=true }
    make_visitor(*check) $(adapter) { visit(fn.body,adapter) }
    if (check.opaque) { return false }
    for (name in keys(check.globals)) { globals[name]=true }
    return true
}
// `globals` receives the globals that the function and those it calls read.
def private transparent_helper(name:string; depth:int; var globals:table<string;bool>):bool {
    if (depth>4 || find(name,"rt_")==0) { return false }
    var found=0
    var transparent=false
    var seen:table<string;bool>
    program_for_each_module(compiling_program()) $(mod) {
        for_each_function(mod,name) $(fn) {
            found += 1
            if (found==1) { transparent=transparent_body(fn,depth,seen) }
        }
    }
    if (found!=1 || !transparent) { return false }
    for (global in keys(seen)) { globals[global]=true }
    return true
}

// Unsupported structural expressions still render correctly through the old
// traversal. Never silently treat an opaque helper as a native leaf binding.
class private UiHybridFallback : UiStatements {
    fallback:bool
    deferred:int
    roots, names, blocks:table<string;bool>
    def deferred_call(name:string):bool {
        return find(name,"on_")==0 || name=="rt_on_mount" || name=="rt_on_unmount" || name=="rt_ui_write"
    }
    def override preVisitExprCall(call:ExprCall?) {
        if (deferred_call(string(call.name))) { deferred+=1 }
    }
    def override visitExprCall(var call:ExprCall?):ExpressionPtr {
        let name=string(call.name)
        if (deferred_call(name)) { deferred-=1; return call }
        if (deferred>0 || !is_statement(call)) { return call }
        if (name=="each_keyed") {
            // The collection is an argument or a global: storage whose writes are
            // reported. A local array or a call result is rebuilt by every pass.
            let root=length(call.arguments)==4 ? read_root(call.arguments[1]) : ""
            if (!key_exists(roots,root) && (key_exists(names,root) || !global_variable(root))) { fallback=true }
            return call
        }
        // An indexed value is bound to the element selected in this pass;
        // UiHybridArguments watches what the index reads.
        if (name=="rt_hybrid_text") {
            if (!static_value(call.arguments[1])) { fallback=true }
            return call
        }
        if (name=="rt_hybrid_value" || name=="rt_hybrid_class" || name=="rt_hybrid_input" || name=="rt_hybrid_checked") { return call }
        // A computed argument (a part name, a document) is a dependency that
        // UiHybridArguments watches.
        if (hybrid_container(name) || hybrid_argument_leaf(name)) { return call }
        let leaves="|text|when|property|attribute|class_if|width|height|padding|padding_x|padding_y|margin_top|margin_bottom|font_size|background|color|opacity|disabled|bind_value|bind_checked|bind_int|bind_float|bind_edit|bind_range|bind_radio|bind_tab|"
        if (typed_property(name) || hybrid_bound_leaf(name) || find(leaves,"|{name}|")>=0) { return call }
        if (name=="rt_binding" || name=="rt_condition" || name=="rt_hybrid_watch" || name=="rt_hybrid_dependency" || name=="rt_named_dependency" || name=="rt_local_state" || name=="rt_computed" || name=="rt_hybrid_global" || name=="rt_volatile_dependency") { return call }
        if (name=="rt_button" || name=="use_style" || name=="use_live_style" || ui_tracked_function(name)) { return call }
        // A slot or a component event is one of this component's own block arguments.
        if ((name=="slot" || name=="emit") && length(call.arguments)>=1 && call.arguments[0] is ExprVar &&
            key_exists(blocks,string((call.arguments[0] as ExprVar).name))) { return call }
        var helper_globals:table<string;bool>
        if (transparent_helper(name,0,helper_globals)) { return call }
        fallback=true
        return call
    }
}
// The inputs of a call are its arguments. Before a component call the caller
// watches what they were computed from; the component may then treat its own
// arguments as covered (rt_hybrid_cover), and what it binds to an argument
// gets the caller's promise as a last parameter. A primitive with a computed
// argument gets the same watches, without the promise.
// The variable whose storage an lvalue lives in, through fields and indices.
def private storage_root(expr:ExpressionPtr):string {
    if (expr is ExprField) { return storage_root((expr as ExprField).value) }
    if (expr is ExprAt) { return storage_root((expr as ExprAt).subexpr) }
    return expr is ExprVar ? string((expr as ExprVar).name) : ""
}
// Block parameters that receive a copy the runtime keeps fresh: an item of
// each_keyed whose type is passed by value (the list watches the element), and
// the value of computed (it changes only inside a pass). A name counts only if
// every declaration of it in the function is such a parameter.
class private UiHybridCopies : AstVisitor {
    declared, copied:table<string;int>
    def note(expr:ExpressionPtr) {
        if (!(expr is ExprMakeBlock)) { return }
        let blk=(expr as ExprMakeBlock)._block as ExprBlock
        for (arg in blk.arguments) { copied[string(arg.name)] += 1 }
    }
    def override preVisitExprBlockArgument(blk:ExprBlock?; arg:VariablePtr; lastArg:bool) { declared[string(arg.name)] += 1 }
    def override preVisitExprLetVariable(expr:ExprLet?; arg:VariablePtr; lastArg:bool) { declared[string(arg.name)] += 1 }
    def override preVisitExprCall(call:ExprCall?) {
        let name=string(call.name)
        if (name=="each_keyed" && length(call.arguments)==4) { note(call.arguments[2]); note(call.arguments[3]) }
        elif (name=="rt_computed" && length(call.arguments)>=1) { note(call.arguments[length(call.arguments)-1]) }
    }
}
// Reads inside the indices of an lvalue: which element it is depends on them.
class private UiIndexReads : AstVisitor {
    names:table<string;bool>
    reads:array<ExpressionPtr>
    def override visitExprAt(var expr:ExprAt?):ExpressionPtr {
        argument_reads(expr.index,names,reads)
        return expr
    }
}
class private UiHybridArguments : AstVisitor {
    names, arguments, blocks, copies:table<string;bool>
    covered:string
    def promise(expr:ExpressionPtr):ExpressionPtr {
        let root=read_root(expr)
        if (key_exists(arguments,root)) { return qmacro($i(covered)) }
        return key_exists(copies,root) ? qmacro(true) : qmacro(false)
    }
    // A read rooted in a global: the variable is registered before it is used.
    def global_root(expr:ExpressionPtr):string {
        let root=storage_root(expr)
        return !key_exists(names,root) && global_variable(root) ? root : ""
    }
    def source(expr:ExpressionPtr; var checks:array<ExpressionPtr>) {
        let root=global_root(expr)
        if (!empty(root)) { checks |> push <| qmacro(rt_hybrid_global($i(root))) }
    }
    def before(call:ExprCall?; component:bool; helper_globals:table<string;bool>):ExpressionPtr {
        var checks:array<ExpressionPtr>
        for (global in keys(helper_globals)) {
            checks |> push <| qmacro(rt_hybrid_global($i(global)))
            checks |> push <| qmacro(rt_hybrid_watch($i(global)))
        }
        for (arg in call.arguments) {
            if (arg is ExprMakeBlock || constant_argument(arg)) { continue }
            // A block handed on is covered exactly when this component is: its own check says so.
            if (arg is ExprVar && key_exists(blocks,string((arg as ExprVar).name))) { continue }
            if (component && (arg is ExprVar || arg is ExprField) && (key_exists(names,read_root(arg)) || !empty(global_root(arg)))) {
                // Handed over as it stands: by value or by reference, see rt_hybrid_argument.
                source(arg,checks)
                checks |> push <| qmacro(rt_hybrid_argument($e(clone_expression(arg)),$e(promise(arg))))
                continue
            }
            var reads:array<ExpressionPtr>
            argument_reads(arg,names,reads)
            for (value in reads) {
                source(value,checks)
                checks |> push <| qmacro(rt_hybrid_watch($e(value),$e(promise(value))))
            }
        }
        if (component) { return qmacro(rt_hybrid_cover($() { $b(checks) },false)) }
        if (empty(checks)) { return null }
        return qmacro(rt_hybrid_arguments($() { $b(checks) }))
    }
    // Storage a statement reads directly: the collection of a list, the value
    // of a native binding. A global there becomes a source just before it.
    def direct_value(call:ExprCall?):int {
        let name=string(call.name)
        if (name=="each_keyed" && length(call.arguments)==4) { return 1 }
        if (name=="rt_hybrid_text" && length(call.arguments)>=3) { return 2 }
        if ((name=="rt_hybrid_value" || name=="rt_hybrid_class") && length(call.arguments)>=2) { return 1 }
        if ((name=="rt_hybrid_input" || name=="rt_hybrid_checked") && length(call.arguments)>=1) { return 0 }
        return -1
    }
    def direct_source(call:ExprCall?):string {
        let value=direct_value(call)
        return value<0 ? "" : global_root(call.arguments[value])
    }
    // A native binding to an indexed element is bound to the element the index
    // selects in this pass; what the index reads decides when to select again.
    def index_checks(call:ExprCall?):ExpressionPtr {
        let value=direct_value(call)
        if (value<0 || string(call.name)=="each_keyed") { return null }
        var indices=new UiIndexReads()
        indices.names := names
        make_visitor(*indices) $(adapter) { visit(call.arguments[value],adapter) }
        if (empty(indices.reads)) { return null }
        var checks:array<ExpressionPtr>
        for (read in indices.reads) {
            source(read,checks)
            checks |> push <| qmacro(rt_hybrid_watch($e(read),$e(promise(read))))
        }
        return qmacro(rt_hybrid_arguments($() { $b(checks) }))
    }
    def override visitExprCall(var call:ExprCall?):ExpressionPtr {
        let name=string(call.name)
        var value = -1
        if (name=="rt_hybrid_text" && length(call.arguments)==3) { value=2 }
        elif ((name=="rt_hybrid_value" || name=="rt_hybrid_class" || name=="rt_hybrid_dependency") && length(call.arguments)==2) { value=1 }
        elif (name=="rt_hybrid_watch" && length(call.arguments)==1) { value=0 }
        if (value>=0) {
            let root=read_root(call.arguments[value])
            if (key_exists(arguments,root)) { call.arguments |> push <| qmacro($i(covered)) }
            elif (key_exists(copies,root)) { call.arguments |> push <| qmacro(true) }
        }
        return call
    }
    def override visitExprBlock(var blk:ExprBlock?):ExpressionPtr {
        var statements:array<ExpressionPtr>
        var inserted=false
        for (expr in blk.list) {
            if (expr is ExprCall) {
                let call=expr as ExprCall
                let name=string(call.name)
                let direct=direct_source(call)
                if (!empty(direct)) { statements |> push <| qmacro(rt_hybrid_global($i(direct))); inserted=true }
                var selected=index_checks(call)
                if (selected!=null) { statements |> push(selected); inserted=true }
                let builtin=hybrid_container(name) || hybrid_argument_leaf(name)
                let component=!builtin && find(name,"rt_")!=0 && ui_component_function(name)
                var helper_globals:table<string;bool>
                let primitive=builtin || (!component && transparent_helper(name,0,helper_globals))
                if (primitive || component) {
                    var check=before(call,component,helper_globals)
                    if (check!=null) { statements |> push(check); inserted=true }
                }
            }
            statements |> push(expr)
        }
        if (inserted) {
            clear(blk.list)
            for (expr in statements) { blk.list |> push(expr) }
        }
        return blk
    }
}
class private UiBindings : UiStatements {
    hybrid : bool
    names : table<string;bool>
    serial : int
    prefix : string
    def override visitExprCall(var call:ExprCall?) : ExpressionPtr {
        if (!is_statement(call)) { return call }
        let name = string(call.name)
        if (hybrid) {
            if (name=="text" && length(call.arguments)==3 && (call.arguments[2] is ExprField || call.arguments[2] is ExprVar || call.arguments[2] is ExprAt)) {
                call.name := "rt_hybrid_text"; return call
            }
            if ((name=="attribute" || name=="property" || name=="class_if") && length(call.arguments)==2 &&
                call.arguments[0] is ExprConstString && (call.arguments[1] is ExprField || call.arguments[1] is ExprVar || call.arguments[1] is ExprAt)) {
                // A state class is scoped to the component's style; only the run time knows it.
                if (name=="class_if") { call.name := "rt_hybrid_class"; return call }
                let target_prefix=name=="attribute" ? "attr:" : "style:"
                return qmacro(rt_hybrid_value($v(target_prefix+string((call.arguments[0] as ExprConstString).value)),$e(call.arguments[1])))
            }
            if ((name=="bind_value" || name=="bind_checked") && length(call.arguments)==2 &&
                (call.arguments[0] is ExprField || call.arguments[0] is ExprVar || call.arguments[0] is ExprAt)) {
                call.name := name=="bind_value" ? "rt_hybrid_input" : "rt_hybrid_checked"; return call
            }
        }
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
        let property_binding = (typed_property(name) || name == "property" || name == "width" || name == "height" ||
            name == "padding" || name == "padding_x" || name == "padding_y" ||
            name == "margin_top" || name == "margin_bottom" || name == "font_size" ||
            name == "background" || name == "color" || name == "opacity" || name == "disabled" ||
            name == "nav" || name == "nav_up" || name == "nav_right" || name == "nav_down" || name == "nav_left" || name == "nav_id" || name == "tab_stop" || name == "image_color" || name == "svg_decorator" || name == "custom_decorator" || name == "custom_shader" || name == "custom_filter" || name == "custom_backdrop_filter" || name == "custom_filters" || name == "custom_backdrop_filters" || name == "attribute" || name == "class_if" || name == "pseudo_if")
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
        if (hybrid) {
            // A global in the expression is tracked, but its value is not part of
            // the snapshot (its type may not be one): evaluate on every pass.
            var globals:array<ExpressionPtr>
            for (expr in expressions) { global_reads(expr,names,globals) }
            if (!empty(globals)) {
                global_checks(globals,checks)
                checks |> push <| qmacro(rt_volatile_dependency())
            }
        }
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
    initial_index : int
    version : ExpressionPtr
}
class private UiLifetime : UiStatements {
    prefix : string
    serial : int
    locals : array<UiLocalSpec>
    state_names : table<string;bool>
    names : table<string;bool>
    def override preVisitExprCall(call:ExprCall?) {
        let computed = string(call.name) == "computed"
        if ((string(call.name) != "state" && !computed) || !is_statement(call)) { return }
        let count=length(call.arguments)
        verify((count==2 || (!computed && (count==3 || count==4))) && call.arguments[count-1] is ExprMakeBlock,
            "state(initial) or state(name, [version,] initial) requires a block with one explicitly typed mutable argument")
        let block_expr = (call.arguments[count-1] as ExprMakeBlock)._block as ExprBlock
        verify(length(block_expr.arguments) == 1, "state requires one explicitly typed mutable block argument")
        serial += 1
        var site = "{prefix}:state:{serial}"
        if (count>2) {
            verify(call.arguments[0] is ExprConstString,"state name must be a constant string")
            let name=string((call.arguments[0] as ExprConstString).value)
            verify(!empty(name) && !key_exists(state_names,name),"state name must be non-empty and unique in the component")
            state_names[name]=true
            site="{prefix}:named:{name}"
        }
        var version=count==4 ? clone_expression(call.arguments[1]) : qmacro(1)
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
        let save_name="{storage}__save"
        if (!computed) {
            var save_fn=qmacro_function(save_name) $(key:string) {
                if (key_exists($i(storage),key)) { rt_live_save("local/{key}",$e(version),$i(storage)[key][0]) }
            }
            save_fn.flags |= FunctionFlags.generated | FunctionFlags.privateFunction
            verify(compiling_module() |> add_function(save_fn))
        }
        locals |> push <| UiLocalSpec(storage=storage,site=site,arg=clone_variable(block_expr.arguments[0]),computed=computed,
            initial_index=count-2,version=version)
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
            let save_name="{spec.storage}__save"
            return qmacro(rt_local_state($i(spec.storage),$v(spec.site),$e(spec.version),
                $() { var initial := $e(call.arguments[spec.initial_index]); return <- initial },
                @@$i(release_name),@@$i(save_name),$e(call.arguments[spec.initial_index+1])))
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

// A write is evaluated once, then reported. Arbitrary external mutating helpers
// must be annotated too, or followed by ui_changed(). No retained script closure.
class private UiWrites : UiStatements {
    arguments : table<string;bool>
    all_variables:bool
    wrote:bool
    def override visitExprCallMacro(var call:ExprCallMacro?):ExpressionPtr {
        // sdl_scope deliberately hides its block from generic AST visitors until
        // expansion. It is executable code, so visit that block explicitly.
        // Do not descend into quotation/other opaque code-generating macros.
        if (string(call.name)=="sdl_scope") {
            for (arg in call.arguments) {
                if (arg is ExprMakeBlock) {
                    var nested=new UiWrites()
                    nested.arguments := arguments
                    nested.all_variables=all_variables
                    make_visitor(*nested) $(adapter) { visit(arg,adapter) }
                }
            }
        }
        return call
    }
    def tracked(expr:ExpressionPtr):bool {
        return expr is ExprField || expr is ExprAt || (expr is ExprVar && (all_variables || key_exists(arguments,string((expr as ExprVar).name))))
    }
    def rewrite(expr:ExpressionPtr; left:ExpressionPtr):ExpressionPtr {
        wrote=true
        let target=clone_expression(left)
        let temporary=make_unique_private_name("ui_write_target",expr.at)
        var operation=clone_expression(expr)
        if (operation is ExprCopy) { (operation as ExprCopy).left=qmacro($i(temporary)) }
        elif (operation is ExprClone) { (operation as ExprClone).left=qmacro($i(temporary)) }
        elif (operation is ExprMove) { (operation as ExprMove).left=qmacro($i(temporary)) }
        elif (operation is ExprOp2) { (operation as ExprOp2).left=qmacro($i(temporary)) }
        elif (operation is ExprOp1) { (operation as ExprOp1).subexpr=qmacro($i(temporary)) }
        elif (operation is ExprCall) { (operation as ExprCall).arguments[0]=qmacro($i(temporary)) }
        return qmacro_expr() {
            rt_ui_write($e(target)) $(var $i(temporary):auto) { $e(operation) }
        }
    }
    def override visitExprCopy(var expr:ExprCopy?):ExpressionPtr { if (tracked(expr.left)) { return rewrite(expr,expr.left) }; return expr }
    def override visitExprClone(var expr:ExprClone?):ExpressionPtr { if (tracked(expr.left)) { return rewrite(expr,expr.left) }; return expr }
    def override visitExprMove(var expr:ExprMove?):ExpressionPtr { if (tracked(expr.left)) { return rewrite(expr,expr.left) }; return expr }
    def override visitExprOp2(var expr:ExprOp2?):ExpressionPtr {
        let op=string(expr.op)
        if ((op=="+=" || op=="-=" || op=="*=" || op=="/=" || op=="%=" || op=="|=" || op=="&=" || op=="^=" || op=="<<=" || op==">>=" || op=="&&=" || op=="||=") && tracked(expr.left)) { return rewrite(expr,expr.left) }
        return expr
    }
    def override visitExprOp1(var expr:ExprOp1?):ExpressionPtr {
        let op=string(expr.op)
        if ((op=="++" || op=="--" || op=="+++" || op=="---") && tracked(expr.subexpr) &&
            !empty(statements) && statements[length(statements)-1]==intptr(expr)) { return rewrite(expr,expr.subexpr) }
        return expr
    }
    def override visitExprCall(var call:ExprCall?):ExpressionPtr {
        let name=string(call.name)
        if (is_statement(call) && length(call.arguments)>0 && tracked(call.arguments[0]) &&
            (name=="push" || name=="push_clone" || name=="emplace" || name=="insert" || name=="erase" || name=="clear" || name=="resize" || name=="pop" || name=="sort" || name=="reverse")) {
            return rewrite(call,call.arguments[0])
        }
        return call
    }
}

def private ui_tracked_function(name:string):bool {
    var found=false
    var untracked=false
    program_for_each_module(compiling_program()) $(mod) {
        for_each_function(mod,name) $(fn) {
            found=true
            if (find_annotation(fn,"ui_component")==null && find_annotation(fn,"ui_action")==null) { untracked=true }
        }
    }
    return found && !untracked
}
// Unlike binding reads, write analysis may follow an index without evaluating
// it. Binding snapshots must retain the whole array to preserve guarded reads.
def private ui_write_root(expr:ExpressionPtr):string {
    if (expr is ExprField) { return ui_write_root((expr as ExprField).value) }
    if (expr is ExprAt) { return ui_write_root((expr as ExprAt).subexpr) }
    return read_root(expr)
}
class private UiOpaqueWrites : UiStatements {
    roots:table<string;bool>
    opaque:bool
    def override preVisitExprBlockArgument(blk:ExprBlock?; arg:VariablePtr; lastArg:bool) { roots[string(arg.name)]=true }
    def override preVisitExprLetVariable(expr:ExprLet?; arg:VariablePtr; lastArg:bool) { roots[string(arg.name)]=true }
    def override preVisitExprForVariable(expr:ExprFor?; arg:VariablePtr; lastArg:bool) { roots[string(arg.name)]=true }
    def override visitExprInvoke(var call:ExprInvoke?):ExpressionPtr { opaque=true; return call }
    def override visitExprCallMacro(var call:ExprCallMacro?):ExpressionPtr { opaque=true; return call }
    def override visitExprOp1(var expr:ExprOp1?):ExpressionPtr {
        let op=string(expr.op)
        if ((op=="++" || op=="--" || op=="+++" || op=="---") &&
            (empty(statements) || statements[length(statements)-1]!=intptr(expr))) { opaque=true }
        return expr
    }
    def override visitExprCall(var call:ExprCall?):ExpressionPtr {
        let name=string(call.name)
        let mutators="|push|push_clone|emplace|insert|erase|clear|resize|pop|sort|reverse|"
        if (find(mutators,"|{name}|")>=0 && !is_statement(call)) { opaque=true }
        let known="|length|empty|count|range|find|key_exists|int|float|double|uint|uint64|int64|string|bool|clamp|min|max|abs|sin|cos|sqrt|floor|ceil|round|push|push_clone|emplace|insert|erase|clear|resize|pop|sort|reverse|ui_changed|"
        if (find(known,"|{name}|")>=0 || ui_tracked_function(name)) { return call }
        for (arg in call.arguments) { if (key_exists(roots,ui_write_root(arg))) { opaque=true } }
        return call
    }
}
[call_macro(name="ui_state")]
class private UiStateMacro : AstCallMacro {
    def override visit(prog:ProgramPtr; mod:Module?; var call:ExprCallMacro?):ExpressionPtr {
        let count=length(call.arguments)
        if (count<1 || count>3) { macro_error(prog,call.at,"ui_state requires initial or (name, [version,] initial)"); return null }
        let factory=make_unique_private_name("ui_state_create",call.at)
        let key=count==1 ? qmacro($v("{call.at.fileInfo.name}:{call.at.line}:{call.at.column}")) : clone_expression(call.arguments[0])
        let version=count==3 ? clone_expression(call.arguments[1]) : qmacro(1)
        var fn=qmacro_function(factory) $(key:string; version:int; initial:auto(T)) {
            static_assert(typeinfo is_struct(initial),"ui_state requires a model struct")
            rt_state_validate(initial)
            verify(!empty(key) && version>0,"ui_state needs a non-empty name and positive schema version")
            var restored := initial
            rt_live_restore("root/{key}",version,restored)
            typedef Store=$UiState<T -const -&>
            var state=new Store(restored,rt_state_id())
            delete restored
            rt_live_attach(key,version,state)
            return state
        }
        fn.flags |= FunctionFlags.generated | FunctionFlags.privateFunction
        verify(compiling_module() |> add_generic(fn))
        var result=new ExprCall(at=call.at,name:=factory)
        result.arguments |> push(key)
        result.arguments |> push(version)
        result.arguments |> push(call.arguments[count-1])
        return result
    }
}
[call_macro(name="ui_edit")]
class private UiEditMacro : AstCallMacro {
    frame:bool
    def override canVisitArgument(call:ExprCallMacro?; index:int):bool { return false }
    def override visit(prog:ProgramPtr; mod:Module?; var call:ExprCallMacro?):ExpressionPtr {
        if (length(call.arguments)!=2) {
            macro_error(prog,call.at,"ui_frame/ui_edit require ui_state and a model block; use ui_legacy_frame for compatibility")
            return null
        }
        var body=clone_expression(call.arguments[1])
        var opaque=true
        if (body is ExprMakeBlock) {
            var blk=(body as ExprMakeBlock)._block as ExprBlock
            if (length(blk.arguments)!=1) { macro_error(prog,call.at,"ui_frame/ui_edit block requires exactly one model argument"); return null }
            blk.arguments[0]._type.flags.constant=false
            blk.arguments[0]._type.flags.ref=false
            var unknown=new UiOpaqueWrites()
            make_visitor(*unknown) $(adapter) { ast::visit(body,adapter) }
            opaque=unknown.opaque
            var writes=new UiWrites(all_variables=true)
            writes.arguments[string(blk.arguments[0].name)]=true
            make_visitor(*writes) $(adapter) { ast::visit(body,adapter) }
            if (frame && writes.wrote) { opaque=true }
        }
        if (frame) { return qmacro_expr() { unsafe { rt_ui_frame($e(call.arguments[0]),$e(body),$v(opaque)) } } }
        return qmacro_expr() { unsafe { rt_ui_edit($e(call.arguments[0]),$e(body),$v(opaque)) } }
    }
}
[call_macro(name="ui_frame")]
class private UiFrameMacro : UiEditMacro { override frame=true }
[function_macro(name="ui_action")]
class private UiAction : AstFunctionAnnotation {
    def override apply(var func:FunctionPtr; var group:ModuleGroup; var args:AnnotationArgumentList; var errors:das_string):bool {
        var unknown=new UiOpaqueWrites()
        for (arg in func.arguments) { unknown.roots[string(arg.name)]=true }
        make_visitor(*unknown) $(adapter) { visit(func.body,adapter) }
        var writes=new UiWrites()
        writes.all_variables=true
        for (arg in func.arguments) { writes.arguments[string(arg.name)]=true }
        make_visitor(*writes) $(adapter) { visit(func.body,adapter) }
        if (unknown.opaque) {
            let original=func.body
            func.body=qmacro_block() { rui_hybrid_invalidate(); $e(original) }
        }
        let dump=find_arg(args,"dump")
        if (dump is tBool && dump as tBool) { print("{describe(func)}\n") }
        return true
    }
}
// Native descendants are described once, outside component reconciliation.
// Extracting a capture-free builder also keeps their expressions out of the
// component's dependency, write-tracking and mount/update/dispatch passes.
def private native_binding(name:string):bool {
    return find("|data_text|data_value|data_checked|data_disabled|data_attribute|data_class|data_style|data_event|data_if|data_for|","|{name}|")>=0
}
class private UiNativeBody : UiStatements {
    invalid:string
    def override preVisitExprBlockExpression(blk:ExprBlock?; expr:ExpressionPtr) {
        statements |> push(intptr(expr))
        if (!(expr is ExprCall) && !(expr is ExprBlock)) {
            invalid="native_data is a static description; use data_if/data_for for native structure"
        }
    }
    def override visitExprCall(var call:ExprCall?):ExpressionPtr {
        if (!is_statement(call)) { return call }
        let name=string(call.name)
        let node=find("|column|row|box|element|text|button|text_input|checkbox|select_input|text_area|","|{name}|")>=0
        let data=native_binding(name)
        let prop=typed_property(name) || find("|property|attribute|width|height|padding|padding_x|padding_y|margin_top|margin_bottom|font_size|background|color|opacity|","|{name}|")>=0
        if (!node && !data && !prop) {
            invalid="native_data does not support {name}; managed components/events belong outside the native scope"
            return call
        }
        for (arg in call.arguments) {
            if (arg is ExprMakeBlock) {
                if (!empty(((arg as ExprMakeBlock)._block as ExprBlock).arguments)) { invalid="native_data blocks cannot have script arguments" }
            } elif (!constant_argument(arg)) {
                invalid="native_data arguments must be constant; use data_* expressions for model values"
            }
        }
        if (node) { call.name := "rt_native_{name}" }
        elif (data) { call.name := "rt_native_{name}" }
        return call
    }
}
class private UiNativeScopes : UiStatements {
    invalid,prefix:string
    nesting,serial:int
    def override preVisitExprCall(call:ExprCall?) {
        if (string(call.name)=="native_data") { nesting+=1 }
    }
    def override visitExprCall(var call:ExprCall?):ExpressionPtr {
        let name=string(call.name)
        if (name!="native_data") {
            if (nesting==0 && is_statement(call) && native_binding(name)) { invalid="data_* bindings require native_data inside [ui_component]" }
            return call
        }
        nesting-=1
        if (nesting!=0) { invalid="native_data scopes cannot be nested"; return call }
        if (!empty(invalid)) { return call }
        if (!is_statement(call) || length(call.arguments)!=3 || !(call.arguments[2] is ExprMakeBlock)) {
            invalid="native_data requires name, UiDataModel and a description block"; return call
        }
        let body=clone_expression((call.arguments[2] as ExprMakeBlock)._block)
        if (!empty((body as ExprBlock).arguments)) { invalid="native_data blocks cannot have script arguments"; return call }
        var rewrite=new UiNativeBody()
        make_visitor(*rewrite) $(adapter) { visit(body,adapter) }
        if (!empty(rewrite.invalid)) { invalid=rewrite.invalid; return call }
        serial+=1
        let site="{prefix}:native:{serial}"
        let builder_name="__ui_native_{hash(site)}"
        var builder=qmacro_function(builder_name) $() { $e(body) }
        builder.flags |= FunctionFlags.generated | FunctionFlags.privateFunction
        verify(compiling_module() |> add_function(builder))
        return qmacro(rt_native_data($v(site),$e(call.arguments[0]),$e(call.arguments[1]),@@$i(builder_name)))
    }
}

[function_macro(name="ui_component")]
class private UiComponent : AstFunctionAnnotation {
    def override apply(var func : FunctionPtr; var group : ModuleGroup;
                       var args : AnnotationArgumentList; var errors : das_string) : bool {
        var signature = ""
        for (arg in func.arguments) { signature += "{describe(arg._type)};" }
        let identity = "{hash(string(func.at.fileInfo.name))}_{func.name}_{hash(signature)}"
        clear(global_lookup)
        let legacy_arg=find_arg(args,"legacy")
        let hybrid=!(legacy_arg is tBool && legacy_arg as tBool)
        var native_scopes=new UiNativeScopes(prefix=identity)
        make_visitor(*native_scopes) $(adapter) { visit(func.body,adapter) }
        if (!empty(native_scopes.invalid)) { errors := native_scopes.invalid; return false }
        var rich=new UiRichText()
        make_visitor(*rich) $(adapter) { visit(func.body,adapter) }
        if (!empty(rich.invalid)) { errors := rich.invalid; return false }
        var original_names = new UiNames()
        for (arg in func.arguments) { original_names.names[string(arg.name)] = true }
        make_visitor(*original_names) $(adapter) { visit(func.body,adapter) }
        // Arguments proper: a name that a block argument or a local of the body
        // declares again is not one, whatever it is called.
        var declared = new UiNames()
        make_visitor(*declared) $(adapter) { visit(func.body,adapter) }
        var argument_names : table<string;bool>
        for (arg in func.arguments) {
            if (!key_exists(declared.names,string(arg.name))) { argument_names[string(arg.name)] = true }
        }
        if (hybrid) {
            var controls=new UiHybridControl()
            controls.names := original_names.names
            controls.arguments := argument_names
            for (arg in func.arguments) { controls.roots[string(arg.name)]=true }
            make_visitor(*controls) $(adapter) { visit(func.body,adapter) }
            var writes=new UiWrites()
            for (arg in func.arguments) { writes.arguments[string(arg.name)]=true }
            // A global that a handler assigns is reported like a field of the model.
            var touched=new UiGlobalNames()
            touched.names := original_names.names
            make_visitor(*touched) $(adapter) { visit(func.body,adapter) }
            for (name in keys(touched.found)) { writes.arguments[name]=true }
            make_visitor(*writes) $(adapter) { visit(func.body,adapter) }
        }
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
        bindings.hybrid=hybrid
        if (hybrid) {
            var key_reads=new UiHybridKeys()
            make_visitor(*key_reads) $(adapter) { visit(func.body,adapter) }
        }
        bindings.names := names.names
        make_visitor(*bindings) $(adapter) { visit(func.body,adapter) }
        var hybrid_fallback=false
        if (hybrid) {
            var tracked_reads=new UiHybridDependencies()
            make_visitor(*tracked_reads) $(adapter) { visit(func.body,adapter) }
            var block_names : table<string;bool>
            for (arg in func.arguments) {
                if (arg._type.baseType == Type.tBlock && key_exists(argument_names,string(arg.name))) { block_names[string(arg.name)] = true }
            }
            var conservative=new UiHybridFallback()
            conservative.names := names.names
            conservative.blocks := block_names
            for (arg in func.arguments) { conservative.roots[string(arg.name)]=true }
            make_visitor(*conservative) $(adapter) { visit(func.body,adapter) }
            hybrid_fallback=conservative.fallback
            // Last: it reads the calls that the passes above have generated.
            let covered=make_unique_private_name("ui_arguments_covered",func.at)
            var inputs=new UiHybridArguments(covered=covered)
            inputs.names := names.names
            inputs.arguments := argument_names
            inputs.blocks := block_names
            var copies=new UiHybridCopies()
            make_visitor(*copies) $(adapter) { visit(func.body,adapter) }
            for (name,count in keys(copies.copied),values(copies.copied)) {
                if (!key_exists(argument_names,name) && (copies.declared?[name] ?? 0)==count) { inputs.copies[name]=true }
            }
            make_visitor(*inputs) $(adapter) { visit(func.body,adapter) }
            var body=func.body as ExprBlock
            var statements:array<ExpressionPtr>
            statements |> push <| qmacro_expr() { let $i(covered) = rt_hybrid_covered() }
            for (expr in body.list) { statements |> push(expr) }
            clear(body.list)
            for (expr in statements) { body.list |> push(expr) }
        }
        var checks : array<ExpressionPtr>
        var actuals : array<ExpressionPtr>
        if (hybrid_fallback) { checks |> push <| qmacro(rt_hybrid_fallback()) }
        for (arg in func.arguments) {
            if (arg._type.baseType == Type.tBlock || arg._type.baseType == Type.tFunction || arg._type.baseType == Type.tLambda) {
                // A borrowed slot/callback can capture changing values. Traverse
                // when visited instead of retaining or comparing its stack frame.
                // A block is code of the caller: when an analysed call site passes
                // it, everything it reads is already registered there.
                if (hybrid && arg._type.baseType == Type.tBlock) { checks |> push <| qmacro(rt_hybrid_block_argument()) }
                elif (hybrid) { checks |> push <| qmacro(rt_hybrid_fallback()) }
                else { checks |> push <| qmacro(rt_volatile_dependency()) }
            } elif (!hybrid) {
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
            if (!$v(hybrid)) { rt_hybrid_fallback() }
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
        let named=find_arg(args,"name")
        let name = named is tString ? "live_{named as tString}" : "s_{hash(identity)}"
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
        var rich=new UiRichText()
        make_visitor(*rich) $(adapter) { visit(func.body,adapter) }
        if (!empty(rich.invalid)) { errors := rich.invalid; return false }
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

