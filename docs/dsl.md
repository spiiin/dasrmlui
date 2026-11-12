# Компоненты, состояние, формы и большие списки

Все конструкции ниже используют синтаксис daScript и AST-аннотации из
`dasrmlui/macros.das`. Отдельного парсера, `.rml` или `.rcss` не требуется.
Работающие приложения: `examples/catalog.das` и `examples/component_lab.das`.

## Media queries, темы, DPI и ninepatch

Пример `examples/style_lab.das` показывает две темы, масштаб 100/150%, native
адаптивную раскладку и растягиваемые рамки одного atlas. Все переключения сохраняют
handles и введённый текст.

```das
[ui_style]
def app_style() {
    spritesheet("examples/assets/style_atlas.png", 2.) {
        sprite("frame", 0, 0, 96, 96)
        sprite("frame_inner", 24, 24, 48, 48)
    }
    rule(part("panel")) { padding(dp(24)); ninepatch("frame", "frame_inner") }
    theme("night") { rule(part("panel")) { color(rgb(220,235,240)) } }
    theme("paper") { rule(part("panel")) { color(rgb(60,55,45)) } }
    media(media_max_width(dp(900))) {
        rule(part("layout")) { property("flex-direction", "column") }
    }
    media(media_and(media_theme("night"), media_min_resolution(1.5))) {
        rule(part("panel")) { padding(dp(28)) }
    }
}

// После создания context, например в обработчике кнопки:
set_theme("night")
set_ui_scale(1.5)
```

`media(query) { ... }` записывает native `@media`. Типизированные query helpers:
`media_min_width`, `media_max_width`, `media_min_height`, `media_max_height` принимают
`UiLength` (`px` или `dp`); `media_min_resolution` принимает отношение пикселей;
`media_orientation("portrait" | "landscape")` и `media_theme(name)` задают другие
условия. `media_and(a,b)` объединяет положительные условия; `media_not(query)`
отрицает весь запрос. Для остальных native условий есть строковый вариант,
например `media("(min-aspect-ratio: 4/3) and (max-resolution: 2x)")`.

Вложенные media/theme blocks запрещены: объединяйте условия через `media_and`.
Отрицание отдельного аргумента `media_and` тоже отвергается, чтобы не менять смысл
выражения при сериализации в native `not`. Синтаксис строкового запроса проверяет
RmlUi; это не отдельный CSS-парсер. Доступны только поддерживаемые RmlUi условия
и операции, без CSS `or` и сравнений вида `width <= ...`.

`theme(name) { ... }` — сокращение для media query по активной теме context.
`set_theme(name)` переключает одну выбранную палитру: деактивирует предыдущую,
активирует новую; `set_theme("")` снимает её. Независимые флаги вроде contrast
включаются через `activate_theme("contrast", true)` и выключаются через `false`.
Смена палитры не выключает другие независимые флаги. `ui_theme()` возвращает
выбранную палитру, `theme_active(name)` — фактическую активность native темы.
Темы общие для всех документов context, их имена не scoped.

`dp(value)` создаёт типизированную длину. `set_ui_scale(value)` задаёт положительный
конечный пользовательский множитель; `ui_scale()` возвращает его. Итоговый
`ui_dp_ratio()` равен SDL display scale × user scale. При инициализации bridge читает
display scale и реальные пиксельные размеры окна; при событии изменения display scale
сохраняет пользовательский множитель. `px` остаётся физическим пикселем, а размеры и
шрифты в `dp` масштабируются. Media queries с длинами в `dp` учитывают итоговый ratio;
`resolution` в RmlUi означает этот же ratio, а не разрешение экрана в пикселях.

Media/theme стили меняются в native RmlUi без пересоздания дерева и пересчёта обычных
компонентов. Прямые вызовы `ui_theme`, `theme_active`, `ui_dp_ratio`, `ui_scale` внутри
аннотации автоматически подписывают компонент на изменения среды; runtime будит
его и нужных предков. Для чтения, спрятанного в обычной helper-функции, добавьте
`watch_style_environment()` в компонент. Изменение размеров viewport по-прежнему
использует существующие зависимости `ui_width`/`ui_height`. `ui_reset` очищает DSL,
но оставляет настройки живого context; `rui_shutdown` сбрасывает и темы, и масштаб.

`spritesheet(source, resolution) { ... }` задаёт native resolution, по умолчанию 1.
Координаты `sprite` всегда в пикселях исходной картинки. Для atlas в 2x размеры
спрайтов и ninepatch-рамки при ratio=1 будут вдвое меньше исходных. Несколько sheets
в одном стиле получают разные имена; sheets можно объявлять внутри media blocks.

`ninepatch(outer, inner, paint_area="padding-box")` использует два scoped sprite
имени из одного atlas: внешний прямоугольник и внутреннюю растягиваемую область.
Углы сохраняют естественный размер, края растягиваются вдоль одной оси, центр — вдоль
двух. Вариант `ninepatch(outer, inner, dp(12), "border-box")` задаёт одинаковую толщину
всех краёв явно. Для разных толщин по сторонам остаётся native `property("decorator",...)`.
Размеры рамки не добавляют padding автоматически: отступы содержимого задаются отдельно.

Проверки: `style_environment` — темы, media, dp, начальный/изменённый DPI, selective
invalidation, focus/state и перезапуск context; `ninepatch_pixels` — реальные пиксели
четырёх углов и центра на двух панелях при 1x/2x и смене темы. Физическое перетаскивание
между мониторами с разным DPI отдельно не проверялось; смена ratio проверена программно.

## Анимации и отложенное удаление

`examples/animations.das` — меню Orbital с плавающим кораблём, выдвижной панелью,
уведомлениями и однократной анимацией запуска. Transform требует GL3 renderer.

```das
[ui_style]
def menu_style() {
    keyframes("enter") {
        keyframe(0.) { opacity(0.); property("transform", "translateX(40px)") }
        keyframe(100.) { opacity(1.); property("transform", "translateX(0px)") }
    }
    keyframes("leave") {
        keyframe(0.) { opacity(1.); property("transform", "translateX(0px)") }
        keyframe(100.) { opacity(0.); property("transform", "translateX(40px)") }
    }
    rule(part("inspector")) { opacity(1.); property("transform", "translateX(0px)") }
}

// Внутри [ui_component], после use_style(@@menu_style):
animated_when("inspector", model.open,
    motion("enter", 0.3), motion("leave", 0.25)) {
    inspector_content(model)
}
```

`keyframes` объявляются вне `rule`, внутри `[ui_style]`. Проценты возрастают от
`0.` до `100.`; оба крайних ключа обязательны. Типизированные style helpers и
`property` записывают свойства ключа. Имена scoped: `motion("enter", ...)` использует
текущий `use_style`; `animation_name("enter")` возвращает полное native имя.

`motion(name, seconds, easing="cubic-out", iterations=1, alternate=false)` — описание
анимации. `iterations=-1` задаёт бесконечный цикл. Внутри элемента:

```das
animate(motion("pulse", 1.2, "sine-in-out", -1, true), 0, model.ambient)

// Для конечной анимации: изменение revision запускает её заново.
animate(motion("launch", 0.4), model.launch_revision, model.launching)
on_animation_end() $(name:string) { model.launching=false; model.completed+=1 }
```

Это альтернативные примеры для разных элементов: на одном элементе работает
одна управляемая анимация. Не смешивайте `animate`, `animated_when` и прямое
присваивание `animation` на одном узле. `enabled=false` останавливает анимацию и
возвращает базовый стиль; повторное включение начинает её сначала. Это stop/replay,
а не pause/resume. Начальный ключ применяется до первого render, завершение или
отмена возвращают значения из stylesheet. Поэтому базовые значения анимируемых
свойств задавайте в `rule`, а не через inline property/binding на том же элементе.

RmlUi интерполирует свойства в `Update`; неизменившиеся компоненты и bindings не
пересчитываются каждый кадр. Runtime собирает native `animationend` всех свойств
в один `on_animation_end`, доставляемый через обычную очередь на следующем
`ui_frame`. Аргумент — полное scoped имя. Каждому запуску назначается generation:
завершение старого запуска не вызывается после replay/cancel. У бесконечной и
отменённой анимации completion нет. `on_transition_end` отдельно получает имя
свойства из native `transitionend`; `transition` задаётся обычным `property` в стиле.

`animated_when` создаёт дополнительный `div` с указанным именем. При `visible=false`
он удерживает DOM и дочернее локальное состояние до фактического завершения exit,
отключает ввод в поддереве и возвращает фокус внешнему элементу через `focus_scope`.
Затем вызывает обычный unmount до render. Если `visible` снова стал true, exit
отменяется, enter начинается с первого ключа, handles и состояние сохраняются.
Это не плавный разворот от текущего интерполированного значения. Exit должен иметь
ровно одну итерацию. Удаление родителя и `ui_reset` очищают поддерево сразу.

