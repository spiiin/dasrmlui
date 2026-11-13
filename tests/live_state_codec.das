options gen2
options gc
options persistent_heap
require dasrmlui/live

enum Choice {
    First
    Second
}
struct Item { value:int=17; title:string="default" }
typedef Alternative=variant<number:int; words:array<string>>
struct Payload {
    alternative:Alternative
    items:array<Item>
    by_id:table<int;Item>
    by_name:table<string;array<int>>
    large:uint64
    vector:float2
    fixed:int[2]
    choice:Choice=Choice.First
}
struct Before { keep:int; removed:int }
struct After { added:string="new"; keep:int }
[export]
def init() {
    ui_live_window("State codec tests",300,200)
    var data=Payload()
    var words:array<string>
    words |> push("owned variant")
    data.alternative <- Alternative(words <- words)
    data.items |> push(Item(value=42,title="owned"))
    data.by_id[5]=Item(value=55,title="integer key")
    data.by_name["array"] |> push(9)
    data.large=18446744073709551615ul
    data.vector=float2(1.5,2.5)
    data.fixed[0]=8; data.fixed[1]=13
    data.choice=Choice.Second
    rt_live_save("codec",1,data)
    delete data
    unsafe { heap_collect(true,false) }
    var restored=Payload()
    rt_live_restore("codec",1,restored)
    verify(restored.items[0].value==42 && restored.items[0].title=="owned")
    verify(restored.by_id[5].value==55 && restored.by_name["array"][0]==9)
    verify(restored.large==18446744073709551615ul && restored.vector==float2(1.5,2.5))
    verify(restored.fixed[0]==8 && restored.fixed[1]==13 && restored.choice==Choice.Second)
    verify(restored.alternative is words && (restored.alternative as words)[0]=="owned variant")
    delete restored
    rt_live_save("fields",1,Before(keep=99,removed=12))
    var after=After()
    rt_live_restore("fields",1,after)
    verify(after.keep==99 && after.added=="new","field order/addition/removal preserves current defaults")
    delete after
    print("PASS: live JSON nested arrays/tables, integer keys, uint64, vectors, fixed arrays, enum and field evolution\n")
    request_exit()
}
[export]
def update() {}
