# Публичный DataModel: компоненты daScript и внешний RML

`require dasrmlui/ui` экспортирует API моделей, зарегистрированных в текущем
`Rml::Context`. Модель можно подключить к `[ui_component]` через `native_data`
или к существующим `.rml`/`.rcss` с native `data-*`.
Компоненты с обычными `bind_value`/`text(model.field)` продолжают использовать `ui_state`, `ui_edit`
и `ui_frame`; вручную создавать эту модель или опрашивать её события не нужно.

## Внутри ui_component, без внешнего RML

```dascript
[ui_style]
def dispatch_style() {
    rule(part("form")) { width(px(420)); padding(px(24)) }
    rule(with_class(part("cargo_row"), "priority")) { background(rgb(250,230,190)) }
}

[ui_component]
def dispatch_panel(model:UiDataModel) {
    use_style(@@dispatch_style)
    native_data("form", model) {
        column("fields") {
            text_input("captain") { data_value("voyage.captain") }
            checkbox("ready") { data_checked("voyage.ready") }
            button("depart", "Разрешить отправку") {
                data_disabled("!voyage.ready")
                data_event("click", "depart(voyage.captain)")
            }
            text("status") { data_text("status") }
            data_if("notice", "voyage.ready") { text("notice_text", "Готово") }
            data_for("cargo_row", "item", "cargo") {
                data_class("priority", "item.priority")
                text("name") { data_text("item.name") }
            }
        }
    }
}
```

Модель объявляется теми же `ui_data_model`/`ui_data_bind`, что и для внешнего RML.
Её handle можно хранить в структуре `ui_state` и передавать компоненту внутри
`ui_frame`. `ui_data_events(model)` обрабатывается приложением перед кадром;
`data_event` регистрирует native expression, а имя callback предварительно
объявляется через `ui_data_on`. Смена handle через `ui_edit` переподключает область.

| Конструкция | Native-привязка |
|---|---|
| `data_text(expression)` | Текстовая интерполяция RmlUi |
| `data_value(path)`, `data_checked(path)` | Двустороннее значение input/select/textarea и checkbox |
| `data_disabled(expression)` | Атрибут disabled |
| `data_attribute(name, expression)` | Атрибут элемента |
| `data_style(name, expression)` | Inline-свойство RCSS |
| `data_class(name, expression)` | Scoped state class, совместимая с `with_class` |
| `data_event(kind, expression)` | Native event expression: callback или присваивание |
| `data_if(name, expression) { ... }` | Native условная область |
| `data_for(name, alias, array_path) { ... }` | Native повторение; допускается вложенность |

Внутри области доступны `column`, `row`, `box`, `element`, `text`, `button`,
`text_input`, `checkbox`, `select_input`, `text_area`, `attribute` и обычные
typed property helpers. `element` позволяет описывать дополнительные native теги,
например `option`, `img` или `label`. Текст и значения атрибутов экранируются;
`text("name", "...")` остаётся буквальным текстом, включая двойные фигурные скобки.

Макрос выносит описание в статическую функцию без captures. Она сериализует
внутренний RML **только при mount или смене модели**. Файла на диске и отдельной
аннотации нет. Тело — статическая схема: имена, captions, свойства и строки
expressions должны быть константами. Изменяемые значения читаются через `data_*`.
Произвольные script-вызовы, `when`, `each_keyed`, component callbacks и вложенные
`native_data` внутри схемы отклоняются при компиляции. Их можно использовать
**снаружи** области. Native expressions разбирает RmlUi во время mount, не компилятор daScript.
Host также не должен наследовать `data-model` от внешнего RML-предка:
вложение независимых native scopes в такую область отклоняется при mount.

