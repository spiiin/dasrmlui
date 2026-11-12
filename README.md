# dasrmlui

Рабочая первая версия DSL для RmlUi на **обычном синтаксисе daScript**.
`[ui_component]` описывает дерево и поведение, `[ui_style]` — изолированные
RCSS-правила, `[ui_template]` — рамки native документов. Отдельные `.rml` и `.rcss`
для приложения не нужны.

Окно, SDL renderer, цикл событий, модель, компоненты, стили и runtime DSL написаны
на daScript. C++ нужен для host, биндингов RmlUi и RenderInterface; проект использует
настоящий модуль `sdl3` и `dassdl3/*` из dasSDL3, а не заменяет его собственным SDL API.

## Запуск

Проверенный профиль: Windows x64, MSVC, конфигурации Release и RelWithDebInfo,
локально собранный dasSDL3. Про другие конфигурации и переносимый пакет — в разделе
[«Зависимости и сборка»](#зависимости-и-сборка).

```powershell
cd C:/src/dasrmlui
./tools/build.ps1
./build/bin/dasrmlui.exe examples/inventory.das
```

Демо: редактирование названий, добавление и удаление предметов, перестановка списка,
условные детали выбранного предмета. Пустое название отклоняется setter-функцией.

```powershell
ctest --test-dir build --output-on-failure
./build/bin/dasrmlui.exe examples/inventory.das --smoke-test
```

Smoke запускает три кадра в скрытом окне и сохраняет `logs/inventory.png`.
Папка `logs` создаётся build-скриптом. Большинство тестов работают с SDL dummy video
driver; Effects, Progress Lab, Animations, Style Lab, Vector Lab и Native Lab используют
настоящий OpenGL context. Пиксельные тесты ninepatch, SVG/Lottie и native-элементов
используют настоящий SDL renderer.

## Продвинутые примеры

```powershell
./build/bin/dasrmlui.exe examples/dashboard.das
./build/bin/dasrmlui.exe examples/settings.das
./build/bin/dasrmlui.exe examples/kanban.das
./build/bin/dasrmlui.exe examples/catalog.das
./build/bin/dasrmlui.exe examples/component_lab.das
```

- **Dashboard:** сводные показатели, поиск и фильтры, keyed-список задач,
  редактирование выбранной задачи в инспекторе, смена статуса и приоритета.
- **Settings:** вкладки, черновик и сохранённое состояние, валидация email,
  условные расширенные поля, выбор акцента/плотности и живое превью.
- **Kanban:** три колонки, перенос карточек кнопками, создание, редактирование,
  приоритет и удаление через инспектор. Drag-and-drop пока не реализован.
- **Catalog:** библиотека из 5 000 объектов, виртуальный список, кешируемый поиск,
  адаптивная панель деталей, редактор с локальным черновиком, фокусом, числовыми
  полями, checkbox и select.
- **Component lab / Quote builder:** карточки услуг с локальным состоянием по ключу,
  перестановкой, удалением и повторным созданием, `computed`, слотом содержимого,
  событиями компонентов и журналом `on_mount`/`on_unmount`.

У Dashboard тёмная тема с красными и золотыми акцентами, у Settings светлая тема
форм, у Kanban сиреневая доска с цветными заголовками колонок.
Catalog использует светлую мятно-зелёную тему библиотеки, Component lab — тёплый
угольный фон, медные акценты и крупные суммы. Эти две отдельные темы находятся
в `examples/workbench_style.das`: `catalog_style` и `component_lab_style`. Ориентир —
[официальная галерея RmlUi](https://github.com/mikke89/RmlUi#gallery), особенно
образцы меню и форм. Изображения из галереи в приложение не встроены.

Данные живут в памяти: примеры не обращаются к сети и не сохраняют настройки на
диск. Общие стили/компоненты находятся в `examples/advanced_style.das`, SDL-цикл —
в `examples/demo_host.das`. У каждого примера есть `--smoke-test`: восемь кадров с
проверкой реальных UI-событий и снимки кадров 0, 3 и 7 в `logs/`.
Клики проходят через SDL, hit testing RmlUi и ту же очередь, что ввод пользователя.
Для визуальной проверки запускайте smoke без `SDL_VIDEODRIVER=dummy`: программный
renderer dummy-драйвера не поддерживает используемое premultiplied-смешивание.
Основные скрипты задают `options stack = 65536` для вложенных блоков интерпретатора.

Полное описание нового API и ограничений: [состояние, computed, формы, виртуализация,
фокус и адаптивная раскладка](docs/dsl.md).

## Примеры native возможностей RmlUi

Запуск из корня проекта, после `./tools/build.ps1`:

```powershell
./build/bin/dasrmlui.exe examples/expedition.das
./build/bin/dasrmlui.exe examples/effects.das
./build/bin/dasrmlui.exe examples/drag_drop.das
./build/bin/dasrmlui.exe examples/templates.das
./build/bin/dasrmlui.exe examples/localization.das
./build/bin/dasrmlui.exe examples/progress_lab.das
./build/bin/dasrmlui.exe examples/animations.das
./build/bin/dasrmlui.exe examples/style_lab.das
./build/bin/dasrmlui.exe examples/event_studio.das
./build/bin/dasrmlui.exe examples/navigation_lab.das
./build/bin/dasrmlui.exe examples/vector_lab.das
./build/bin/dasrmlui.exe examples/native_lab.das
./build/bin/dasrmlui.exe examples/mesh_lab.das
```

| Пример | Что демонстрирует |
|---|---|
| Expedition | PNG sprite sheet, range, radio, textarea, native tabset, индикатор топлива |
| Effects | Фильтры, стек теней, backdrop blur, transform, shader, glow/outline/shadow текста |
| Drag & drop / Field logistics | Native drag clone, перенос между контейнерами, вставка перед карточкой, лимит вместимости, отмена сброса снаружи |
| Window template / Field office | Два документа с общей рамкой, три произвольных `slot(name)` для действий, заметок и статуса; независимые компоненты, условный unmount редактора, native move/resize и close/reopen |
| Localization / Explorer passport | English/Deutsch/Русский, `TranslateString`, реактивный `tr`, параметры, plural forms, fallback на английский; сохраняются draft и input handle |
| Progress Lab / Follow the signal | Заполнение S-кривой по накопленной длине сегментов, движущийся спрайт, native radial `fill-image`, play/pause, slider и reset |
| Animations / Orbital | Scoped keyframes, циклические движения, stop/replay, выдвижная панель с сохранением локального состояния при отмене закрытия, уведомления с exit/unmount, completion запуска |
| Style Lab / The relay station | Media queries, темы Night/Paper, масштаб 100/150%, `dp`, адаптивная панель заметок, ninepatch-рамки разных размеров из atlas 2x; ввод сохраняется |
| Event Studio / Signal desk | Полные snapshots событий, Ctrl+S, keyboard/context menu, popup dismiss, native modal, hide/show редактора с локальным черновиком, move/resize и журнал |
| Navigation Lab / Vector deck | Native nav Auto/TreeOrder, явные ID-переходы, disabled, scroll и popup; штатный Debugger по F8, Element Info, Event Log, Outlines и Data Models |
| Vector Lab / Vector atelier | SVG из файла и inline, crop, SVG-декоратор, Lottie JSON; смена источника/цвета/размера, remount и анимация без обновлений компонента |
| Native Lab / Signal foundry | Три осциллограммы как настоящие custom elements: регистрация из daScript, собственная геометрия, native update/paint, события, keyed reorder, remount, resize, Hold и GC |
| Mesh Lab / Bend the surface | Произвольные indexed mesh, UV-лента, кольцевой прогресс, vertex colors, PNG-атлас и RGBA-текстура из daScript, tint/alpha, кеширование и освобождение ресурсов |

Все тринадцать входят в CTest. Для самостоятельного smoke добавьте `--smoke-test`:
шесть SDL-примеров выполняют 8 кадров, семь GL-примеров — 12; снимки идут в
`logs/`. GL-примерам нужен OpenGL 3.3 и Windows video driver, SDL dummy не подходит.
Localization использует установленный `C:/Windows/Fonts/segoeui.ttf` для кириллицы;
шрифт не копируется и не распространяется вместе с проектом.

```powershell
# Все тесты, включая OpenGL и SDL pixel checks:
ctest --test-dir build --output-on-failure
# Только тринадцать примеров native возможностей:
ctest --test-dir build -R 'demo_(expedition|effects|drag_drop|templates|localization|progress_lab|animations|style_lab|event_studio|navigation_lab|vector_lab|native_lab|mesh_lab)$' --output-on-failure
# Без графического контекста:
ctest --test-dir build -LE graphics --output-on-failure
```

У всех примеров UI, стили и поведение находятся в `.das`. Native window template
генерируется из `[ui_template]` и передаётся через in-memory FileInterface; ручная
RML-строка и внешний `.rml` не требуются. Подробнее — [DSL шаблонов](docs/dsl.md#native-документы-и-шаблоны).
Изображение атласа — [отдельный PNG-ресурс](examples/assets/expedition_atlas.png).

## Компоненты и привязки

Полный пример находится в `examples/inventory_ui.das`:

```das
[ui_component]
def inventory_panel(var model : InventoryUi) {
    use_style(@@inventory_style)

    column("panel") {
        when(empty(model.items)) {
            text("empty", "No items")
        }

        model.items |> each_keyed($(item : Item) => item.id) $(item : Item) {
            row("item") {
                text_input("title") {
                    bind_value(item.title) $(value : string) {
                        rename_item(model, item.id, value)
                    }
                }
                stock_badge(item.count)
            }
        }
    }
}
```

- `column`, `row`, `box`, `text`, `text_input`, `button` создают стандартные элементы.
  `element("name", "img")` создаёт элемент с любым другим тегом RmlUi.
- `class_if("selected", condition)` и `pseudo_if(...)` включают класс или псевдокласс по
  условию. В отличие от inline-свойства, смена класса запускает `transition`.
- Вложенные `[ui_component]` — обычные вызовы функций. Параметры проверяет daScript.
- `when` создаёт и удаляет поддерево. При повторном появлении это новый экземпляр.
- `each_keyed` принимает массив и **уникальные `int`-ключи внутри одного списка**.
  Перестановка сохраняет handles элементов; удаление и последующее добавление того же
  ключа создаёт новые handles. Дубликаты приводят к диагностике.
- `bind_value` синхронизирует текст через RmlUi `change`. Getter вызывается во время
  обновления, setter — при доставке события. Setter может отклонить или нормализовать
  ввод; следующий проход возвращает в поле значение модели.
- `disabled() { return condition; }` обновляет атрибут, псевдокласс и доступность
  кнопки. Отключённые элементы не получают клики, в том числе из уже собранной
  очереди после отключения предыдущей командой.
- `on_click` получает событие из очереди. Ни блок, ни адрес элемента массива не
  сохраняются после выхода из функции.
- `ui_frame() { ... }` выполняет доставку событий, синхронизацию DOM и RmlUi Update.
- `ui_reset()` удаляет созданные элементы и очищает runtime перед `rui_shutdown()`.

Не изменяйте модель в обычном теле компонента или getter: тело может выполняться
несколько раз за кадр. Изменения выполняются в обработчиках либо до `ui_frame`.
Обычные циклы с повторным выполнением одного UI-места не поддерживаются — используйте
`each_keyed`. Для динамической структуры используйте `when`.

## Стили

```das
[ui_style]
def inventory_style() {
    rule(root()) {
        padding(px(24.0))
        background(rgb(19, 25, 38))
    }
    rule(part("title")) {
        width(px(300.0))
        color(rgb(235, 240, 249))
    }
    part("action") |> hover() |> rule() {
        background(rgb(65, 117, 183))
    }
}
```

`UiLength` и `UiColor` — разные типы: `width(rgb(...))` не компилируется.
Типизированные helper'ы есть для размеров, отступов, рамок, позиционирования и
flex-свойств: `border(px(1), rgb(54,116,84))`, `border_radius(px(6))`, `margin_x(dp(8))`,
`position("absolute")`, `left(px(40))`; полный список — в
[docs/dsl.md](docs/dsl.md#типизированные-свойства). Для остальных RCSS-свойств остаётся
`property("transform", "rotate(4deg)")`.
`root`, `part`, `hover`, `disabled_state` генерируют селекторы с префиксом таблицы стилей;
`with_class(selector, name)` и `with_pseudo(selector, name)` добавляют к ним класс из
`class_if` или псевдокласс, например `focus`.
Вложенный компонент получает собственную область стилей. Для явного переиспользования
можно вызвать тот же `use_style(@@style_function)`.

`[ui_style]` требует функцию без параметров и кеширует результат первого вызова.
Такие функции должны описывать статические правила и не читать изменяемое состояние.
Динамические свойства задаются внутри компонента, например `width() { return pct(...); }`.
`property` и другие setters относятся к текущему **контейнеру**. Для стилизации
текстового leaf используйте `part(...)` либо явный `box` вокруг текста.

## Реальная развёртка и runtime

Для каждой `[ui_component] def panel(...)` макрос создаёт три отдельные функции
`panel__mount`, `panel__update`, `panel__dispatch` с теми же аргументами. Исходное
имя становится обёрткой, которая проверяет зависимости и выбирает фазу.

- `mount` создаёт DOM и задаёт начальные значения.
- `update` выполняется только при изменении входов или явной инвалидации.
  Статические текстовые узлы сохраняются без повторного присваивания текста;
  свойства с константными аргументами применяются только к новым контейнерам.
  Если `when` или `each_keyed` добавляет поддерево при обновлении, оно получает и
  статический текст, и начальные свойства.
- `dispatch` не вычисляет текстовые getter-блоки и свойства. Runtime обходит только
  компоненты на пути к получателю события. После setter компонент принудительно
  обновляется, даже если модель не изменилась: это восстанавливает отклонённый ввод.

Идентичность учитывает исходный файл, функцию, место вызова, родительский путь и
ключ списка. Пропущенный компонент сохраняет свои DOM-узлы, порядок и дочерние
экземпляры. Удаление поддерева освобождает кеш компонентов и подписки; повторное
появление выполняет новый `mount`. DOM-обёрток для `each_keyed`/`when` нет.

### Зависимости и стоимость

Аргументы компонента автоматически сравниваются по содержимому. Поддержаны
`string`, `bool`, целые от `int8` до `uint64`, `float/double`, перечисления, векторы
(`float2..4`, `int2..4`, `uint2..4`, `range`), структуры, кортежи и массивы из этих типов. Используются снимки значений с границами полей, а не хеш адреса
массива. Поэтому `model.items[0].title = ...`, `push`, удаление и перестановка
обнаруживаются без `revision`. Неизменившийся дочерний компонент пропускается,
даже когда его родитель обновился.

Внутри компонента **у каждой привязки свой снимок зависимостей**. Макрос выделяет
чтения параметров и доступных локальных значений: `model.profile.name` зависит
именно от этого поля, а не от всей `model.profile`. Обрабатываются текст,
подпись кнопки, `bind_value`, свойства и условие `when`. Setter и тело `when`
не входят в зависимости значения/условия.

```das
[ui_component]
def profile(var model:Profile) {
    text("name") { return format_name(model.name) }
    text("email") { return model.email }
    box("preview") { width() { return px(model.preview_width) } }
}
```

Изменение `email` не вызывает `format_name` и getter ширины. В сгенерированных
`profile__mount` / `profile__update` каждая операция получает guard примерно
такого вида (идентификаторы сокращены):

```das
rt_binding("name-binding", $() { rt_dependency(model.name) }, false, false) {
    text("name-site", "name") { return format_name(model.name) }
}
```

Проверяется исходное поле, а не результат вызова `format_name`: сам вызов при
неизменившейся зависимости пропускается. Вызов helper с целой структурой зависит
от всей переданной структуры; межпроцедурного анализа тела helper пока нет.
Индексирование отслеживается консервативно по исходному массиву и внешнему индексу,
чтобы при проверке не выполнять потенциально небезопасное чтение элемента.
Доступ к `item.title` внутри `each_keyed` отслеживается отдельно для каждого ключа.

`when` кеширует только вычисление условия. При сохранении `true` его дочерние
привязки продолжают проверяться, поэтому изменение текста внутри не теряется.
Переупорядочивание keyed-списка сохраняет снимки привязок. При удалении поддерева
снимки очищаются, а повторное добавление ключа заново выполняет привязки.
`bind_value` дополнительно обновляется после `change` своего input, даже если
setter отклонил значение. Соседние поля при этом не пересчитываются.

Стоимость не стала нулевой: аргументы корня по-прежнему сравниваются по содержимому,
а при изменении компонента выполняется обход его структуры и проверка зависимостей
привязок. Также остаются сопоставление DOM, обход массива и проверка ключей списка.
Пропускаются именно вычисления неизменившихся привязок. Произвольный код перед
UI-вызовами и выражения аргументов дочерних компонентов исполняются как обычный
код daScript; дорогие вычисления помещайте внутрь getter или отдельного компонента
с узкими входами. Getter без определённых зависимостей консервативно выполняется
при каждом обновлении компонента.

Для большого внешнего состояния можно передавать компактные входы и использовать
токены инвалидации:

```das
var inventory_changed = ui_signal()
var external_title = "Inventory"

[ui_component]
def external_heading() {
    ui_watch(inventory_changed)
    text("heading") { return external_title }
}

// В обработчике или до ui_frame:
// external_title = "Updated inventory"
// inventory_changed |> ui_touch()
```

`ui_watch` переносится макросом в фазу регистрации зависимостей. Его аргумент
должен быть доступен при входе в функцию: глобальная переменная либо параметр,
не локальная переменная внутри `each_keyed`. `ui_touch` помечает подписчика **и
всех его родителей**, поэтому спящий родитель не блокирует обновление ребёнка.
Этот явный сигнал инвалидирует все привязки самого подписчика; у родителей
он вызывает обход, сохраняя кеши их независимых привязок. При unmount подписки снимаются. Изменения глобальных переменных и скрытого
состояния внутри helper-функций автоматически не перехватываются: для них нужен
токен и `ui_touch`. Указатели, native handles, таблицы и замыкания в аргументах
пока не поддерживаются как снимки; передавайте значения/версию.

`ui_stats()` возвращает счётчики `mounts/updates/skips/dispatches` и
`binding_mounts/binding_updates/binding_skips`,
`ui_clear_stats()` обнуляет их. Пропуск целого родителя считается одним `skip`.

Нативный listener копирует события в очередь. Каждая команда доставляется отдельно,
затем DOM синхронизируется перед следующей командой; события удалённых элементов
отбрасываются. Все пользовательские блоки вызываются синхронно, без сохранения
ссылок на стек или элементы массива. Список клонируется на время обхода.

### Синтаксис блоков и пайпы

Блок без параметров пишется без `$`: `on_click() { ... }`,
`text("name") { return value; }`. `when(condition)` принимает обычный `bool`,
а `bind_value(value) $(new_value:string) { ... }` — текущее значение и setter.
Формы с getter-блоками также сохранены. Для блока с параметрами `$` нужен.
`$e/$v/$i` внутри макросов — AST-подстановки, их также нельзя убрать.

`items |> push <| Item(...)` добавляет значение в массив;
`part("action") |> hover() |> rule() { ... }` последовательно строит селектор
и правило. Всё разбирается штатным парсером daScript.

Для длинного цикла скрипта используйте `options persistent_heap`, `options gc` и
периодический `heap_collect` в безопасной точке, как в `examples/inventory.das`.

## Текущее покрытие и ограничения

Подробная [матрица покрытия RmlUi](docs/rmlui-coverage.md) отделяет готовые
возможности от частичных bindings, отсутствующих helpers и незавершённых примеров.

- Один UI context на процесс. Поддержаны несколько RmlUi documents внутри окна;
  несколько независимых SDL-окон/context пока не реализованы.
- `rui_init` использует SDL_Renderer: текст, PNG-текстуры, геометрия и прямоугольный
  scissor. Для transform, clip masks, layers, filters и shader decorators добавлен
  отдельный `rui_init_gl` с upstream GL3 renderer; окно/context и ввод остаются в
  dasSDL3. Его использует `examples/effects.das`.
- Перемещение строки восстанавливает фокус/выделение текстового input. Подключён
  штатный SDL IME adapter; во время композиции внешнее присваивание и перемещение
  сфокусированной строки откладываются. Реальный ввод через конкретные IME не проверен.
- Ключи пока `int`. `virtual_each` поддерживает фиксированную высоту строк;
  переменная высота не реализована. Подробности стоимости — в `docs/dsl.md`.
- Есть select, range, radio, textarea, tabset, progress и sprite-sheet helpers;
  дополнительные native controls демонстрирует `examples/expedition.das`.
- Восемь примеров native возможностей включены в CTest. Media/theme правила,
  `dp`, DPI и ninepatch описаны в `docs/dsl.md`; физические переходы между
  мониторами с разным DPI отдельно не проверялись.
- Нет hot reload, AOT-профиля, полного event API и сложного text shaping.
  Native documents/templates, translation bridge и drag-and-drop демонстрируются
  отдельными примерами; ограничения перечислены в матрице покрытия.
  Это не заявление о полном покрытии RmlUi.
- Проверен Windows/MSVC interpreter. CMake больше не привязан к MSVC и к Release, но
  другие ОС и toolchain не проверялись: для них нужна сборка dasSDL3 тем же toolchain.
- По умолчанию используется LatoLatin из зависимости RmlUi (`rui_default_font`). Свой
  шрифт, например с кириллицей, загрузите через `rui_font` и назовите его семейство в
  `set_base_text("Segoe UI")` — оно станет базовым для всех документов.

## Зависимости и сборка

Проект читает существующие исходники/библиотеки и ничего не изменяет в соседних репозиториях.
Пути задаются CMake cache-переменными:

| Переменная | Значение по умолчанию |
|---|---|
| `DASSDL3_DIR` | `C:/src/dasSDL3` |
| `DASSDL3_BUILD` | `${DASSDL3_DIR}/build/ninja` |
| `RMLUI_DIR` | `C:/src/dascript_sdl_gui/third_party/RmlUi` |

Профиль использует совместимые статические библиотеки daScript, SDL3 и FreeType из
dasSDL3. CMake читает пути к SDL/FreeType из его cache, а системные библиотеки SDL3
берёт из его же CMake-пакета. Отдельная копия daScript или SDL в executable не
линкуется. Эта логика вынесена в `cmake/dependencies.cmake`.

### Конфигурации

Конфигурация должна линковаться с указанной сборкой dasSDL3. Отладочная сборка меняет
C runtime и build id daScript, поэтому правило такое:

| Сборка dasSDL3 | Допустимые конфигурации dasrmlui |
|---|---|
| Release, RelWithDebInfo, MinSizeRel | Release, RelWithDebInfo, MinSizeRel |
| Debug | Debug |

Несовместимую конфигурацию CMake отклоняет при конфигурировании с объяснением. Если
`CMAKE_BUILD_TYPE` не задан, берётся первая допустимая. У генераторов с несколькими
конфигурациями (Visual Studio) в список попадают только допустимые.

```powershell
./tools/build.ps1 -Configuration RelWithDebInfo -BuildDir build-relwithdebinfo
```

Имена библиотек строятся по правилам toolchain, MSVC-флаги и системные библиотеки
Windows включаются только там, где они нужны. Проверено это только на MSVC с Ninja
(Release и RelWithDebInfo) и конфигурированием под Visual Studio 2022.

### Где exe ищет скрипты и шрифт

Хост ищет каталоги `daScript`, `dassdl3`, `dasrmlui`, `examples` и файл
`assets/LatoLatin-Regular.ttf` в таком порядке:

1. в каталоге из переменной окружения `DASRMLUI_HOME`;
2. рядом с исполняемым файлом и на уровень выше (в пакете exe лежит в `bin/`);
3. в дереве, из которого он собран, — только если сборка сделана с
   `DASRMLUI_DEV_PATHS=ON` (так по умолчанию).

`dasrmlui --roots` показывает, что и откуда взято. Без первых трёх каталогов хост
завершается с кодом 5 и сообщением; `examples` и шрифт необязательны.

### Переносимый пакет

```powershell
cmake -S . -B build-package -G Ninja -DCMAKE_BUILD_TYPE=Release -DDASRMLUI_DEV_PATHS=OFF
cmake --build build-package
cmake --install build-package --component runtime --prefix dist
./dist/bin/dasrmlui.exe examples/dashboard.das
```

В `dist` попадают exe, `daslib`, das-модули dasSDL3 и dasrmlui, примеры и шрифт
LatoLatin с его лицензией. Каталог можно переносить: с `DASRMLUI_DEV_PATHS=OFF` в
бинарнике не остаётся путей к дереву сборки. Примеры обращаются к своим ресурсам
относительно текущего каталога, поэтому запускайте их из корня пакета. Тест
`runtime_package` собирает такой пакет и запускает из него пример.

Что пакет не делает: лицензии остальных библиотек (RmlUi, SDL3, daScript, FreeType,
lunasvg, rlottie) в него не копируются, а в бинарнике остаются имена исходных файлов
daScript из его отладочных сообщений.

Проверенная ревизия dasSDL3: `a13e01f1f8a42683d212d4498137d37732529478`.
Ревизия встроенного daScript: `ebac0ffe46ab30de6c9536f4b0af7a33ede45902`.
Проверенная ревизия RmlUi: `821cbd229d804cb1c905b729af86c21133abceee`.

## Проверки

`runtime.das` проверяет настоящие DOM/input RmlUi: идентичность и порядок после
перестановки, вложенные компоненты, фокус/выделение, ввод через `ProcessTextInput`,
двустороннюю синхронизацию, отклонённое значение, условные поддеревья, удаление и
повторное использование ключа, порядок команд, устаревшие события и работу после GC.

`incremental.das` проверяет 120 кадров без выполнения тел/getter-блоков, выборочное
обновление дочерних компонентов, пробуждение родителей через зависимости, снятие
подписок, повторный mount, GC и reset.

`bindings.das` проверяет независимость соседних/вложенных полей, свойства,
кеширование условий с обновлением их детей, прямое и двустороннее значение,
действительно отключённые кнопки и события к отключённым целям,
перестановку/удаление/возврат ключей, GC и reset. Три smoke-теста примеров
доставляют клики и ввод через очередь RmlUi и проверяют прикладное состояние.

Отдельные тесты проверяют три сгенерированные функции, отказ при дубликатах ключей и ошибку
типа в стиле. Отрицательные тесты проверяют одновременно код завершения и диагностику.

`lifecycle.das` проверяет ключи, последнее состояние в cleanup, порядок удаления,
GC и повторный reset. `composition.das` проверяет computed, слоты, события и имена
зависимостей в trace. `viewport.das` проверяет 10 000 строк при ограниченном DOM,
scroll/shrink/resize и клавиатурный фокус. `forms.das` проверяет черновики, диапазоны,
переполнение, валидацию, Enter/blur/Escape, checkbox мышью и select клавиатурой.
В CTest входят восемнадцать интерактивных примеров; полный список — `ctest --test-dir build -N`.
Новые проверки также покрывают отказ drop при заполненном контейнере, сохранение
ключей при перестановке, native move/resize, teardown документов, перевод native
RML и смену языка без изменения модели, заполнение разных участков кривой и размер
радиального индикатора. Скриншоты помогают визуальной проверке; это не pixel-golden
тесты, анимация shader зависит от времени.

`tests/templates.das` проверяет генерацию native шаблона, кеширование нескольких
экземпляров, scoped styles, экранирование текста/атрибутов, динамический content,
GC и повторную инициализацию context. `tests/template_slots.das` проверяет несколько
произвольных слотов, независимость экземпляров, сохранение state/focus, выборочное
обновление, смену target, условный unmount и повторный reset. Отрицательные тесты
проверяют динамические конструкции в шаблоне, повторные/пустые имена, отсутствующий
target, заполнение обычного узла и детей внутри объявления слота.

Объявляйте места вставки через `slot("имя")`, заполняйте через
`document_content(document,"имя") { component(model) }`. Главного слота нет;
старый `content_slot` удалён, существующие вызовы заменены на `slot`.

`style_environment.das` проверяет native media/theme и dp без remount, автоматическую
подписку читающих среду компонентов, DPI и сохранение пользовательского масштаба.
`ninepatch_pixels` сравнивает углы/центр реально отрисованных рамок при разных
размерах, DPI и темах. Геометрический atlas воспроизводится командой
`./tools/make_style_atlas.ps1` и не требует внешних ресурсов.

`events.das` проверяет capture/target/bubble, параметры мыши/клавиатуры, синхронную
остановку распространения и native default action, GC, изменение подписок и stale
очереди. `documents.das` — скрытую загрузку, focus modes, front/back, modal isolation,
отложенный ввод, popup поверх modal, Escape/outside dismissal, resize и retained draft.
DSL API: [события](docs/dsl.md#события-элементов-и-документов) и
[режимы документов](docs/dsl.md#режимы-документов-popup-и-редакторы).

`navigation.das` проверяет штатные режимы `nav`, переходы по document-local ID,
скрытые/отключённые цели, scroll, ввод текста, Tab scope и popup. `debugger.das`
проверяет F8, native picking без вызова прикладного callback, удаление выбранного
элемента, изоляцию стилей, фокус, отключение и restart плагина. В Vector deck F8
открывает штатную панель RmlUi: нажмите Element Info и выберите плитку. Для нашего
состояния daScript используйте `ui_trace`/`ui_stats`; Data Models инспектирует только
native модели RmlUi. API: [native navigation](docs/dsl.md#native-spatial-navigation)
и [Debugger](docs/dsl.md#встроенный-rmlui-debugger).

SVG/Lottie используют официальные плагины RmlUi и закреплённые LunaSVG/rlottie.
Первый build скачивает зависимости через Git; [версии, лицензии и offline build](docs/vector-dependencies.md).
API: [SVG и Lottie](docs/dsl.md#svg-и-lottie). Геометрические SVG/JSON воспроизводятся
`python tools/make_vector_assets.py`. Runtime-тест проверяет native factories, смену
источника, независимые привязки, шаблоны, DPI и lifecycle; pixel-тест — crop,
декоратор, tint/opacity и фактическое движение/цикл Lottie при замороженных bindings.
Native Lottie автоматически повторяется; плагин этой версии не предоставляет pause/seek.

Native-элементы регистрируются через `register_native_element`, создаются через
`native_element` в компонентах и шаблонах. Обработчики Create/Attribute/Property/Resize/
Update/Paint/Destroy написаны на daScript; owning lambdas остаются GC roots до снятия
регистрации или shutdown. Геометрия кешируется и рисуется через RenderManager RmlUi.
События UI используют обычный DSL. [API и правила lifetime](docs/dsl.md#пользовательские-native-элементы).
Тесты покрывают ключи, захваченные значения, GC внутри callback, шаблоны, ошибки/reentry,
unregister, shutdown/restart и завершение script Context; отдельный pixel test —
геометрию, clipping, opacity, DPI и resize.
`UiNativeMesh`/`native_mesh` добавляют UV, vertex RGBA и индексы треугольников;
`native_texture_load`/`native_texture_rgba` — PNG и пиксели daScript. Rect/triangle/line
теперь целиком написаны на daScript поверх этого API. `native_mesh_pixels` проверяет
SDL/GL3 pixels, порядок смешивания, atlas UV, tint/alpha, GC, stale handles и cleanup
после ошибки Paint. [Контракт API](docs/dsl.md#mesh-uv-и-текстуры).

## Файлы

- `dasrmlui/macros.das` — AST-аннотации компонентов, стилей и шаблонов.
- `dasrmlui/ui.das` — runtime и типизированный API стилей на daScript.
- `src/rml_module.cpp` — SDL_Renderer, безопасные handles и биндинги RmlUi.
- `src/native_elements.inc` — custom Element/Instancer, callbacks и кеш native-геометрии.
- `src/host.cpp` — загрузка модулей и запуск `[export] main(smoke:bool):int`.
- `examples/inventory_ui.das` — прикладная модель, компоненты и стили.
- `examples/inventory.das` — окно и цикл приложения на dasSDL3.
- `tests/` — интеграционные и отрицательные проверки.
