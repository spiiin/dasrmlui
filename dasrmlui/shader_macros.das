options gen2
module shader_macros public
require glsl/glsl_internal
require daslib/ast public
require daslib/ast_boost
require daslib/templates_boost
require daslib/ast_used
require strings

// These macros use the upstream typed AST emitter, not a source parser.
class private UiGpuAnnotation : AstFunctionAnnotation {
    filter:bool
    def suffix():string { return filter ? "_filter" : "_shader" }
    def override apply(var func:FunctionPtr; var group:ModuleGroup; var args:AnnotationArgumentList; var errors:das_string):bool {
        if (length(args)!=0) { errors := "UI shader annotations do not accept options"; return false }
        if (func.name=="main") { errors := "main is reserved by the UI shader adapter"; return false }
        func.flags.exports=true
        let source="{func.name}`ui_source"
        let signature="{func.name}`ui_signature"
        if (!add_global_var(compiling_module(),source,new TypeDecl(at=func.at,baseType=Type.tString),func.at,false) ||
            !add_global_var(compiling_module(),signature,new TypeDecl(at=func.at,baseType=Type.tString),func.at,false)) {
            errors := "UI shader annotations cannot share an entry point or overload its name"; return false
        }
        let factory="{func.name}{suffix()}"
        let is_filter=filter
        var generated=qmacro_function(factory) $():UiShaderProgram {
            return UiShaderProgram(source=$i(source),signature=$i(signature),filter=$v(is_filter))
        }
        generated.at=func.at; generated.atDecl=func.at
        if (!(compiling_module() |> add_function(generated))) { errors := "UI shader descriptor name already exists"; return false }
        return true
    }
    def override fixup(var func:FunctionPtr; var group:ModuleGroup; var args:AnnotationArgumentList; progArgs:AnnotationArgumentList; var errors:das_string):bool {
        var output=find_variable(compiling_module(),"{func.name}`ui_source")
        if (output.init!=null) { return true }
        if (func.result.baseType!=Type.tFloat4 || func.result.isRef) { errors := "[ui_shader/ui_filter] must return float4"; return false }
        var signature=""; var arguments=""
        for (arg in func.arguments) {
            let name=string(arg.name); let t=arg._type.baseType
            if (arg.init!=null || !arg._type.flags.constant) { errors := "UI shader arguments must be read-only, without defaults"; return false }
            var actual=""
            if (name=="uv" || name=="size" || name=="texel") {
                if (t!=Type.tFloat2) { errors := "UI shader uv/size/texel must be float2"; return false }
                actual=name=="uv" ? "uv" : "u_{name}"
            } elif (name=="time") {
                if (t!=Type.tFloat) { errors := "UI shader time must be float"; return false }
                actual="u_time"
            } else {
                if (t!=Type.tFloat && t!=Type.tFloat4) { errors := "UI shader parameters must be float (number/length) or float4 (color)"; return false }
                var valid=!empty(name)
                for (ch,i in name,count()) {
                    valid=valid && ((ch>='a' && ch<='z') || (i>0 && ((ch>='0' && ch<='9') || ch=='_')))
                }
                if (!valid) { errors := "UI shader parameter names require lowercase letters, digits or underscores"; return false }
                actual="p_{name}"
                signature+="{name}:{t==Type.tFloat ? "f" : "c"};"
            }
            arguments+="{empty(arguments) ? "" : ", "}{actual}"
        }
        var dependency_error=""
        collect_dependencies(func) $(functions,variables) {
            for (g in variables) {
                if (g._module.name=="glsl_ui_builtins") {
                    if (!filter) { dependency_error="sample_source is only available in [ui_filter]" }
                } elif (g._module.name!="shader_lingua_franca" && g._module.name!="glsl_common" && !g._type.flags.constant) {
                    dependency_error="UI shaders cannot capture mutable CPU globals; pass a style parameter"
                }
            }
            for (fn in functions) {
                if (string(fn.name)=="dasrmlui_entry") { dependency_error="dasrmlui_entry is reserved by the UI shader adapter" }
            }
        }
        if (!empty(dependency_error)) { errors := dependency_error; return false }
        var diagnostics:array<string>
        var caps:ShaderExportCaps
        // The existing native ABI supplies #version, inputs, uniforms and main.
        let generated=generate_glsl(func,diagnostics,ShaderType.fragment,330,int3(0),caps)
        if (!empty(diagnostics)) {
            errors := "dasGlsl: {diagnostics[0]}"; return false
        }
        var function_name=""
        build_string() $(var writer) {
            var emitter=new GlslExport(writer,ShaderType.fragment,330,int3(0),caps)
            collect_dependencies(func) $(functions,variables) {
                collect_used_types(functions,variables) $(types) {
                    for (st in keys(types.st)) { emitter.stnames["{st.name}"]=true }
                }
            }
            function_name=emitter.glsl_function_name(func)
            unsafe { delete emitter }
        }
        // The alias applies only to the native main appended after this source.
        // It also permits a user entry function literally named 'effect'.
        let source="// daScript entry: {func.name}\n{generated.body}\nvec4 dasrmlui_entry(vec2 uv) \{ return {function_name}({arguments}); \}\n#define effect dasrmlui_entry\n"
        output.init=new ExprConstString(at=func.at,value:=source,_type=new TypeDecl(at=func.at,baseType=Type.tString))
        output._type.flags.constant=true
        var schema=find_variable(compiling_module(),"{func.name}`ui_signature")
        schema.init=new ExprConstString(at=func.at,value:=signature,_type=new TypeDecl(at=func.at,baseType=Type.tString))
        schema._type.flags.constant=true
        return true
    }
}
[function_macro(name="ui_shader")]
class UiShaderAnnotation : UiGpuAnnotation {}
[function_macro(name="ui_filter")]
class UiFilterAnnotation : UiGpuAnnotation { override filter=true }
