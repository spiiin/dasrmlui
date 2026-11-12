options gen2
options persistent_heap
options gc
options stack = 65536
require dasrmlui/ui
require strings
require math
require dassdl3/sdl3_window_boost
require dassdl3/sdl3_scope

var plain_runs,observed_runs,parent_runs,mounts,unmounts:int
struct Draft { value:string="kept" }
[ui_style]
def adaptive_style() {
    rule(part("probe")) { width(dp(100)); height(dp(30)); padding(dp(0)); background(rgb(1,2,3)) }
    theme("night") { rule(part("probe")) { height(dp(40)) } }
    media(media_max_width(dp(500))) { rule(part("probe")) { width(dp(80)) } }
    media(media_and(media_theme("night"),media_min_resolution(1.5))) { rule(part("probe")) { height(dp(50)) } }
    media(media_orientation("portrait")) { rule(part("probe")) { padding(dp(2)) } }
    media(media_not(media_theme("night"))) { rule(part("day_flag")) { width(px(17)) } }
    rule(part("day_flag")) { height(px(5)) }
    spritesheet("examples/assets/style_atlas.png",2.) {
        sprite("frame",0,0,96,96); sprite("inner",24,24,48,48)
    }
    rule(part("patch")) { width(px(160)); height(px(80)); ninepatch("frame","inner",dp(12)) }
}
[ui_component]
def plain() {
    plain_runs+=1
    use_style(@@adaptive_style)
    state(Draft()) $(var local:Draft) {
        on_mount() { mounts+=1 }
        on_unmount() { unmounts+=1 }
        column() {
            box("probe") {}; box("day_flag") {}; box("patch") {}
            text_input("input") { bind_value(local.value) $(value:string) { local.value=value } }
        }
    }
}
[ui_component]
def observed() {
    observed_runs+=1
    text("environment","{ui_theme()} / {ui_dp_ratio()} / {ui_scale()} / {theme_active("night")}")
}
[ui_component]
def screen() { parent_runs+=1; plain(); observed() }
[export]
def main(smoke:bool):int {
    let result=sdl_scope() {
        with_sdl() |> sdl_use
        let window:SDL_Window?=with_window("Style environment",800,600,SDL_WINDOW_HIDDEN) |> sdl_use
        let renderer:SDL_Renderer?=window |> with_renderer() |> sdl_use
        for (generation in range(2)) {
            verify(rui_init(window,renderer,800,600)); verify(rui_default_font())
            verify(ui_scale()==1. && empty(ui_theme()) && !theme_active("night"),"new context resets environment")
            verify(abs(ui_dp_ratio()-SDL_GetWindowDisplayScale(window))<0.01,"initial display scale")
            rui_test_display_scale(1.)
            ui_frame() { screen() }
            let probe=ui_find("probe"); let input=ui_find("input"); let env_text=ui_find("environment")
            verify(rui_bounds(probe).z==100. && rui_bounds(probe).w==30.)
            rui_focus(input); rui_test_event(input,"change","saved draft")
            ui_frame() { screen() }
            let plain_before=plain_runs; let observed_before=observed_runs
            set_theme("night")
            ui_frame() { screen() }
            verify(rui_bounds(probe).w==40. && plain_runs==plain_before,"native style changes do not rerun plain component")
            verify(observed_runs==observed_before+1 && find(rui_inner_markup(env_text),"night")>=0,"wake reader through cached parent")
            set_theme("day")
            ui_frame() { screen() }
            verify(!theme_active("night") && theme_active("day") && rui_bounds(probe).w==30.)
            verify(rui_bounds(ui_find("day_flag")).z==17.,"media not")
            activate_theme("contrast"); set_theme("night")
            ui_frame() { screen() }
            verify(theme_active("contrast") && theme_active("night") && !theme_active("day"),"independent theme flags survive palette switch")
            set_ui_scale(1.5)
            ui_frame() { screen() }
            verify(ui_dp_ratio()==1.5 && rui_bounds(probe).z==150. && rui_bounds(probe).w==75.,"dp and theme/resolution conjunction")
            verify(find(rui_inner_markup(env_text),"1.5")>=0 && plain_runs==plain_before)
            rui_test_display_scale(2.)
            ui_frame() { screen() }
            verify(ui_dp_ratio()==3. && ui_scale()==1.5 && rui_bounds(probe).z==240.,"display scale preserves user multiplier and dp media width")
            set_ui_scale(1.); rui_test_display_scale(1.)
            rui_test_resize(400,600)
            ui_frame() { screen() }
            verify(rui_bounds(probe).z==84. && rui_bounds(probe).w==44.,"portrait and dp breakpoint")
            verify(ui_find("input")==input && rui_focused(input) && rui_get_value(input)=="saved draft")
            unsafe { heap_collect(true,false) }
            rui_test_resize(800,600)
            ui_frame() { screen() }
            verify(rui_bounds(probe).z==100. && rui_bounds(probe).w==40.)
            let revision=rui_style_revision(); let runs=observed_runs
            set_theme("night"); set_ui_scale(1.); activate_theme("contrast")
            ui_frame() { screen() }
            verify(rui_style_revision()==revision && observed_runs==runs,"idempotent setters")
            verify(!rui_set_ui_scale(0.) && !rui_set_ui_scale(-1.) && ui_scale()==1.,"reject invalid scales")
            set_theme(""); activate_theme("night")
            ui_frame() { screen() }
            let before_selection=rui_style_revision(); let before_reader=observed_runs
            set_theme("night")
            ui_frame() { screen() }
            verify(rui_style_revision()>before_selection && observed_runs==before_reader+1,
                "selecting an already active flag still updates palette readers")
            ui_reset(); rui_shutdown()
            verify(mounts==unmounts)
        }
        print("PASS: native media, theme flags, dp, initial/changed DPI, user scale, selective invalidation, focus/state, GC, reset\n")
        return sdl_ok()
    }
    if (is_err(result)) { print("{unwrap_err(result).message}\n"); return 1 }
    return 0
}