Runtime учитывает только host области. Внутри него находится отдельный native
model root; его потомки не участвуют в reconciliation. Изменение native поля
не вызывает пересчёт компонента. Перестановка host через `each_keyed` сохраняет
native input handles, focus/selection и aliases списка. `data_for` располагает
привязки строки глубже структурного view, чтобы сокращение массива удаляло строку
до вычисления её прежнего индекса. Это native список, не наш `each_keyed`.

Имена дочерних элементов становятся scoped classes и part-маркерами, не DOM ID.
Их можно повторять в строках и разных экземплярах компонента. Для доступа:

```dascript
let scope = ui_find("form")
let captain = ui_data_find(scope, "captain")
let second_row = ui_data_find(scope, "cargo_row", 1)
```

`ui_data_find` исключает скрытые шаблоны `data-for`, но может вернуть скрытый
`data_if` элемент. Возвращает 0 при отсутствии part/occurrence. Прямое назначение
`id`, `class`, `style`, `data-model` и part-маркера через `attribute`/`data_attribute`
запрещено: идентичность задаёт builder, стили — properties и scoped classes.
Unmount уничтожает native subtree, сохраняя публичную модель. Закрытие модели
отсоединяет привязки; существующая область остаётся безопасной для повторного
посещения. Новый mount требует живой модели.

## Создание и привязка

После `rui_init` или `rui_init_gl`, до загрузки RML:

```dascript
struct Person { name:string; ready:bool }

let model = ui_data_model("dispatch")
ui_data_bind(model, "person", Person(name="Ada", ready=false), true)
ui_data_bind(model, "status", "Waiting")
ui_data_on(model, "confirm")
let document = ui_load_rml("dispatch.rml")
```

Содержимое `dispatch.rml`:

```html
<rml>
  <head><link type="text/rcss" href="dispatch.rcss"/></head>
  <body data-model="dispatch">
    <input data-value="person.name"/>
    <input type="checkbox" data-checked="person.ready"/>
    <p>{{status}}</p>
    <button data-attr-disabled="!person.ready"
            data-event-click="confirm(person.name)">Confirm</button>
  </body>
</rml>
```

В цикле приложения, после передачи SDL-событий в `rui_event`:

```dascript
ui_data_events(model) $(event:UiDataEvent) {
    if (event.name == "confirm") {
        ui_data_set(model, "status", "Confirmed by {event.arguments[0].text}")
    }
}
rui_update()
rui_render()
```

`ui_load_rml` использует native `Context::LoadDocument`, сохраняет source URL для
относительных ресурсов и возвращает обычный document handle. Для строк остаётся
`rui_document`. Документу доступны `close_document`, `show_document`, остальные
операции над документами и штатные native views/controllers RmlUi.

## Значения и владение

`ui_data_bind(model, name, value, writable=false)` глубоко копирует значение в
native-хранилище моста. Поддерживаются строки, bool, целые, float/double, enum
(как целое), структуры и массивы этих типов. `uint64` ограничен диапазоном int64;
нечисловые и бесконечные float-значения отклоняются. Указатели и closures не
поддерживаются. GC daScript не влияет на существование привязанных значений.

`writable=true` разрешает native input-контроллерам и RML expressions менять
значения. Исходная daScript-структура при этом не изменяется. Для чтения native
значения используйте `ui_data_text`, `ui_data_int`, `ui_data_number`, `ui_data_bool`;
для длины массива — `ui_data_size`.

```dascript
ui_data_set(model, "person.name", "Grace")
let name = ui_data_text(model, "person.name")
ui_data_set(model, "cargo[0].crates", 12)
ui_data_set(model, "cargo", new_manifest)
```

`ui_data_set` доступен и для readonly bindings: флаг writable ограничивает native
контроллеры, а не приложение. Запись проверяет тип до замены и автоматически
помечает корневую переменную dirty. Вложенная запись `cargo[0].crates` помечает
`cargo`. Native `Context::Update` выполняет обновление views. В отличие от нашего
`each_keyed`, native `data-for` использует собственный алгоритм RmlUi.