В keyed-списке оставляйте запись в модели на время exit и меняйте её `visible`.
Физическое удаление записи из массива сразу размонтирует компонент: автоматического
удержания удалённых элементов списка пока нет. Managed keyframes принимают native
числа/длины/углы, цвета, transform, keywords, decorator и filter. Box-shadow,
font-effect и ещё не разрешённые `var(...)`/shorthand placeholders в ключах отвергаются,
чтобы не ждать несуществующего completion. Прямые bindings `Element::Animate` и
`AddAnimationKey`, несколько параллельных клипов на узле и timeline пока не добавлены.

`tests/animations.das` использует управляемые часы и небольшие шаги native Update:
RmlUi ограничивает шаг интерполяции 0.1 секунды. Проверяются интерполяция при спящих
компонентах, группировка completion, устаревшее событие после replay, repeat/infinite,
stop, exit/unmount, фокус, сохранение состояния, GC и удаление родителя.

## Локальное состояние и жизненный цикл

```das
struct Counter { id:int; count:int }

[ui_component]
def counter(id:int) {
    state(Counter(id=id)) $(var local:Counter) {
        on_mount() { local.count = 10; request_focus("increment") }
        on_unmount() { print("Closed {local.id} at {local.count}\n") }
        column() {
            text("count", "{local.count}")
            button("increment", "+ 1") { on_click() { local.count += 1 } }
        }
    }
}
```

`state(initial)` получает блок с **явно типизированным mutable-аргументом**.
Инициализатор выполняется один раз. Макрос создаёт отдельное типизированное хранилище
`table<string;array<T>>`; ключ включает путь экземпляра компонента и место декларации.
Одноэлементный массив удерживает адрес значения при росте таблицы. В runtime не
сохраняется указатель на стек вызвавшей функции.

В `each_keyed` перестановка сохраняет локальное состояние. Удаление вызывает очистку;
последующее появление того же ключа создаёт новое состояние. Для долгоживущих данных
после удаления храните их в модели. Декларации `state` и `computed` должны находиться
на уровне компонента, до DOM-контейнеров, и быть безусловными. Это же правило действует
для hooks `on_mount`/`on_unmount`. В условии или списке
вызывайте дочерний компонент с собственной декларацией. Для нескольких одинаковых
компонентов с изменяемым порядком используйте `each_keyed`.

`on_mount` выполняется один раз **в месте декларации во время первого прохода**, до
завершения layout. Поэтому в нём можно инициализировать состояние; для фокуса служит
отложенный `request_focus`. Это не callback «после отрисовки». Не измеряйте в нём ещё
не созданные DOM-элементы.

`on_unmount` вызывается до удаления DOM, с последним значением локального состояния.
Дочерние компоненты очищаются раньше родителей, несколько hooks одного компонента —
в обратном порядке. Затем освобождается состояние. `ui_reset()` выполняет такую же
очистку; повторный reset ничего не вызывает. Нельзя создавать UI или вызывать reset
из teardown.

Cleanup становится отдельной именованной функцией, которая заново получает owned
state. В ней доступны глобальные значения и окружающие `state`/`computed`; borrowed
параметры исходной функции и временные локальные переменные не захватываются. Сохраните
нужный идентификатор в состоянии, как `local.id` выше. В состоянии храните значения,
которые действительно принадлежат компоненту, а не указатели на временные массивы.

## Computed, слоты и события

```das
[ui_component]
def panel(title:string; changed:block<(delta:int):void>; content:block) {
    column() {
        text("title",title)
        slot(content)
        button("add","Add") { on_click() { emit(changed,1) } }
    }
}

[ui_component]
def screen(var model:Model) {
    computed(expensive(model.amount)) $(total:int) {
        panel("Total: {total}", $(delta:int) { model.amount += delta }) {
            text("caption",model.caption)
        }
    }
}
```

`computed` кеширует результат по прочитанным полям, здесь `model.amount`. Изменение
`model.caption` не вызывает `expensive`. Поддержаны владеющие результаты, включая
массивы; они освобождаются вместе с компонентом. Тип результата задаётся аргументом
блока. Getter должен быть чистым. Для скрытых внешних зависимостей передавайте
revision/значение явно либо используйте `ui_watch` и `ui_touch`.

`slot` синхронно вызывает блок содержимого, `emit` — типизированное событие компонента.
Есть `emit(event)` без payload и `emit(event,value)` с payload. Ни один из этих блоков
не сохраняется между кадрами. Компонент с callable-параметром консервативно обходится
при посещении родителем: сравнивать адрес borrowed-замыкания небезопасно. Если родитель
пропущен, дочерние слоты также не выполняются. Внутренние bindings и computed сохраняют
свои отдельные проверки зависимостей.

## Поля и валидация

```das
text_input("units") {
    bind_int(model.units,0,10000,"Enter") $(value:int) { model.units=value }
}
text("error") { return field_error("units") }

text_input("price") {
    bind_float(model.price,0.0,10000.0,"blur") $(value:float) { model.price=value }
}
text_input("name") {
    bind_edit(model.name,"change",$(value:string):string {
        return length(value) < 3 ? "At least 3 characters" : ""
    }) $(value:string) { model.name=value }
}
checkbox("enabled") {
    bind_checked(model.enabled) $(value:bool) { model.enabled=value }
}
select_input("collection") {
    select_options(choices)
    bind_value(model.collection) $(value:string) { model.collection=value }
}
```

`choices` имеет тип `array<UiOption>`, например
`UiOption(value="audio",caption="Audio")`. Подписи экранируются как текст.
Список опций перестраивается только при изменении содержимого. Значение модели
должно соответствовать существующей опции. `checkbox` создаётся сразу с правильным
типом input, а не меняет тип уже созданного текстового поля.

У `bind_int`, `bind_float`, `bind_edit` есть черновик ввода. Строки `-`, `12xyz`,
переполнение и выход за диапазон не меняют модель и не превращаются в ноль. Черновик
остаётся в поле для исправления, `field_error` возвращает сообщение, элемент получает
псевдокласс `:invalid`. `bind_float` отвергает NaN и бесконечность при конечных границах.
У `bind_edit` validator возвращает пустую строку для допустимого значения.

Режим `change` применяет допустимые изменения сразу; `Enter` ждёт Enter; `blur` —
ухода фокуса. Escape сбрасывает черновик к модели. Внешнее изменение значения модели
заменяет черновик. `field_pending(name[,key])` сообщает о неприменённом вводе; например,
в Catalog Save недоступен, пока количество не подтверждено Enter. `field_error` и
`field_pending` ищут поле внутри текущего компонента; вне рендера — во всём дереве.
Для повторяющихся полей передавайте ключ. Имена полей внутри области должны различаться.

Простой `bind_value` сохраняет прежнее поведение: setter может отклонить/нормализовать
строку, и следующий проход возвращает значение модели. Он не удерживает ошибочный
черновик. Programmatic updates checkbox/select подавляют события, чтобы не создавать
петлю model → DOM → model. Черновики удаляются вместе с DOM-узлами.

## Виртуализация

```das
virtual_each("assets",items,54.0,420.0,$(item:Asset) => item.id) $(item:Asset) {
    asset_row(item)
}
```

Параметры: имя, массив, высота строки, высота viewport, функция уникального `int`-ключа,
блок строки. Необязательный последний аргумент `overscan` по умолчанию равен 2.
Высоты задаются в пикселях и должны быть положительными. На данный момент это
**фиксированная высота**, без измерения переменных строк.

Runtime создаёт scroll-контейнер, верхний и нижний spacer и только видимые строки с
запасом. Обёртка строки имеет фиксированную высоту и скрывает переполнение: содержимое
должно в неё помещаться. При прокрутке просыпается владелец списка и его предки.
При уменьшении массива scroll offset ограничивается новой длиной. Для программного
перехода: `rui_scroll_to(ui_find("assets"),offset)`.

Копируется только видимый срез, чтобы setter мог безопасно менять источник во время
события. Все ключи проверяются на дубликаты: стоимость обновления списка включает
**O(N) проверку ключей**, создание/обновление DOM — O(видимых строк). На спокойном кадре
список не обходится, если компонент пропущен. Передача огромного массива как аргумента
корневого компонента всё ещё требует снимка этого аргумента. В Catalog корень получает
небольшие query/selection/revision, а фильтр кеширует массив в `computed`.

Ушедшая за overscan строка размонтируется. Возврат создаёт новый компонент. Долговечное
редактируемое состояние строки храните в модели по ключу; локальное состояние
компонента предназначено для текущего смонтированного экземпляра.

