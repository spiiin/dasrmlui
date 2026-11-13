# Inline rich text

`[ui_component]` and `[ui_template]` describe formatted text with regular daScript
blocks. The macro creates a native RmlUi inline tree; line wrapping, font metrics,
baseline, inheritance and images are laid out by RmlUi itself. No RML string is needed.

```dascript
[ui_component]
def message(var model:Model) {
    rich_text("paragraph") {
        width(px(480)); font_size(px(20)); line_height(1.5)
        text("hello", "Hello, ")
        strong("name") {
            emphasis("accent") { text("value", model.name) }
        }
        text("space", "! ")
        inline_image("badge", model.image) {
            width(em(1.2)); height(em(1.2)); vertical_align("middle")
        }
        text("gap", " ")
        link("details", model.target) {
            text("caption", "Read more")
            on_activate() { model.opened = true }
        }
        line_break()
        span("fine_print") {
            font_size(em(0.8)); color(rgb(110,120,130))
            text("note", "A second line, in smaller type.")
        }
    }
}
```

The model for this fragment contains `name`, `image`, `target` of type string and
`opened` of type bool. `image` is a path to a PNG, `target` is an address or an
application identifier.

## Elements

| Call | Native representation and behavior |
|---|---|
| `rich_text(name) { ... }` | `div`, `display: block`; regular text flow, no flex |
| `span(name) { ... }` | `span`, `display: inline`; nested styles and content |
| `strong(name) { ... }` | Inline span with `font-weight: bold` |
| `emphasis(name) { ... }` | Inline span with `font-style: italic` |
| `underline(name) { ... }` | Inline span with `text-decoration: underline` |
| `strike(name) { ... }` | Inline span with `text-decoration: line-through` |
| `link(name, target) { ... }` | Inline `a`, reactive `href`, underline, focus and tab-index auto |
| `inline_image(name, source) { ... }` | Inline `img`, reactive `src`; the style/attribute block is optional |
| `inline_sprite(name, sprite_id) { ... }` | Inline `img`, `sprite` from the current scoped spritesheet; the block is optional |
| `line_break(name)` | Native `br`; the name is optional |

For `rich_text`, `span`, `strong`, `emphasis`, `underline`, `strike` the name can be
omitted: `strong() { text("value", "Important") }`. Names become regular `part(name)`
and are accessible through `ui_find(name)`. Formatting containers nest inside each
other; `text(name, value)` and the getter variant remain the usual text leaves.

Spaces are not added automatically: put them in the text between fragments.
`white-space: normal` collapses spaces by the RmlUi rules; `white_space("pre-wrap")`
preserves them and line breaks. `line_break()` creates an explicit break regardless of
how the daScript source is split into lines.

## Styles and fonts

The text helpers work in components, `[ui_style]`, templates and keyframes:

- `font_weight(string)`, `font_style(string)`, `text_decoration(string)`;
- `line_height(float)` — a multiplier; `line_height(UiLength)` — px/em/% and other units;
- `vertical_align(string)` or `vertical_align(UiLength)`;
- `white_space(string)`, `word_break(string)`, `text_align(string)`.

`vertical_align("baseline")` is the standard position of an inline image;
`"middle"`, `"super"`, `"sub"`, `"top"` and other native values are passed to RCSS.
Do not use `row()` for a paragraph: flex does not wrap a single text flow.
The `width`/`height` properties are set on the paragraph and on images; a regular
inline span has the size of its content. For an independent rectangular block there is
`display("inline-block")`.

The semantic helpers set properties directly on the element. Inside the block you can
override them, for example `strong() { font_weight("normal"); ... }`.
Other styles are set with regular scoped `rule(part(...))`, including `:hover` and
`:focus`. The inheritance scope ends on leaving the span; the formatting of neighboring
fragments does not change. Allowed values and the specifics of text-decoration are
defined by RCSS.

Real font styles require the corresponding font faces to be loaded. The built-in
`rui_default_font_styles()` loads LatoLatin Regular, Bold, Italic, BoldItalic.
All four files and the license are included in the runtime package; the regular
`rui_default_font()` still loads only Regular. For your own font, use `rui_font(...)`
for each font style. For other alphabets, load a suitable font/fallback.