Схема структуры и тип значения после привязки сохраняются. Тип элемента пустого
массива определяется при первом непустом значении и сохраняется после очистки.
`ui_data_dirty(model, "cargo")`, `ui_data_dirty_all` и `ui_data_is_dirty` доступны
для явной инвалидизации/диагностики; при обычном `ui_data_set` дополнительный dirty
не нужен. Dirty принимает только имя корневой переменной.

## События

`ui_data_on(model, "confirm")` регистрирует native `BindEventCallback`. Вызов из
RML expressions ставит событие в очередь модели; обработка daScript отложена до
`ui_data_events`. Имена регистрируются до загрузки документа.

`UiDataEvent` содержит `name` (имя callback), `kind` (например, `click`), `target`
(observer handle элемента) и `arguments`. Для scalar-аргументов доступны проекции
`.text`, `.integer`, `.number`, `.boolean` с преобразованиями RmlUi Variant.
Аргументы копируются в момент события; к моменту обработки target может быть
удалён, поэтому перед операциями с ним проверяйте `rui_alive(event.target)`.

Блок и его captures используются только во время вызова `ui_data_events` и не
сохраняются в C++. Обрабатывается очередь на начало вызова: события, созданные
обработчиком, остаются до следующего вызова. Рекурсивный drain той же модели
запрещён. При исключении текущее событие считается обработанным, остальные
сохраняются; следующий drain разрешён. Обработчик может закрыть свою модель.
Этот отложенный API не предназначен для синхронной отмены native события.

## Context, Debugger и lifetime

- `ui_data_exists(name)` и `ui_data_model_count()` смотрят модели текущего Context.
- `ui_data_debugger()` открывает штатный Debugger сразу на панели Data Models;
  повторный вызов оставляет её открытой. Структуры и массивы отражаются native API.
- Гибридная модель компонентов также зарегистрирована в Context под резервным
  именем `dasrmlui`. Debugger показывает её scalar slots `v0`, `v1`, …, а не всю
  daScript-структуру. Произвольные script-переменные туда не попадают.
- `ui_data_close(model)` удаляет модель, очереди и незавершённые записи, сначала
  отсоединяя native views/controllers. Живые документы остаются; для подключения
  новой модели с тем же именем документ следует загрузить заново.
- `ui_data_alive(model)` проверяет handle. Повторный close возвращает false;
  операции записи/чтения с устаревшим handle вызывают script exception.
- `ui_reset` удаляет гибридную модель, сохраняя внешние. `rui_shutdown` удаляет
  все модели до уничтожения Context. Handle не переиспользуется при restart.

Bridge обслуживает один Context. API не является полной копией C++ конструктора:
пользовательские синхронные `BindFunc` getters/setters и transform callbacks из
daScript пока не экспортированы. Встроенные transforms RmlUi доступны в RML.

## Пример и проверки

**Harbour / Cargo manifest**: `[ui_component]` + `native_data` и `[ui_style]`,
массив грузов, формы с вложенной структурой, native expressions, смена списка,
callbacks и кнопка инспектора. Весь пример находится в `.das`, без внешних RML/RCSS.

```powershell
./build/bin/dasrmlui.exe examples/data_models.das
ctest --test-dir build -R '^(native_data.*|data_models|demo_data_models|data_model_type_error)$' --output-on-failure
```

Тесты проверяют native bindings и формы, атомарный отказ записи неверного типа,
массивы после очистки, callbacks/исключения/GC, изоляцию моделей, reflection в
реальной панели Debugger, hybrid Context integration, remove и shutdown/restart.
`native_data_dsl` дополнительно проверяет scoped styles, экранирование, вложенные
списки, отсутствие component updates при native записи, соседние managed-элементы,
перестановку keyed-областей с сохранением input/focus/selection, смену модели и
unmount/remount. Отрицательные тесты проверяют границы владения и captures.
Runtime package запускает Harbour из установленной папки.