## Фокус и размер окна

```das
on_mount() { request_focus("name") }
focus_scope("editor") {
    text_input("name") { on_submit() { save() } }
    button("cancel","Cancel") { on_click() { close() } }
}
flow("workspace",900.0) {
    list_panel()
    details_panel()
}
```

`request_focus(name[,key])` применяется после reconciliation и layout. Поиск ограничен
экземпляром компонента, из которого сделан запрос; внешний вызов ищет глобально.
`focus_scope` циклически переводит Tab/Shift+Tab между видимыми доступными элементами
области. При удалении области, в которой находился фокус, восстанавливает прежний
фокус, если элемент ещё жив. Вложенные области восстанавливаются корректно и при
одновременном удалении всего внешнего поддерева.
Это область клавиатурного фокуса; для модального окна отдельно создайте перекрывающий
фон, как в Catalog. Скрытые и disabled элементы пропускаются. Кнопки поддерживают
клавиатурную активацию через стандартное поведение RmlUi.

`on_key("Enter"/"Escape"/"Tab"/"Up"/"Down"/"Space") { ... }` получает именованную
клавишу; `on_submit` — сокращение для Enter. Событие получает ближайший подписанный
элемент. Tab внутри focus_scope обрабатывается навигацией до обычной доставки.
Для остальных key codes доступен нативный SDL-цикл; этот helper не является полным
менеджером глобальных сочетаний клавиш.

`flow(name,breakpoint)` переключает направление flex row/column, сохраняя узлы.
`ui_width()` и `ui_height()` возвращают размеры RmlUi context в пикселях. Resize
инвалидирует компоненты, а чтение размеров внутри binding учитывается в его зависимостях.
Обычные `pct`, flex-свойства и `property` остаются доступны. Стили `[ui_style]` статичны;
вычисляемые размеры задавайте внутри компонента. Длинная страница прокручивается.

## Диагностика

`[ui_component(dump=true)]` печатает реальные AST трёх сгенерированных функций при
компиляции. Пример — `tests/macros_probe.das`.

```das
ui_trace(true)
ui_frame() { screen(model) }
for (i in range(ui_trace_count())) {
    let entry=ui_trace_at(i)
    print("{entry.owner} / {entry.site}: {entry.reason}\n")
}
```

Trace хранит последние 256 записей: mount, изменение аргументов/полей, явный сигнал,
непрозрачный getter, событие ввода. При включённой трассировке сохраняются именованные
снимки зависимостей, и причина перечисляет изменившиеся чтения, например `model.amount`
или `viewport.width`. Значения полей в журнал не выводятся. `ui_trace(false)` очищает
дополнительные снимки. `ui_stats()` возвращает счётчики компонентов, bindings и
computed; `ui_clear_stats()` обнуляет их. Непрозрачный getter — консервативный fallback,
а не доказательство полного отслеживания произвольных глобальных чтений.

Предупреждения и ошибки RmlUi печатаются в консоль с префиксом `rmlui warning:` или
`rmlui error:` — в том числе опечатки в `property(...)` и в правилах `[ui_style]`.
Для отклонённого inline-свойства следующей строкой выводятся тег и классы элемента.
То же значение повторно не применяется, поэтому сообщение одно, а не на каждый проход.
`rui_warning_count()` возвращает число таких сообщений с момента `rui_init`; в тестах
удобно проверять, что корректное дерево даёт ноль. Хосты примеров `run_demo` и
`run_gl_demo` делают это сами: smoke-прогон, в котором RmlUi выдал хотя бы одно
предупреждение, завершается ошибкой. Саму эту проверку сторожит отрицательный тест
`smoke_warning_error`.

## Имена примитивов и частей

Аннотация распознаёт примитивы DSL по имени, но только в позиции оператора. Вызов,
использованный как значение (`let h = height(item)`, аргумент, операнд), остаётся
обычным пользовательским кодом, даже если его имя совпадает с `height`, `color`,
`text` и подобными. Собственную функцию с таким именем, вызываемую как оператор,
уточняйте модулем: `_::height(item)`.

Имя части может быть выражением: `box(model.wide ? "wide" : "narrow") { ... }`.
Элемент остаётся тем же, меняется его scoped-класс, и `ui_find` видит новое имя.
Это работает для контейнеров и для `text`, `tab_label`, `sprite_image`, `progress_bar`.

`button("name") { ... }` без подписи создаёт кнопку, содержимое которой целиком задаёт
тело, например иконку. У кнопки с подписью дочерние элементы идут после текста и
сохраняются при смене подписи.

## Условные свойства, порядок стилей и блоки

Свойство применяется, когда выполнение доходит до его вызова, в том числе под `if` или
`when` на уже существующем контейнере. Оно не снимается, когда условие становится
ложным: задавайте обе ветви либо значение выражением.

```das
box("panel") {
    if (model.wide) { width(px(300)) } else { width(px(120)) }
    property("border-color", model.error ? "#b3261e" : "#5f6b7a")
}
```

Таблицы `[ui_style]` попадают в общий CSS в порядке первого использования. При равной
специфичности побеждает правило из таблицы, использованной позже. Это важно только для
глобальных селекторов (`rule("progress")`, `rule("input")`): классы `part(...)` у разных
таблиц разные и между собой не конфликтуют.

`box` — блочный элемент (`display: block`) при любом родителе; `row` и `column` — flex.
Чтобы получить строчный `box`, задайте `property("display","inline")`.

`on_key("Enter")` и `on_submit` срабатывают и от Enter на цифровой клавиатуре. Клавиши,
у которых нет имени в `on_key`, в очередь DSL не попадают и компоненты не будят.

В GL-режиме `rui_render` сам очищает кадр. `rui_gl_clear(false)` отключает очистку:
приложение рисует свою сцену, а интерфейс накладывается поверх неё.

## Базовый шрифт

```das
verify(rui_font("assets/Inter-Regular.ttf"))
set_base_text("Inter", px(15), rgb(30,34,40))
```

`set_base_text(family, size, color)` задаёт текст по умолчанию для всех документов:
семейство, размер и цвет. Размер и цвет необязательны и равны `px(16)` и
`rgb(232,237,246)`. Без вызова используется `LatoLatin` — семейство шрифта, который
загружает `rui_default_font()`. `base_font_family()` возвращает текущее семейство.

Сам файл шрифта этот вызов не загружает: сначала `rui_font(path)`, затем имя семейства.
Если семейство не загружено, RmlUi сообщит об этом предупреждением. Вызывайте
`set_base_text` один раз при запуске: главный документ и документы, открытые позже,
получают новые значения, а уже открытый документ-шаблон сохраняет те, с которыми был
загружен. Правило `rule("body")` в `[ui_style]` по-прежнему перекрывает эти значения.

Файл для `rui_default_font()` хост ищет рядом с exe (`assets/LatoLatin-Regular.ttf`),
подробнее — в README, раздел «Где exe ищет скрипты и шрифт». Если файл не найден,
функция возвращает `false`.

## Классы по состоянию и произвольные теги

```das
[ui_style]
def card_style() {
    rule(part("card")) { background(rgb(30,40,56)); property("transition","background-color 0.2s") }
    part("card") |> with_class("selected") |> rule() { background(rgb(65,117,183)) }
    part("card") |> with_pseudo("flagged") |> rule() { property("border","2px #d9a441") }
    part("field") |> with_pseudo("focus") |> rule() { property("border-color","#6aa7ff") }
}

// Внутри [ui_component], после use_style(@@card_style):
box("card") {
    class_if("selected", model.selected == item.id)
    pseudo_if("flagged", item.flagged)
}
```

`class_if(name, condition)` включает и выключает класс текущего контейнера,
`pseudo_if(name, condition)` — псевдокласс. Условие — обычная зависимость привязки:
пока прочитанные значения не изменились, оно не вычисляется заново. Класс получает
префикс текущей таблицы стилей, поэтому выбирается через `with_class(selector, name)`,
а не строкой `.selected`. `with_pseudo(selector, name)` добавляет `:name` и годится также
для состояний самого RmlUi: `focus`, `active`, `checked`.

Отличие от свойства существенное. Inline-свойство (`background(...)` с выражением)
меняется мгновенно: RmlUi запускает `transition` только при смене класса или
псевдокласса. Поэтому состояние, которое должно меняться плавно, задавайте классом, а
оба вида оформления описывайте в `[ui_style]`.

Для `pseudo_if` выбирайте собственные имена: `hover`, `active`, `focus`, `checked` и
`disabled` RmlUi выставляет сам и перезапишет ваше значение. В `[ui_template]` доступен
`class_if` с постоянным условием; `pseudo_if` там отклоняется, шаблон статичен.

