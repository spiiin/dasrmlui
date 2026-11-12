options gen2
options persistent_heap
options gc
options stack = 65536
require examples/demo_host
require examples/advanced_style
require strings

struct Card { id:int; title,owner:string; stage:int; urgent:bool }
struct Board { cards:array<Card>; draft:string; next_id:int = 7; selected:int = -1 }
def stage_count(cards:array<Card>; stage:int):int {
    var count = 0
    for (card in cards) { if (card.stage == stage) { count += 1 } }
    return count
}
def move_card(var board:Board; id:int) {
    for (card in board.cards) { if (card.id == id) { card.stage = (card.stage+1)%3 } }
}
def delete_card(var board:Board; id:int) {
    for (i in range(length(board.cards))) {
        if (board.cards[i].id == id) { board.cards |> erase(i); board.selected = -1; return }
    }
}
[ui_component]
def lane(var board:Board; stage:int; title:string) {
    use_style(@@board_style)
    column("card") {
        width(px(328.0)); margin_right(px(12))
        border_top(px(4),stage == 0 ? rgb(185,155,206) : (stage == 1 ? rgb(217,164,97) : rgb(124,186,160)))
        row("toolbar") {
            text("section",title)
            text("muted") { return "   /   {stage_count(board.cards,stage)}" }
        }
        column() {
            width(px(328.0)); height(px(335.0)); property("overflow-y","auto")
            board.cards |> each_keyed($(card:Card) => card.id) $(card:Card) {
                when(card.stage == stage) {
                    column("task") {
                        width(px(292.0))
                        text("caption") { return "NS-{100+card.id}   /   {card.owner}" }
                        text("task_title",card.title)
                        when(card.urgent) { text("warning","HIGH PRIORITY") }
                        row() {
                            button("select_card","Details") { padding(px(8.0)); on_click() { board.selected = card.id } }
                            button("move_card",stage == 2 ? "Reopen" : "Move next >") { padding(px(8.0)); on_click() { move_card(board,card.id) } }
                        }
                    }
                }
            }
            when(stage_count(board.cards,stage) == 0) { text("muted","No cards in this lane.") }
        }
    }
}
[ui_component]
def inspector(var board:Board) {
    use_style(@@board_style)
    board.cards |> each_keyed($(card:Card) => card.id) $(card:Card) {
        when(card.id == board.selected) {
            column("card") {
                width(px(1080.0))
                text("section") { return "Card details / NS-{100+card.id}" }
                row() {
                    text_input("card_title") {
                        width(px(530.0))
                        bind_value(card.title) $(value:string) {
                            if (!empty(value)) { for (target in board.cards) { if (target.id == card.id) { target.title = value } } }
                        }
                    }
                    button("urgent",card.urgent ? "High priority" : "Normal priority") {
                        padding(px(12.0)); margin_left(px(12))
                        on_click() { for (target in board.cards) { if (target.id == card.id) { target.urgent = !target.urgent } } }
                    }
                    button("delete_card","Delete") { padding(px(12.0)); color(rgb(177,63,88)); on_click() { delete_card(board,card.id) } }
                    button("close_details","Close") { padding(px(12.0)); on_click() { board.selected = -1 } }
                }
            }
        }
    }
}
[ui_component]
def kanban(var board:Board) {
    use_style(@@board_style)
    column("shell") {
        studio_header(2,"NORTHSTAR / PRODUCT TEAM","Release board","Move cards between lanes, edit details and keep the work in view.")
        row("toolbar") {
            text_input("draft_field") {
                width(px(560.0))
                bind_value(board.draft) $(value:string) { board.draft = value }
            }
            button("add_card","+ Add to backlog") {
                padding(px(12.0)); background(rgb(40,115,99)); margin_left(px(12))
                disabled() { return empty(board.draft) }
                on_click() {
                    board.cards |> push <| Card(id=board.next_id,title=board.draft,owner="You")
                    board.next_id += 1; board.draft = ""
                }
            }
            text("muted") { return "   {length(board.cards)} cards" }
        }
        row() {
            property("align-items","flex-start")
            lane(board,0,"Backlog")
            lane(board,1,"In progress")
            lane(board,2,"Done")
        }
        when(board.selected < 0) { text("muted","Select Details on any card to open the editor below.") }
        inspector(board)
    }
}
[export]
def main(smoke:bool):int {
    var board = Board()
    board.cards |> push <| Card(id=1,title="Keyboard navigation audit",owner="Maya",urgent=true)
    board.cards |> push <| Card(id=2,title="Add workspace templates",owner="Alex")
    board.cards |> push <| Card(id=3,title="Build notification center",owner="Sam",stage=1)
    board.cards |> push <| Card(id=4,title="Improve onboarding flow",owner="Jordan",stage=1,urgent=true)
    board.cards |> push <| Card(id=5,title="Ship account settings",owner="Maya",stage=2)
    board.cards |> push <| Card(id=6,title="Update status indicators",owner="Alex",stage=2)
    return run_demo("dasrmlui - Release board","logs/kanban.png",smoke,$() { kanban(board) }) $(frame:int) {
        if (frame == 0) { rui_test_click(ui_find("move_card",1)) }
        elif (frame == 1) { verify(board.cards[0].stage == 1); rui_test_click(ui_find("select_card",1)) }
        elif (frame == 2) { verify(board.selected == 1); rui_test_event(ui_find("card_title",1),"change","Keyboard audit complete") }
        elif (frame == 3) { verify(board.cards[0].title == "Keyboard audit complete"); rui_test_click(ui_find("delete_card",1)) }
        elif (frame == 4) { verify(length(board.cards) == 5 && board.selected == -1); rui_test_event(ui_find("draft_field"),"change","Write migration guide") }
        elif (frame == 5) { rui_test_click(ui_find("add_card")) }
        elif (frame == 6) { verify(length(board.cards) == 6 && empty(board.draft) && ui_find("select_card",7) != 0ul) }
    }
}
