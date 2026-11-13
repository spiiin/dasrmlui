# Inline rich text

`[ui_component]` и `[ui_template]` описывают форматированный текст обычными блоками
daScript. Макрос создаёт native inline-дерево RmlUi; переносы, шрифтовые метрики,
baseline, наследование и изображения раскладывает сам RmlUi. Строка RML не нужна.

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

Модель для этого фрагмента содержит `name`, `image`, `target` типа string и `opened`
типа bool. `image` — путь к PNG, `target` — адрес или прикладной идентификатор.

## Элементы

| Вызов | Native-представление и поведение |
|---|---|
| `rich_text(name) { ... }` | `div`, `display: block`; обычный текстовый поток, без flex |
| `span(name) { ... }` | `span`, `display: inline`; вложенные стили и содержимое |
| `strong(name) { ... }` | Inline span с `font-weight: bold` |
| `emphasis(name) { ... }` | Inline span с `font-style: italic` |
| `underline(name) { ... }` | Inline span с `text-decoration: underline` |
| `strike(name) { ... }` | Inline span с `text-decoration: line-through` |
| `link(name, target) { ... }` | Inline `a`, reactive `href`, underline, focus и tab-index auto |
| `inline_image(name, source) { ... }` | Inline `img`, reactive `src`; блок стилей/атрибутов необязателен |
| `inline_sprite(name, sprite_id) { ... }` | Inline `img`, `sprite` из текущего scoped spritesheet; блок необязателен |
| `line_break(name)` | Native `br`; имя необязательно |

У `rich_text`, `span`, `strong`, `emphasis`, `underline`, `strike` имя можно опустить:
`strong() { text("value", "Important") }`. Имена становятся обычными `part(name)`
и доступны через `ui_find(name)`. Форматированные контейнеры вкладываются друг в
друга; `text(name, value)` и getter-вариант остаются привычными текстовыми листьями.

Пробелы не добавляются автоматически: указывайте их в тексте между фрагментами.
`white-space: normal` схлопывает пробелы по правилам RmlUi; `white_space("pre-wrap")`
сохраняет их и переводы строк. `line_break()` создаёт явный разрыв независимо от
разбиения исходного daScript на строки.

## Стили и шрифты

Добавлены helpers, работающие в компонентах, `[ui_style]`, шаблонах и keyframes:

- `font_weight(string)`, `font_style(string)`, `text_decoration(string)`;
- `line_height(float)` — множитель; `line_height(UiLength)` — px/em/% и другие единицы;
- `vertical_align(string)` или `vertical_align(UiLength)`;
- `white_space(string)`, `word_break(string)`, `text_align(string)`.

`vertical_align("baseline")` — стандартное положение inline-изображения;
`"middle"`, `"super"`, `"sub"`, `"top"` и прочие native значения передаются в RCSS.
Не используйте `row()` для абзаца: flex не выполняет перенос единого текстового потока.
Свойства `width`/`height` задаются абзацу и изображениям; обычный inline span имеет
размер содержимого. Для независимого прямоугольного блока есть `display("inline-block")`.

Семантические helpers задают свойства непосредственно на элементе. Внутри блока
можно переопределить их, например `strong() { font_weight("normal"); ... }`.
Остальные стили задаются обычными scoped `rule(part(...))`, включая `:hover` и `:focus`.
Область наследования заканчивается при выходе из span; форматирование соседних
фрагментов не меняется. Допустимые значения и особенности text-decoration определяет RCSS.

Для настоящих начертаний нужно загрузить соответствующие font faces. Встроенный
`rui_default_font_styles()` загружает LatoLatin Regular, Bold, Italic, BoldItalic.
Все четыре файла и лицензия включены в runtime package; обычный `rui_default_font()`
по-прежнему загружает только Regular. Для своего шрифта используйте `rui_font(...)`
для каждого начертания. Для других алфавитов загрузите подходящий шрифт/fallback.

## Ссылки и изображения

`on_activate() { ... }` получает click, включая native click от Enter/Space на
сфокусированной ссылке. Отдельного повторного key-handler нет. Tab работает благодаря
`tab-index: auto`. Событие от дочернего текста всплывает к ссылке. Можно использовать
обычные `on_click`/`on_event` для более специального поведения.