```das
box("avatar") { element("photo","img") { attribute("src","assets/avatar.png") } }
element("name_label","label") { attribute("for","name_field"); text("caption","Имя") }
text_input("name") { attribute("id","name_field") }
```

`element(name, tag)` создаёт элемент с любым тегом RmlUi; порядок аргументов тот же,
что у остальных примитивов — сначала имя части. Тело необязательно. Так доступны
`img` с `src`, `label`, `form`, `p` и другие теги, у которых нет собственного helper'а.
Нативное поведение сохраняется: `img` берёт размер файла, клик по `label` передаёт
фокус полю из атрибута `for`. У RmlUi нет встроенной таблицы стилей, поэтому такой
элемент строчный, пока правило не задаст `display`; внутри `row` и `column` он, как и
любой flex-элемент, ведёт себя как блок. Тег места вызова не должен меняться между
проходами. Обе конструкции работают и в `[ui_template]`.

## Типизированные свойства

```das
rule(part("card")) {
    padding(px(12)); margin_x(dp(8)); min_width(px(180)); max_width(pct(60))
    border(px(1), rgb(54,116,84)); border_radius(px(6))
    background(rgb(20,28,40), 0.85)
}
rule(part("badge")) { position("absolute"); top(px(-6)); right(px(-6)); z_index(2) }
```

Каждый helper только записывает одно объявление через `property`, поэтому работает
везде, где работает `property`: в `rule`, `keyframe`, `[ui_template]` и в теле
компонента. Внутри компонента вызов helper'а — привязка с зависимостями, как у `width`.

| Группа | Helper'ы | Аргументы |
|---|---|---|
| Единицы | `px`, `dp`, `pct`, `em`, `rem`, `vw`, `vh` | число → `UiLength` |
| Размеры | `width`, `height`, `min_width`, `min_height`, `max_width`, `max_height` | `UiLength` |
| Внешние отступы | `margin`, `margin_top`, `margin_bottom`, `margin_left`, `margin_right`, `margin_x`, `margin_y` | `UiLength` |
| Внутренние отступы | `padding`, `padding_top`, `padding_bottom`, `padding_left`, `padding_right`, `padding_x`, `padding_y` | `UiLength` |
| Рамка | `border`, `border_top`, `border_right`, `border_bottom`, `border_left` | толщина, цвет, альфа |
| | `border_width`, `border_radius` | `UiLength` |
| | `border_color` | цвет, альфа |
| Цвет | `background`, `color` | цвет, альфа |
| Позиция | `position` | `static`, `relative`, `absolute`, `fixed` |
| | `left`, `top`, `right`, `bottom` | `UiLength` |
| | `z_index` | `int` |
| Раскладка | `display` | значение `display` из RCSS |
| | `gap` | `UiLength` |
| | `flex_grow`, `flex_shrink` | `float` |
| Текст | `font_size`, `letter_spacing` | `UiLength` |
| Прочее | `opacity` | `float` |

Альфа необязательна и задаётся от 0 до 1, как в остальных цветовых функциях DSL.
`margin_x` и `padding_x` записывают левую и правую стороны, `_y` — верхнюю и нижнюю.

Что даёт типизация. Длина и цвет — разные типы, поэтому `border_radius(rgb(1,2,3))` не
компилируется. `position` и `display` принимают строку и сверяют её со значениями,
которые понимает RmlUi: опечатка останавливает программу с понятным сообщением при
первом использовании таблицы стилей, а не превращается в предупреждение разборщика.

Имена этих helper'ов, как и остальных примитивов, аннотация `[ui_component]` узнаёт по
вызову-оператору. Собственную функцию с именем `left`, `top`, `position`, `display`,
`margin`, `border` или `gap`, вызываемую как оператор внутри компонента, пишите с
модулем: `_::display(text)`. Вызов, использованный как значение, не затрагивается.

`transform`, `transition`, `box-shadow`, `font-effect`, `decorator` и `filter` остаются
строками: у них составной синтаксис, и helper'а для них пока нет.

## Границы текущей реализации

DSL покрывает перечисленные структурные конструкции, формы, стили и композицию,
но не каждую возможность RmlUi. Нет автоматического вывода зависимостей через тела
произвольных вызываемых функций, переменной высоты виртуальных строк,
универсального менеджера shortcuts или hot reload с миграцией state. Для drag-and-drop
есть `draggable`/`on_drop` и проверенный пример `examples/drag_drop.das`. Backend
SDL_Renderer не реализует полный набор renderer extensions RmlUi; отдельный GL3
путь используется в `examples/effects.das`.

Актуальные различия между native возможностями, bindings, DSL и примерами:
[матрица покрытия RmlUi](rmlui-coverage.md).

## Native документы и шаблоны

`[ui_template]` описывает native template обычными вызовами daScript. Ручные RML/RCSS
строки не нужны. Стили задаются через `[ui_style]` или привычные `width`, `padding`,
`property` внутри узла шаблона.

```das
[ui_style]
def frame_style() {
    rule(root()) {
        property("position", "absolute")
        width(px(430))
        height(px(390))
    }
    rule(part("move")) { height(px(42)); padding(px(12)) }
    rule(part("mission_actions")) { padding(px(12)) }
    rule(part("field_notes")) { padding(px(22)) }
    rule(part("crew_status")) { padding(px(12)) }
    rule(part("resize")) {
        property("position", "absolute")
        property("right", "2px"); property("bottom", "2px")
        width(px(28)); height(px(28))
    }
}

[ui_template]
def tool_window() {
    use_style(@@frame_style)
    window_frame("window") {
        move_handle("move") { title_slot("title") }
        slot("mission_actions")
        slot("field_notes")
        slot("crew_status")
        resize_handle("resize")
    }
}
```

Функция шаблона не принимает параметров; статическое описание кешируется.
`open_template(@@tool_window, title, float2(x,y))` создаёт отдельный документ,
задаёт положение и заполняет `title_slot` безопасным текстом. Закрытие документа
и динамическое содержимое остаются в `[ui_component]`:

```das
state(WindowLife()) $(var local:WindowLife) {
    on_mount() { local.document = open_template(@@tool_window, "Inspector", float2(50.,210.)) }
    on_unmount() { rui_close_document(local.document) }
    document_content(local.document, "mission_actions") { actions(model) }
    document_content(local.document, "field_notes") { notes_editor(model) }
    document_content(local.document, "crew_status") { crew_status(model) }
}
```

`slot(name)` принимает выбранное приложением имя: `mission_actions`, `field_notes`
и `crew_status` — примеры, а не встроенные типы слотов. Имя можно вычислить обычным
кодом daScript при построении статического определения. Слот становится пустым `div`
с document-local ID и scoped style class; оформить его можно через `part(name)` или
`slot(name) { padding(...); property(...); attribute(...); }`.

Главного слота нет. Прежний `content_slot` удалён без совместимого alias: замените
вызовы на `slot` с тем же именем. Native `<template>` генерируется без атрибута
`content`; DSL сам направляет каждый компонент в объявленный слот.

Текущие правила DSL:

- Один `window_frame` обязателен. Именованных слотов может быть ноль, один или много;
  заполнять каждый из них необязательно. Незаполненный слот остаётся пустым элементом.
- `title_slot` необязателен; допускается не более одного.
- `move_handle`/`resize_handle` генерируют native `<handle>` с target `#document`.
- `row`, `column`, `box`, `text` внутри аннотации описывают статическую рамку.
  Их имена становятся document-local ID и scoped style classes. Имена не должны
  повторяться в одном шаблоне; одинаковые имена разных экземпляров допустимы.
- Имена слотов непустые и не повторяют имена других узлов шаблона. Выбирайте имена,
  пригодные для ID и CSS-классов, например `quest_details`; `#` запрещён.
- У `slot`, `title_slot`, `resize_handle` есть варианты с блоком стилей.
  В блоке `slot` допустимы свойства и атрибуты, а не дочерние элементы;
  содержимое приложения помещайте в `document_content` внутри `[ui_component]`.
- Текст и значения `attribute` экранируются при сериализации. `attribute("id",...)`,
  `class`, `style`, `template`, `data-rui-slot` и `data-rui-template` зарезервированы:
  используйте имя узла и `property`.
- Состояние, `when`, keyed-списки, bindings и обработчики принадлежат компонентам.
  Аннотация диагностирует эти конструкции в статическом шаблоне. `return` внутри
  описания не поддерживается; вычисления можно вынести в обычные helper-функции.

Макрос перенаправляет вызовы контейнеров в builder и оборачивает описание кешем.
Builder создаёт native `<template>`, RCSS-ресурс и параметры корневого документа;
`open_template` регистрирует ресурсы в памяти и подключает native template через
`<link type="text/template">`. RmlUi разбирает результат своим штатным парсером.
Отдельного парсера DSL нет. `template_markup(@@tool_window)` возвращает сгенерированный
native template для инспекции; RCSS подключён из отдельного in-memory ресурса.
При вызове сохраняется текущая область стилей вызывающего компонента.