## Links and images

`on_activate() { ... }` receives click, including the native click from Enter/Space on
a focused link. There is no separate repeated key handler. Tab works thanks to
`tab-index: auto`. An event from the child text bubbles up to the link. You can use
regular `on_click`/`on_event` for more specialized behavior.

`href` is application data. Neither the helper nor the RmlUi bridge launches a browser
or follows a URL automatically; the handler decides whether to open a panel or call an
action allowed by the application. `href(value)` and `image_source(value)` are
shorthand for reactive `attribute("href", value)` and `attribute("src", value)`.

`inline_image` uses the existing native PNG loader; the path is resolved as for
regular RmlUi images. For an atlas use `inline_sprite` and `spritesheet`.
`width`, `height`, `vertical_align`, `image_color`, margins and other properties
can be set inside the block. There is no new image loader and no separate layout for
images.

## Dynamics and macro expansion

Conceptually:

```dascript
strong("name") { text("value", model.name) }
// -> before the regular generation of site IDs and bindings:
element("name", "span") {
    display("inline")
    font_weight("bold")
    text("value", model.name)
}

link("details", model.target) { text("caption", "Read"); on_activate() { open_panel() } }
// -> inline a + attribute("href", model.target) + focus/tab-index/cursor/underline
//    + independent bindings of the child nodes + a regular event handler.
```

The link container is not wrapped in the binding of its `href`: the child text,
properties and handlers have their own dependencies. A change of the text, address or
image preserves the nodes; RmlUi lays out the affected text flow again. `when` and
`each_keyed` inside a paragraph use the regular lifetime and identity rules.

`[ui_component]` uses native DataViews by default for the direct fields
`text`, `href`, `src`. Create `state = ui_state(initial)` once and call
`ui_frame(state) $(model:Model) { message(model) }` in the application loop.
The `on_activate` handler in the example automatically tracks the write to opened.
For an external change use edit:

```dascript
ui_edit(state) $(var model:Model) {
    model.name = "Alex"
    model.target = "journal:appendix"
}
```

`ui_read(state) $(model:Model) { ... }` provides readonly access. The state deep-copies
initial, so changing the source structure does not update the UI. The model must not be
stored outside the borrow scope. [Full contract](hybrid.md).
The old value-comparison path is available explicitly through
`[ui_component(legacy=true)]` and `ui_legacy_frame()`.

In hybrid, direct changes of these three fields do not require a traversal of the
formatted tree. Computed expressions and structural changes keep the regular fallback.
`text` values remain text: `<tag>` does not create an element. RmlUi processes its own
text entities and whitespace; a Markdown/HTML parser and a formatted-text editor are
not part of this API. Static content also works in `[ui_template]`; events and
dynamics should be placed in the components that fill the slot.

## Example and checks

From the project root:

```powershell
./tools/build.ps1
./build/bin/dasrmlui.exe examples/rich_text_lab.das
ctest --test-dir build -R 'rich_text' --output-on-failure
```

The Field Notes shows nested font styles, text size and width, links, a superscript
footnote, PNG and sprites inside sentences. A `--smoke-test` run saves a screenshot to
`logs/rich_text_lab.png`.

`tests/rich_text.das` checks the native line count/positions when the width changes,
the baseline of 16/32 px text and of an image, superscript, inherited
bold/italic/color, br, nowrap, pre-wrap, spaces between fragments, preservation of
handles, reactive text/href/src, mouse/Enter/Space without double activation,
conditional unmount, templates, GC and the absence of recomputation of the hybrid
component. A separate negative test checks the diagnostics of an incorrect `link` call.
The runtime package runs the example with its own fonts. The read-only probes
`rui_text_line_count`, `rui_text_line_position`, `rui_text_line` read the first text
descendant of the given node; the position is absolute x/baseline-y after Update.
`rui_computed_property` lets you check inheritance.

Native semantics: [inline layout and baseline](https://mikke89.github.io/RmlUiDoc/pages/rcss/visual_formatting_model_details.html),
[text/whitespace](https://mikke89.github.io/RmlUiDoc/pages/rcss/text.html).