`href` — данные приложения. Ни helper, ни RmlUi-мост не запускают браузер и не
переходят по URL автоматически; обработчик решает, открыть панель или вызвать
разрешённое приложением действие. `href(value)` и `image_source(value)` — сокращения
для reactive `attribute("href", value)` и `attribute("src", value)`.

`inline_image` использует существующий native PNG loader; путь разрешается как у
обычных RmlUi-изображений. Для атласа применяйте `inline_sprite` и `spritesheet`.
`width`, `height`, `vertical_align`, `image_color`, margins и остальные свойства
можно задавать внутри блока. Нового image loader и отдельного layout для картинок нет.

## Динамика и разворачивание макроса

Концептуально:

```dascript
strong("name") { text("value", model.name) }
// -> перед обычной генерацией site IDs и bindings:
element("name", "span") {
    display("inline")
    font_weight("bold")
    text("value", model.name)
}

link("details", model.target) { text("caption", "Read"); on_activate() { open_panel() } }
// -> inline a + attribute("href", model.target) + focus/tab-index/cursor/underline
//    + независимые bindings дочерних узлов + обычный обработчик события.
```

Контейнер ссылки не заворачивается в binding её `href`: дочерний текст, свойства и
обработчики имеют собственные зависимости. Изменение текста, адреса или изображения
сохраняет узлы; RmlUi заново раскладывает затронутый текстовый поток. `when` и
`each_keyed` внутри абзаца используют обычные правила lifetime и identity.

`[ui_component]` по умолчанию использует native DataViews для прямых полей
`text`, `href`, `src`. Создайте `state = ui_state(initial)` один раз и вызывайте
`ui_frame(state) $(model:Model) { message(model) }` в цикле приложения.
Обработчик `on_activate` в примере автоматически отслеживает запись opened.
Для внешнего изменения используйте edit:

```dascript
ui_edit(state) $(var model:Model) {
    model.name = "Alex"
    model.target = "journal:appendix"
}
```

`ui_read(state) $(model:Model) { ... }` предоставляет readonly доступ. State глубоко
копирует initial, поэтому изменение исходной структуры не обновляет UI. Модель
нельзя сохранять за пределами borrow scope. [Полный контракт](hybrid.md).
Старый путь сравнения значений доступен явно через `[ui_component(legacy=true)]`
и `ui_legacy_frame()`.

В hybrid прямые изменения этих трёх полей не требуют обхода форматированного дерева.
Вычисляемые выражения и структурные изменения сохраняют обычный fallback.
Значения `text` остаются текстом: `<tag>` не создаёт элемент. RmlUi обрабатывает свои
text entities и whitespace; Markdown/HTML-парсер и редактор форматированного текста
в этот API не входят. Статическое содержимое работает и в `[ui_template]`, события
и динамику следует размещать в компонентах, заполняющих slot.

## Пример и проверки

Из корня проекта:

```powershell
./tools/build.ps1
./build/bin/dasrmlui.exe examples/rich_text_lab.das
ctest --test-dir build -R 'rich_text' --output-on-failure
```

The Field Notes показывает вложенные начертания, размер и ширину текста, ссылки,
надстрочную сноску, PNG и спрайты внутри предложений. Снимок: `logs/rich_text_lab.png`.

`tests/rich_text.das` проверяет native line count/positions при изменении ширины,
baseline текста 16/32 px и изображения, superscript, inherited bold/italic/color,
br, nowrap, pre-wrap, пробелы между фрагментами, сохранение handles, reactive
text/href/src, mouse/Enter/Space без двойной активации, условный unmount, шаблоны,
GC и отсутствие пересчёта hybrid-компонента. Отдельный отрицательный тест проверяет
диагностику неправильного вызова `link`. Runtime package запускает пример со своими
шрифтами. Read-only probes `rui_text_line_count`, `rui_text_line_position`,
`rui_text_line` читают первый текстовый потомок указанного узла; позиция — абсолютные
x/baseline-y после Update. `rui_computed_property` позволяет проверить наследование.

Native-семантика: [inline layout и baseline](https://mikke89.github.io/RmlUiDoc/pages/rcss/visual_formatting_model_details.html),
[text/whitespace](https://mikke89.github.io/RmlUiDoc/pages/rcss/text.html).
