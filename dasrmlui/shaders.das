options gen2
module shaders public
require dasrmlui/ui public
require dasrmlui/glsl_ui_builtins public
require dasrmlui/shader_macros public
require strings
require daslib/strings_boost

struct UiShaderProgram { source,signature:string; filter:bool }
def private validate_shader_program(program:UiShaderProgram; params:array<UiEffectParam>; filter:bool) {
    if (program.filter!=filter) { panic("UI shader/filter registration kind does not match its annotation") }
    var matched=0
    for (field in split(program.signature,";")) {
        if (empty(field)) { continue }
        var inscope parts <- split(field,":")
        if (length(parts)!=2 || (parts[1]!="f" && parts[1]!="c")) { panic("Invalid UI shader signature") }
        var found=false
        for (param in params) {
            // RCSS uses hyphens, while daScript identifiers use underscores.
            let name=replace(param.name,"-","_")
            if (name!=parts[0]) { continue }
            if (found) { panic("Duplicate UI shader parameter") }
            found=true; matched+=1
            if ((parts[1]=="c" && param.parser!="color") ||
                (parts[1]=="f" && param.parser!="number" && param.parser!="length_percent")) {
                panic("UI shader parameter '{param.name}' has incompatible RCSS type")
            }
        }
        if (!found) { panic("Missing UI shader parameter '{parts[0]}'") }
    }
    if (matched!=length(params)) { panic("Extra UI shader parameter absent from its function signature") }
}
def register_shader(name:string; program:UiShaderProgram; params:array<UiEffectParam>):uint64 {
    validate_shader_program(program,params,false)
    return register_shader(name,program.source,params)
}
def register_shader(name:string; program:UiShaderProgram):uint64 {
    var inscope params:array<UiEffectParam>; return register_shader(name,program,params)
}
def register_filter(name:string; program:UiShaderProgram; params:array<UiEffectParam>; overflow:float=0.):uint64 {
    validate_shader_program(program,params,true)
    return register_filter(name,program.source,params,overflow)
}
def register_filter(name:string; program:UiShaderProgram; overflow:float=0.):uint64 {
    var inscope params:array<UiEffectParam>; return register_filter(name,program,params,overflow)
}