`ui_reset` очищает кеш builder, а `open_template` повторно регистрирует ресурсы для
нового context. Определения статичны: это не hot reload, и изменение глобальных
значений внутри шаблона не является способом обновить уже загруженный native cache.
Для изменяемых данных используйте компоненты.

`document_content(document, name)` направляет создание узлов в объявленный слот.
Опечатка в имени и попытка заполнить обычный статический узел вместо слота вызывают
ошибку с именем target. Слот не является компонентом и сам не хранит состояние:
вставленные компоненты используют обычные bindings, `state`, `when` и `each_keyed`.
Если убрать вызов `document_content` условием, дочерние компоненты проходят unmount,
а пустой контейнер слота остаётся в рамке. Другие слоты и документы не меняются.

Шаблон владеет рамкой и target, runtime — вставленными детьми. ID документа и handle
слота входят в путь идентичности. Смена `name` у того же вызова размонтирует старое
поддерево и создаст новое в другом слоте; локальное состояние не переносится.
При обычном обновлении содержимого того же слота handles и локальный state сохраняются.
Stylesheets DSL применяются к документам вместе с исходными
стилями шаблона; более специфичные template rules могут переопределять общую базу.
Не удаляйте target вручную, пока компонент смонтирован. Закрытие документа делайте
в `on_unmount`; остальные уже закрытые handles становятся недействительными.

`examples/templates.das` показывает `[ui_template]` без RML-строк, два экземпляра,
три именованных слота с отдельными компонентами, условное удаление редактора,
native `move_target`/`size_target`, редактирование и закрытие/повторное открытие.
Модель переживает закрытие окна; локальный state создаётся заново.

Низкоуровневые `rui_resource` и `rui_document` сохранены для существующих RML-шаблонов
и интеграций, которым нужна прямая загрузка разметки. RmlUi раскладывает документ уже
во время загрузки, а стили DSL присоединяются после неё, поэтому такая разметка должна
сама задавать `font-family`: иначе первый layout пройдёт без шрифта и RmlUi сообщит
«No font face defined». Шаблоны из `[ui_template]` несут базовый шрифт в собственном CSS. Для документов, созданных
напрямую через `rui_document`, `document_content` по-прежнему принимает произвольный
существующий ID: проверка объявления слота относится к документам из `open_template`.
Существующий `slot(block)` для композиции компонентов остаётся отдельной перегрузкой.

## Перевод текста

```das
rui_translation("en", "hello", "Hello")
rui_translation("ru", "hello", "Привет")
// В компоненте:
text("greeting", tr("hello"))
// В обработчике или до ui_frame:
set_locale("ru")
```

`tr` вызывает установленный `SystemInterface::TranslateString`. Нативный парсер
также переводит `[hello]` при загрузке RML. Для отсутствующего перевода используется
английский каталог; неизвестный ключ остаётся `[key]`. Замены токенов однопроходные.
Каталоги и строки копируются в native storage; script callbacks не сохраняются.

Изменение языка/каталога увеличивает revision. Компоненты видят revision в снимке
входов, а прямые `tr(...)`/`ui_locale()` в bindings получают зависимость от него.
Поэтому текст обновляется без remount и изменения input handles. Если helper
скрывает вызов `tr`, явно передайте `ui_locale()` в аргументы helper, как в
`sample_phrase` примера. Автоматического межпроцедурного анализа нет.

Уже распарсенный текст native RML не переводится повторно автоматически: для
живой смены языка используйте `tr` в DSL. `tr` в `text` создаёт обычный безопасный
текст, а не интерпретирует перевод как RML. Сам native RML parser может разбирать
разметку из доверенного каталога согласно поведению RmlUi.

Plural rules и подстановка `%name%` показаны на daScript для en/de/ru; это не ICU.
`rui_font` загружает основное начертание, `rui_fallback_font` — fallback face.
HarfBuzz/RTL и CJK-сценарии этим примером не заявлены.

## Drag-and-drop и прогресс

`draggable(payload)` включает native `drag: clone`; `on_drop() $(payload:string)`
получает копию payload ближайшего подписанного элемента. Обработчик меняет модель,
после чего keyed reconciliation обновляет DOM. Исходный native pointer не хранится.
Клон имеет `:drag`, drop target — `:drop`. Обработчик отвечает за валидацию payload
и ограничений; сброс вне target не меняет модель. Полный набор drag lifecycle
callbacks доступны через `on_event("dragstart"/"dragend"/"dragdrop", ...)`;
`event.source` — безопасный handle источника, если native событие содержит
`drag_element`. Автоскролл drop-зон отдельно не реализован.

`progress_bar(name,value,maximum,direction)` создаёт настоящий `<progress>`.
`fill-image` принимает имя спрайта, `clockwise` включает радиальное раскрытие.
Для произвольной кривой `examples/progress_lab.das` измеряет длину сегментов пути
и обновляет их opacity с дробным последним сегментом. Скорость следует длине пути,
а не горизонтальной координате. Это композиция DSL, не новый native progress type.

## События элементов и документов

`on_event` работает внутри `[ui_component]` на текущем элементе, с любым native
именем события (включая custom events). Макрос добавляет уникальный site; runtime
создаёт native listener, кеширует его при пропуске компонента и удаляет при unmount
или исчезновении подписки. Несколько подписок одного типа допустимы. Старые
`on_click`, `on_key`, `bind_value` и `on_drop` продолжают работать отдельно и не
получают дубли из новых listeners.

```dascript
column("panel") {
    on_event("click", UiEventOptions(use_capture=true)) $(event:UiEvent) {
        print("target={event.target}, current={event.handle}, phase={event.phase}\n")
    }
    button("action", "Run") {
        on_event("click") $(event:UiEvent) { run_command() }
    }
}
document_events(editor_document) {
    on_event("keydown", UiEventOptions(key="S", modifiers=1, stop=true)) $(event:UiEvent) {
        save_draft()
    }
    on_event("hide") $(event:UiEvent) { print("Editor hidden\n") }
}
```

`UiEvent` — владеющая данными копия; native Event/Element pointers и daScript closures
не сохраняются. Для сохранения события с таблицей параметров используйте `saved := event`.

| Поле | Значение |
|---|---|
| `handle`, `target` | currentTarget и исходная цель; weak handles проверяются через `rui_alive` |
| `kind`, `value` | native имя и строковое значение параметра `value` |
| `phase` | 1 capture, 2 target, 4 bubble |
| `key_code`, `key` | Полный native KeyIdentifier; удобные имена A–Z, 0–9, F1–F24, Enter, Escape, Tab, Space, стрелки, Home/End/PageUp/PageDown/Insert/Delete/Backspace. Для остальных клавиш имя пустое, код сохраняется |
| `modifiers` | Ctrl=1, Shift=2, Alt=4, Meta=8, CapsLock=16, NumLock=32, ScrollLock=64; helpers `event_ctrl/shift/alt/meta` |
| `mouse`, `screen`, `button`, `wheel` | Native mouse_x/y (проекция для текущего элемента), исходные координаты context в пикселях, кнопка 0=левая/1=правая/2=средняя или -1, native wheel_delta_x/y |
| `interruptible` | Допускает ли RmlUi остановку этого события |
| `source` | Handle native drag_element или 0 |
| `parameters` | Таблица копий параметров: scalar, string, vector и colour в строковом представлении; `event_parameter(event,"text")`, `event_parameter(event,"reason")` и т. п. Native pointer/resource параметры не экспортируются |

`UiEventOptions`: `use_capture`, `stop`, `stop_immediate`, `key`, `modifiers`,
`enabled`. Пустой key не фильтрует клавишу. Modifiers=-1 принимает любую комбинацию,
0–15 требует точное сочетание Ctrl/Shift/Alt/Meta, игнорируя lock keys. `enabled=false`
снимает listener. Изменение параметров подписки аннулирует старые queued snapshots;
при неизменных типе/фазе порядок listeners на одном узле сохраняется.

Доставка обработчиков отложена до `ui_frame`, в порядке native dispatch. После каждого
обработчика выполняется reconciliation; следующие команды заново проверяют подписку,
цель, disabled, visibility и modal focus. Поэтому удалённая цель, закрытое окно или
фон нового modal не получают уже поставленные в очередь команды ввода. При доставке
события родительские listeners не подменяют `target` своим `handle`.

