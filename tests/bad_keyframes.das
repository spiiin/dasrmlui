options gen2
require dasrmlui/ui

[ui_style]
def invalid_style() {
    keyframes("backwards") {
        keyframe(0.) { opacity(0.) }
        keyframe(70.) { opacity(0.7) }
        keyframe(30.) { opacity(0.3) }
        keyframe(100.) { opacity(1.) }
    }
}
[export]
def main(smoke:bool):int { use_style(@@invalid_style); return 0 }
