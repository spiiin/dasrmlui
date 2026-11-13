options gen2
module state_types public
require daslib/typemacro_boost public
require daslib/templates

// Script GC owns the object and its deep-cloned model. No writable accessor is
// exposed; the edit/frame macros use a checked, unsafe internal bridge.
[template_structure(T)]
class template UiState {
    private data:array<T>
    private identity:uint64
    def UiState(initial:T; id:uint64) { data |> push_clone(initial); identity=id }
    def const read(body:block<(value:T):void>) { invoke(body,data[0]) }
    def const id():uint64 { return identity }
}