**Остановка применяется синхронно по параметрам подписки**, до native default action.
В RmlUi StopPropagation также отменяет default actions; независимого PreventDefault
в этой версии нет. `stop` оставляет другие listeners того же узла, `stop_immediate`
останавливает и их. Неотменяемые события (например change) это игнорируют.
Из отложенного блока нельзя задним числом отменить native событие. Изменение фокуса
в таком блоке также происходит при `ui_frame`, после уже обработанного native ввода.
Существующий `focus_scope` самостоятельно обрабатывает Tab/Shift+Tab.

Подписывайтесь после создания документа: уже прошедший `load` не воспроизводится.
После `close_document` snapshots удалённых handles отбрасываются; для освобождения
ресурсов используйте `on_unmount`, а не отложенный `unload`. `show`/`hide` сохраняют
native семантику: событие вызывается каждым соответствующим вызовом, даже если
видимость уже такая. Custom события от внешнего native кода доступны тем же API.
Это события RmlUi, не новая система browser PointerEvent/TouchEvent.

## Режимы документов, popup и редакторы

```dascript
// Обычно в on_mount; on_unmount должен вызвать close_document(document).
let document = open_template(@@editor_window, "Notes", float2(40.,250.),
    UiDocumentOptions(visible=false))

show_document(document, UiDocumentOptions(focus=UiDocumentFocus.Keep))
hide_document(document)       // DOM, handles и локальное состояние сохраняются
bring_to_front(document)
send_to_back(document)
position_document(document, float2(100.,200.))

show_document(dialog, UiDocumentOptions(modal=UiModal.Modal))
show_popup(menu, float2(300.,180.))
```

`UiDocumentOptions` имеет `visible=true`, `modal=UiModal.None`,
`focus=UiDocumentFocus.Auto`, `scroll=true`. `UiModal.Keep` сохраняет предыдущий modal
флаг. Focus None не меняет фокус; Document фокусирует документ; Keep возвращает его
последнему дочернему получателю; Auto ищет `autofocus`, иначе фокусирует документ.
Это native режимы: modal блокирует фон, пока документ владеет фокусом. Сочетание
Modal+Focus.None само по себе фокус не захватывает.

`open_template(..., visible=false)` создаёт скрытый документ без промежуточного Show
и кражи фокуса. Продолжайте вызывать `document_content` для скрытого редактора:
видимость не является unmount. Если убрать его компонент через `when`, состояние
будет уничтожено по обычным правилам DSL. `hide_document`/`close_document` возвращают
фокус сохранённому получателю, если фокус находился внутри скрываемого документа и
получатель ещё жив, видим и доступен. `document_visible`/`document_modal` — запросы
состояния; они не создают отдельную реактивную подписку.

Front/back меняют порядок внутри одной группы native z-index. Явный z-index нужен,
если полноэкранный основной документ не должен перекрывать вспомогательные окна
при получении фокуса. Управление несколькими SDL windows/context сюда не входит.

`show_popup` показывает документ с modal focus и Auto, поднимает его и ограничивает
положение границами viewport; после resize положение пересчитывается. Размер popup
задаёт шаблон: oversized окно не уменьшается автоматически. Popup можно открыть
поверх modal; после закрытия фокус возвращается в него. Верхний popup закрывается
по Escape и внешнему нажатию, включая поглощение соответствующего mouse-up, чтобы
клик не активировал фон. `document_events(menu)` + `on_event("dismiss")` получает
`reason="escape"` или `"outside"`. Обычный `hide_document` не генерирует dismiss.

Для меню используйте `attribute("autofocus","")` у начального пункта, native Enter/Tab
и `on_event("keydown", UiEventOptions(key="Down",stop=true))` с
`focus_next(menu)`; для Up — `focus_next(menu,true)`. Callback не переживает кадр.
Реальный пример — `examples/event_studio.das`: контекстное меню, Ctrl+S, журнал,
перемещаемый редактор с локальным черновиком, hide/show и modal подтверждение.
`tests/events.das` и `tests/documents.das` проверяют native input, lifetime и очереди.

## Native spatial navigation

DSL вызывает штатные RCSS `nav`, `nav-up/right/down/left` и `tab-index`. Поиск
соседа, переключение `:focus-visible`, прокрутку и Enter/Space выполняет сама RmlUi
во время native обработки клавиатуры. Обработчики `on_event("keydown", stop=true)`
по-прежнему могут отменить это стандартное действие.

```dascript
[ui_style]
def navigation_style() {
    rule(part("tile")) { nav(UiNav.Auto) }
    rule(part("tile")+":focus-visible") { background(rgb(90,110,65)) }
}

[ui_component]
def panel() {
    use_style(@@navigation_style)
    document_nav(rui_root())
    row() {
        button("tile", "First") {
            nav_id("first")
            nav_right(nav_to("last"))
        }
        button("tile", "Last") { nav_id("last"); nav_left(nav_to("first")) }
    }
    box("custom_control") { tab_stop(); nav(UiNav.Vertical); text("caption","Focusable") }
}
```

| Helper/режим | Native поведение |
|---|---|
| `nav()` / `nav(UiNav.Auto)` | Геометрический поиск по всем четырём направлениям |
| `UiNav.None` | Нет автоматического перехода |
| `UiNav.Horizontal` / `UiNav.Vertical` | Поиск только вдоль указанной оси |
| `UiNav.TreeOrder` | Следующий/предыдущий tabbable элемент в порядке DOM, без циклического возврата к корню |
| `nav_up/right/down/left(mode)` | Режим для отдельного направления |
| `nav_up/right/down/left(nav_to("id"))` | Явный переход к ID в текущем документе |
| `nav_id("id")` | Задать настоящий native ID текущего элемента |
| `tab_stop(true/false)` | `tab-index: auto/none` для обычного элемента |
| `document_nav(document, mode=UiNav.Auto)` | Навигация, когда фокус находится на самом документе |

Helpers стилей работают и в `[ui_template]`, и непосредственно в компоненте.
`nav_id`/`nav_to` принимают непустой ID без `#` и пробельных символов; префикс `#`
добавляется при генерации свойства. Имена document-local: они не превращаются в
scoped classes и не разрешаются через глобальный `ui_find`. Для повторяющихся
компонентов задавайте уникальные ID, например `nav_id("item_{item.id}")`.
Одинаковые ID в разных документах допустимы. Явный target должен существовать и
быть доступен для фокуса; DSL не создаёт его и не заменяет native правила проверки.

Nav-свойства не наследуются. Обычно `nav` задают каждому виду кнопок через
`[ui_style]`, а документу — `document_nav` или `nav()` внутри `window_frame`.
Без `autofocus`/`request_focus` начальный фокус может быть на документе; его native
`nav:auto` позволяет перейти к первому/последнему tabbable элементу.

`Auto` ограничивается ближайшим scroll container и пропускает скрытые/недоступные
для фокуса элементы. `TreeOrder` может переходить между scroll containers.
`focus_scope` по-прежнему ограничивает **Tab/Shift+Tab**, а не все варианты стрелок;
для native геометрической области задайте контейнеру `overflow: auto`.
Явные ID-переходы могут пересекать такие области внутри документа. Они не переходят
в другой документ; native modal/popup остаётся отдельной областью фокуса.
Текстовые поля сохраняют native обработку курсора; `nav(UiNav.None)` отключает их
участие как источника автоматических переходов стрелками, но не Tab.

`nav*` и `tab_stop` участвуют в обычной генерации mount/update и зависимостей
отдельных bindings. Движение фокуса не требует пересчёта компонентов; если нужны
изменения модели, подписывайтесь на `on_event("focus")`.
`tests/navigation.das` проверяет режимы, ID, disabled/hidden, scroll, Tab scope,
текстовый курсор, popup, активацию и отсутствие лишних обновлений. Геймпадная
обвязка SDL в этот native API не входит.

## Встроенный RmlUi Debugger

Подключён официальный `RmlUi::Debugger`; его DOM inspector, Event Log, Outlines и
Data Models работают в текущем RmlUi context. Интерфейс и встроенный шрифт принадлежат
плагину, отдельной реализации инспектора в DSL нет.

```dascript
// Обычно в on_mount приложения. Плагин загрузится при первом включении.
debugger_hotkey()           // F8; имя клавиши в формате SDL
debugger_hotkey("F9")       // сменить клавишу
debugger_hotkey("")         // отключить горячую клавишу

debugger_init()             // необязательная предварительная инициализация
debugger_show()             // показать панель; автоматически инициализирует
debugger_toggle()
debugger_show(false)
debugger_shutdown()         // освободить плагин и отключить горячую клавишу
```

По умолчанию плагин не загружен и горячая клавиша не назначена. Регистрация клавиши
не требует постоянного вызова из render. Нажатие и отпускание перехватываются до
очереди приложения; autorepeat не переключает панель многократно. Хоткей работает
также при фокусе в native документах инструментов и в popup.

