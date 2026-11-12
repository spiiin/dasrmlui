options gen2
require dasrmlui/ui
[ui_style]
def invalid_style() {
    media(media_max_width(dp(800))) { theme("night") { rule(root()) { width(dp(100)) } } }
}
[export]
def main(smoke:bool):int { use_style(@@invalid_style); return 0 }