`debugger_ready()` и `debugger_visible()` можно читать в компоненте: макрос
автоматически подписывает его на изменение состояния Debugger. Несвязанные
компоненты не инвалидируются. Это состояние панели инструментов, а не проверка
отдельного окна Element Info или Event Log.

В upstream `SetVisible(false)` скрывает только toolbar. Наш `debugger_show(false)`
также закрывает окна инструментов, выключает Outlines и прекращает picking. При
следующем показе появляется toolbar; нужный инструмент открывается его кнопкой.
Если фокус был в окне Debugger, он возвращается живому доступному элементу,
сохранённому при показе. Клик по Debugger поверх popup не считается внешним кликом
для закрытия popup. Первый picking-click перехватывает native инспектор; повторный
клик по уже выбранному элементу может пройти приложению по правилам RmlUi.

Документы Debugger не принадлежат component reconciliation и не получают stylesheets
DSL. `ui_reset` удаляет прикладные узлы, но не выключает отдельно запущенный плагин;
для component-owned lifetime вызовите `debugger_shutdown()` в `on_unmount`.
При `rui_shutdown` плагин освобождает сама RmlUi. Инициализация идемпотентна;
проверены явный restart и создание нового context после полного shutdown.

Data Models показывает только **native RmlUi data models**, а не произвольные
переменные daScript или состояние наших компонентов. Для DSL остаются `ui_stats`
и `ui_trace`. Выбрать другой context пока нельзя: bridge обслуживает один context.

Пример: `examples/navigation_lab.das` (Vector deck). Стрелки/Enter управляют плитками
и popup; F8 открывает штатный Debugger. Element Info позволяет выбрать элемент и
увидеть native ID, scoped classes, RCSS и геометрию. `tests/debugger.das` проверяет
picking, отсутствие лишних callbacks, удаление выбранного элемента, изоляцию стилей,
возврат фокуса, hide/shutdown, GC и повторную инициализацию.

## SVG и Lottie

Официальные плагины RmlUi включены в сборку. Элементы работают в `[ui_component]`
и статическом `[ui_template]`, стили задаются через `[ui_style]` или родительский
контейнер. Это native элементы `<svg>` и `<lottie>`; отдельного проигрывателя DSL нет.

```das
[ui_style]
def vector_style() {
    rule(part("icon")) { width(px(160)); height(px(120)); image_color(rgb(255,255,255)) }
    rule(part("motion")) { width(px(240)); height(px(240)) }
    rule(part("seal")) { width(px(80)); height(px(60)); svg_decorator("examples/assets/vector_orbit.svg",true) }
}
[ui_component]
def vector_view(var model:Model) {
    use_style(@@vector_style)
    svg_image("icon",model.svg_path,model.crop)
    svg_inline("badge",model.svg_fragment,float2(100.,100.))
    lottie("motion",model.animation_path)
    box("seal") {}
}
```

- `svg_image(name, source, crop=false)` загружает SVG через FileInterface RmlUi.
  `crop=true` задаёт `crop-to-content`: прозрачные поля убираются при растеризации;
  intrinsic-размер самого SVG остаётся исходным.
- `svg_inline(name, fragment, viewport:float2, crop=false)` принимает SVG XML
  **без внешнего `<svg>`**. DSL задаёт namespace, width/height и `viewBox="0 0 w h"`.
  Размеры должны быть конечными и положительными. SVG-пути внутри fragment не являются
  DOM-элементами RmlUi и не получают отдельные UI-события. Можно собирать fragment
  функцией daScript; API не вводит отдельный парсер или язык рисования.
- `lottie(name, source)` загружает Lottie JSON. В текущем плагине воспроизведение
  автоматическое, циклическое, по времени RmlUi; pause/seek/speed API отсутствует.
  `when` удаляет и заново создаёт элемент; remount и смена источника запускают новую
  анимацию. Простое скрытие элемента не означает паузу.
- `svg_decorator(source, crop=false, paint_area="padding-box")` задаёт native
  SVG-декоратор. Допустимы `padding-box`, `border-box`, `content-box`. В путях используйте
  `/`; кавычки и переносы строк запрещены. Декоратор растягивается на область элемента.
- `image_color(rgb(...))` и `opacity(...)` модулируют изображение SVG/Lottie.
  Для изменения пропорций/размеров используйте обычные RCSS width/height. DPI учитывает
  native плагин; при изменении размеров он создаёт текстуру подходящего разрешения.

Source, fragment, viewport и crop отслеживаются **на уровне привязки**. Неизменившийся
компонент не пересчитывается ради кадров Lottie — host продолжает вызывать
`rui_update`/`rui_render`. При замене содержимого файла по прежнему пути native кеш
не обязан перечитать его: это не hot reload. Используйте новый путь ресурса.
`rui_resource(path, data)` позволяет зарегистрировать SVG/JSON в памяти и передать
его путь тем же функциям. Relative paths разрешаются относительно документа.

Сборка загружает закреплённые LunaSVG 3.2.1 (с PlutoVG) и rlottie; см.
[зависимости](vector-dependencies.md). Поддерживаемый SVG/Lottie subset определяется
этими библиотеками; произвольный экспорт After Effects не гарантируется.
Пример `examples/vector_lab.das` использует GL3; функциональные тесты работают с SDL
dummy, пиксельные тесты SVG и анимации — с настоящим SDL renderer.

## Пользовательские native-элементы

`register_native_element` регистрирует настоящий `Rml::ElementInstancer`. Native
подкласс `Rml::Element` вызывает обработчик daScript из своих виртуальных методов,
а `native_element` создаёт его через Factory в компоненте или шаблоне.
Регистрация выполняется **после `rui_init`/`rui_init_gl` и до создания элементов**.

```das
def meter(event:UiNativeEvent) {
    if (event.kind==UiNativeKind.Paint) {
        native_rect(event.element,float4(0.,0.,event.size.x,event.size.y),rgb(30,50,40))
        native_line(event.element,float2(10.,10.),event.size-float2(10.,10.),3.,rgb(240,190,70))
    }
}
// В startup, после инициализации RmlUi:
// register_native_element("app-meter",@@meter,float2(200.,80.))

[ui_component]
def meter_view(var model:Model) {
    native_element("meter","app-meter") {
        width(px(300)); height(px(100))
        attribute("value","{model.value}")
        on_click() { model.value+=1 }
    }
}
```

Сигнатура: `register_native_element(tag, handler, intrinsic=float2(0.), continuous=false)`.
Handler — обычная функция `@@name` или owning lambda `@(event:UiNativeEvent) { ... }`.
Имя должно начинаться с латинской строчной буквы, содержать дефис и состоять из
`a-z`, `0-9`, `-`. Встроенные типы и повторная регистрация одного имени отклоняются.
Ошибки регистрации не заменяют прежний обработчик. Возвращается уникальный ID регистрации.

`UiNativeEvent` содержит `element:uint64`, `kind:UiNativeKind`, `name:string`,
`size:float2` (content box в пикселях) и `time:double` (время RmlUi).

| Kind | Когда вызывается |
|---|---|
| `Create` | Один раз после получения handle, до установки атрибутов Factory и присоединения к документу; размер может быть нулевым |
| `Attribute` | Для каждого изменённого атрибута; `name` — его имя, значение читается через `rui_get_attr`/`rui_has_attr` |
| `Property` | Для каждого изменённого computed property; `name` — имя RCSS-свойства; актуальные размеры для рисования берите в Paint |
| `Resize` | Native `OnResize`, после изменения content box |
| `Update` | Native `OnUpdate`, только при `continuous=true`; может вызываться несколько раз за кадр и для скрытого элемента |
| `Paint` | В native `OnRender`, когда нужно построить или обновить геометрию |
| `Destroy` | Один раз при уничтожении native-объекта; handle уже невалиден, используется только как ключ для cleanup |

`native_rect`, `native_triangle`, `native_line` принимают handle, геометрию,
`UiColor` и необязательный `alpha=1`. Координаты локальны относительно content box,
в физических пикселях. Solid geometry копируется в native mesh и компилируется
через `RenderManager`. Сохранённые native clipping/transform/layer states применяются
при рисовании; возможности transforms/filters зависят от renderer (GL3).
RCSS opacity применяется к цветам вершин каждого примитива: перекрывающиеся
полупрозрачные примитивы смешиваются последовательно, это не отдельная opacity-layer.
Примитивы полностью реализованы в daScript поверх `native_mesh`; отдельных C++
привязок rect/triangle/line нет. Custom shader commands, hit testing и baseline
overrides пока не экспортированы.

### Mesh, UV и текстуры

`UiNativeMesh` — обычная структура daScript с тремя массивами:

- `vertices:array<float4>`: `(x,y,u,v)`, координаты относительно content box в пикселях,
  UV нормализованы относительно всей текстуры;
- `colors:array<uint4>`: один **не premultiplied** RGBA 0..255 на вершину;
- `indices:array<int>`: индексы с нуля, каждая тройка задаёт треугольник.

```das
var mesh:UiNativeMesh
let a=mesh_vertex(mesh,float2(0.,0.),rgb(255,120,80),float2(0.,0.))
let b=mesh_vertex(mesh,float2(200.,0.),rgb(80,230,210),float2(1.,0.))
let c=mesh_vertex(mesh,float2(100.,120.),rgb(180,120,255),float2(0.5,1.))
mesh_triangle(mesh,a,b,c)
native_mesh(event.element,mesh) // Без текстуры, цвета интерполируются.
// native_mesh(event.element,mesh,texture) — те же вершины с текстурой.
```

`mesh_vertex(mesh,position,ink,uv=float2(0.),alpha=1.)` возвращает индекс добавленной
вершины. `mesh_triangle(mesh,a,b,c)` добавляет индексы; вершины можно переиспользовать.
`mesh_quad(mesh,bounds,ink,uv=float4(0.,0.,1.,1.),alpha=1.)` добавляет quad.
В `bounds` лежат `(x,y,width,height)`, в `uv` — **`(u0,v0,u1,v1)`**, не ширина/высота.
Массивы можно заполнять напрямую. Их данные синхронно копируются в C++ при
`native_mesh(element,mesh,texture=0ul)`; после вызова исходные массивы можно менять,
освобождать и собирать GC. Нулевой texture означает solid geometry.

В одном Paint можно отправить несколько mesh с разными текстурами. Порядок вызовов
сохраняется; соседние submissions одной текстуры объединяются, включая solid geometry.
RCSS opacity модулирует vertex alpha; vertex RGBA и generated texture RGBA
premultiply выполняется в C++. На кадрах без invalidation геометрия не пересоздаётся.
Все позиции/UV должны быть конечными, длины vertices/colors совпадать, indices
быть кратны трём и ссылаться на существующие вершины. Лимит на один Paint —
1 000 000 отправленных вершин и 3 000 000 индексов. Неверный mesh отклоняется
целиком до изменения batches. Пустой mesh допустим; вызов всё равно требует Paint.

Текстуры принадлежат **конкретному экземпляру элемента**:

```das
// Инициализировать один раз в Paint, затем сохранить handles в состоянии по element.
let atlas=native_texture_load(event.element,"examples/assets/native_mesh_atlas.png")
verify(atlas!=0ul)
var pixels=array<uint4>(uint4(255u,100u,40u,255u),uint4(40u,200u,255u,128u))
let generated=native_texture_rgba(event.element,int2(2,1),pixels)
verify(generated!=0ul)
// Левая половина атласа. native_image — также daScript-обёртка над mesh.
native_image(event.element,atlas,float4(0.,0.,64.,64.),float4(0.,0.,0.5,1.))
```

- `native_texture_load(element,source):uint64` загружает PNG через RenderManager;
  relative path разрешается относительно native документа. Ошибка загрузки даёт 0,
  RmlUi может записать warning. Не вызывайте load заново на каждом Paint.
- `native_texture_rgba(element,size:int2,pixels:array<uint4>):uint64` создаёт текстуру
  из row-major RGBA, строка 0 сверху. Каналы 0..255, alpha не premultiplied.
  Размер каждой стороны 1..4096, длина массива строго width*height. Неверные аргументы
  вызывают ошибку; ошибка создания renderer даёт 0. Пиксели копируются, callback RmlUi
  владеет C++-копией и не хранит указателей в daScript heap.
- `native_texture_size(element,texture):int2` возвращает размер или `(0,0)` для
  устаревшего/чужого handle.
- `native_texture_release(element,texture):bool` удаляет handle; повторный вызов
  возвращает false. Уже закешированная геометрия сохраняет ресурс до следующего Paint
  или уничтожения элемента. Release сам по себе не инвалидирует геометрию.
- `native_texture_resources():int` — число живых обёрток ресурсов для диагностики,
  включая удержанные batches. Это не число GPU allocations: file textures дополнительно
  кеширует RmlUi до освобождения его texture cache/shutdown. Generated textures
  освобождаются вместе с последней ссылкой элемента/batch.

Создание текстур требует элемента, уже присоединённого к context; Create вызывается
слишком рано. Используйте ленивую инициализацию в Paint или обычный код после mount.
При Destroy все оставшиеся ресурсы освобождаются автоматически; handle элемента
в этом callback уже невалиден. Handles монотонны и не переиспользуются при remount
или shutdown/restart. Передача чужого или released texture в mesh вызывает ошибку.
Для замены картинки создайте новый handle, освободите старый и вызовите invalidate.

Sampler пока задаёт backend: GL3 использует repeat/linear, SDL — своё штатное
семплирование. Для атласов оставляйте padding/inset, если края соседних клеток не должны
смешиваться. Индивидуальные sampler/filter/wrap настройки пока не экспортированы.
Пример `examples/mesh_lab.das` показывает UV-ленту, кольцевой прогресс, градиент
вершин, PNG-спрайты, tint/alpha, кеширование и remount/GC. Тест `native_mesh_pixels`
проверяет те же API на SDL и GL3, включая lifecycle после ошибки Paint.

Обычно Paint не вызывается каждый кадр. Атрибуты, native style changes, размеры
и DPI помечают геометрию устаревшей; `native_invalidate(element)` делает это явно.
Для анимации регистрируйте `continuous=true`, обновляйте своё состояние в Update
и вызывайте invalidate. Сам компонент при этом остаётся закешированным. Одного
изменения таблицы daScript недостаточно для native repaint без invalidate.

`intrinsic` задаёт размер в dp и aspect ratio; положительные размеры делают элемент
replaced element. `(0,0)` оставляет обычную раскладку контейнера. Изменить intrinsic
можно через `native_set_intrinsic(element,size)` из Create/Attribute/Update или обычного
кода. Во время Paint/Destroy это запрещено. Размеры должны быть конечными и положительными.
RCSS width/height переопределяют intrinsic. Атрибуты в DSL отслеживаются отдельными bindings.

Обработчики синхронны и работают на UI-потоке. Из native-хука разрешены чтение
свойств/атрибутов, изменение своего состояния daScript, native invalidate/size и
рисование в Paint. Мутации DOM/context и повторный update/render/shutdown запрещены:
выполняйте их в обычных `on_event`/`on_click` или основном цикле. Это предотвращает
удаление элемента во время собственного native обхода. Рисовать можно только в Paint
текущего элемента. `Create`/`Destroy` не следует использовать как замену component
`on_mount`/`on_unmount`: native lifetime также охватывает элементы из RML/templates.

Реестр lambda хранится в глобальной таблице daScript, которую видит GC; C++ хранит
только статический dispatcher и его Context. Захваченные owning значения и таблицы
состояния сохраняются при GC. Не захватывайте указатели на уже завершившиеся стековые
переменные. Для состояния отдельного экземпляра используйте таблицу по `event.element`,
создавайте запись в Create и удаляйте в Destroy (см. Signal foundry).

`ui_reset` удаляет компонентные элементы, сохраняя регистрации. Закрытие документа
освобождает также его статические native-элементы. `unregister_native_element(tag)`
возвращает false, пока есть живые экземпляры; при успехе освобождает handler/captures.
`rui_shutdown` сначала уничтожает элементы, затем снимает GC roots обработчиков.
Host завершает native context до уничтожения script Context; после нового init типы
нужно зарегистрировать заново. ID не переиспользуются.
Завершайте RmlUi до уничтожения SDL renderer или GL context. Host guard защищает
срок жизни script Context, но не заменяет этот порядок освобождения графических ресурсов.

Исключение callback перехватывается внутри C++-границы, элемент перестаёт получать
обычные callbacks, но Destroy всё ещё вызывается для cleanup и должен учитывать
частично завершившийся Create. Диагностика возвращается
после `ui_frame`, `ui_reset`, `rui_render` или script `rui_shutdown`, когда native
обход завершён. При работе через raw APIs вызывайте `rui_native_check()` после
операции; `rui_native_error()` позволяет прочитать отложенную диагностику.
Необработанная terminal script exception завершает host без повторного входа
в повреждённый script Context; произвольный пользовательский cleanup при таком
аварийном завершении не гарантируется.

Для диагностики есть `native_registered`, `native_instance_count`, `native_handler_count`
и `rui_is_native`. Пример — `examples/native_lab.das`; тесты — `native_elements.das`,
`native_safety.das`, `native_host_lifetime.das` и `native_render.das` с pixel checker.
Native contract сверяется с [RmlUi custom elements](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/custom_elements.html)
и заголовками используемой локальной ревизии.

