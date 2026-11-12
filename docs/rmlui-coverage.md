# Покрытие RmlUi в dasrmlui

Аудит исходников на 2026-11-12. Проверена локальная ревизия RmlUi
`821cbd229d804cb1c905b729af86c21133abceee` (CMake version 6.4, unreleased),
а не только возможности последней опубликованной документации.

**Есть** означает наличие реализации в проекте. **Частично** означает наличие
общего механизма или части API, но не законченного интерфейса и проверки всех
сценариев. Наличие функции в самой RmlUi не означает, что она экспортирована в
daScript. Наличие примера не означает, что он включён в CTest.

## Что уже есть

| Область | Реализация и примеры | Граница покрытия |
|---|---|---|
| Компоненты | `[ui_component]`, отдельные mount/update/dispatch, зависимости отдельных bindings, keyed-списки, `when` | Это runtime dasrmlui, а не встроенные RmlUi data models |
| Состояние и композиция | `local_state`, mount/unmount, computed, слоты, события, сигналы | Локальное состояние живёт до unmount; возврат удалённого ключа создаёт новый экземпляр |
| Виртуализация | `virtual_each`, Catalog, `tests/viewport.das` | Фиксированная высота строки, int-ключи, проверка всех ключей при обновлении |
| Формы | Текст, числовые drafts, checkbox, select, ошибки, Enter/blur/Escape | Прикладная валидация; не универсальная обёртка `<form>` |
| Дополнительные native controls | range, radio, textarea, tabset, progress в `examples/expedition.das` | Smoke включён в CTest |
| Фокус и раскладка | Tab/Shift+Tab scope, восстановление фокуса, resize, `flow`, flex через свойства | Не менеджер окон или всех сочетаний клавиш |
| Native события | `on_event`, `document_events`, capture/target/bubble, target/currentTarget, клавиши/modifiers, mouse/wheel, copied parameters, синхронные stop flags | Обработчик получает snapshot в ui_frame; cancellation задаётся до dispatch. Нет browser PointerEvent API; load не воспроизводится после создания, cleanup выполняет on_unmount |
| Режимы документов | Скрытая загрузка шаблона, hide/show, modal/focus/scroll flags, front/back, position, retained editor; `show_popup` с clamping/Escape/outside dismissal и возвратом фокуса | Один context; native modal изолирует ввод при владении фокусом; front/back внутри z-index; popup не уменьшает свой размер |
| Стили | Scoped `[ui_style]`, произвольные селекторы в `rule`, RCSS через `property` | Большинство свойств строковые; отдельный типизированный helper не обязателен для доступа |
| Спрайты | `spritesheet(source,resolution)`, `sprite`, `sprite_image`, PNG atlas в Expedition и Style Lab | Выбор разных atlases можно задать media/theme rules |
| SVG / Lottie | Официальные плагины включены; `svg_image`, `svg_inline`, `svg_decorator`, `lottie`, `image_color`; компоненты/шаблоны, отдельные bindings; Vector atelier | Native automatic loop, без pause/seek. Subset форматов зависит от LunaSVG/rlottie; перезапись ресурса по старому пути не является hot reload |
| Эффекты | `examples/effects.das`: фильтры, backdrop blur, тени, поворот/масштаб, upstream shader `creation`, glow/outline/shadow текста | GL3 smoke включён в CTest. Это не API загрузки произвольных шейдеров |
| Native templates | `[ui_template]` + `[ui_style]`, произвольные `slot(name)`, автоматический title, native handles; Field Office заполняет три слота отдельными компонентами | Без главного слота и прежнего `content_slot`. Проверяются имена, изоляция экземпляров, обновления/state/focus, смена target, lifecycle, кеш, экранирование и перезапуск |
| Локализация | `examples/localization.das`: TranslateString, реактивный tr, en/de/ru, plural forms, fallback каталога | Проверены UTF-8, native parser и сохранение input/focus; не ICU/RTL |
| Прогресс по кривой | `examples/progress_lab.das`: S-кривая по длине сегментов и radial sprite fill | GL3 smoke, play/pause/reset и проверки фактических свойств/геометрии |
| Keyframe-анимации | Scoped `keyframes`/`keyframe`, `motion`/`animate`, repeat/alternate, stop/replay, `animated_when`, grouped completion и transition callback; `examples/animations.das` | Проверены native интерполяция без пересчёта компонентов, cancel exit/state/focus, unmount, устаревшие события, GC и GL3 smoke |
| Media/themes/DPI/ninepatch | `media`, `theme`, context theme API, `dp`, пользовательский scale поверх display scale, atlas resolution, `ninepatch`; `examples/style_lab.das` | Native стили без remount, подписки читателей среды, DPI и pixel checks углов/центра на SDL; физический переход между мониторами не проверен |
| Диагностика DSL | `ui_stats`, `ui_trace`, AST dump, отрицательные тесты | Это не визуальный RmlUi Debugger |
| Spatial navigation | Typed `nav`, `nav_up/right/down/left`, `UiNav`, `nav_to`, `nav_id`, `tab_stop`, `document_nav`; native geometry/tree-order/ID и focus-visible | Native auto ограничен scroll container; focus_scope ограничивает Tab; геймпадная обвязка SDL отдельно |
| RmlUi Debugger | Официальный плагин: lazy init, F8, toolbar, Element Info, Event Log, Outlines, Data Models, hide/shutdown и reactive status; Vector deck | Один context; Data Models не показывает состояние DSL. Hide дополнительно закрывает инструменты и выключает picking/outlines |

Файлы реализации: [ui.das](../dasrmlui/ui.das),
[macros.das](../dasrmlui/macros.das),
[rml_module.cpp](../src/rml_module.cpp).

## Что ещё не покрыто или покрыто частично

| Возможность RmlUi | Текущее состояние dasrmlui | Что потребуется |
|---|---|---|
| Несколько context/SDL-окон | Несколько native документов в одном context поддержаны, включая режимы окон | Отдельные context и рендеринг в нескольких SDL windows |
| Полный drag-and-drop | `draggable(payload)`/`on_drop`, native clone, подсветка target; lifecycle через `on_event`, безопасный source handle | Автоскролл, более сложные payloads и дополнительные прикладные сценарии |
| Дополнительное управление анимациями | Управляемые CSS keyframes и enter/exit реализованы; одна анимация на узле | Прямые `Element::Animate`/`AddAnimationKey`, pause/resume, параллельные клипы, плавный разворот exit и автоматическое удержание удалённых записей списка; `var(...)` внутри managed keys пока не поддержан |
| Дополнительные media queries | Native `media(...)`, typed условия, conjunction/not и theme API реализованы | Остальные native условия доступны строкой; nested queries и CSS Level 4 comparisons не поддерживаются самим RmlUi |
| RCSS custom properties/`var(...)` | Доступны строками через `property`, поддерживаются локальной RmlUi | Удобные токены и пример смены палитры; отдельный механизм наследования писать не требуется |
| DPI на реальном оборудовании | Начальный display scale и pixel dimensions, события смены display scale с сохранением user scale, dp и atlas resolution реализованы | Физические переходы между мониторами разных DPI; тесты сейчас программно меняют display ratio |
| Другие tiled/text decorators | Ninepatch helper и пример готовы; tiled-box, tiled-horizontal/vertical и text decorator доступны через `property` | Отдельные helpers/примеры для этих decorators и font icons |
| Radial/conic gradients, mask-image, 3D perspective | Доступны через RCSS с подходящим renderer; GL3 реализует необходимые расширения | Примеры/проверки масок, градиентов, вложенного clipping и 3D. Нельзя переносить этот статус на SDL_Renderer |
| Полная семантика форм | Нет DSL `<form>`/`<label>` и native submit dictionary; password возможен через input type attribute | Helpers и тесты label→focus, name/value отправки формы. Нынешний `on_submit` — Enter handler, а не native form submit |
| Touch и IME | SDL adapter передаёт touch, подключён IME handler; есть защита композиции при обновлении input | Реальные сценарии на устройствах/IME, прикладные touch callbacks и жесты. Базовая передача событий уже есть |
| Шрифтовый fallback и shaping | Есть `rui_font` и `rui_fallback_font`; кириллица показана с Segoe UI. Используется FreeType | Проверки цепочек fallback/CJK; отдельная интеграция HarfBuzz для сложного shaping и проверка RTL. Загрузка шрифта сама этого не решает |
| Табличная раскладка и rich text | `display: table*` доступен через `property`; `text()` создаёт plain text | Helpers/пример таблицы с row/col spans, inline fragments и управляемым форматированием текста |
| Пользовательские элементы, decorators, filters, shaders | Native API регистрации не экспортирован | Явный ABI и lifetime для расширений, безопасные callbacks daScript; для shader — поддержка renderer |
| Встроенные RmlUi data models | Нет `CreateDataModel`/Bind/DirtyVariable bindings | Только если нужна совместимость с существующими RML `data-*`; для текущих компонентов эту задачу решает наш runtime |
| Файловая система и ресурсы | FileInterface читает зарегистрированные текстовые ресурсы из памяти, остальные файлы — с диска; texture loaders читают PNG с диска | Архивы, invalidation/cache reload, in-memory textures, расширение форматов при необходимости |
| Планирование обновлений | Компоненты пропускают пересчёт, но host продолжает Update/Render и SDL_Delay | Интеграция `Context::GetNextUpdateDelay` с очередью событий, анимациями и сигналами; проверить idle CPU |

`rui_watch` остаётся legacy подпиской на ограниченный набор типов. Новый `on_event`
регистрируется непосредственно на элементе для любого native event. `stop` и
`stop_immediate` применяются синхронно по параметрам подписки: RmlUi связывает
остановку распространения с отменой default actions. Отложенный setter не может
изменить уже завершившийся native dispatch; независимого PreventDefault здесь нет.

## Десять примеров native возможностей и тесты

- `drag_drop.das`: перенос, перестановка с сохранением keyed handle, отказ при
  заполненном контейнере, отмена снаружи и невалидный payload.
- `templates.das`: два экземпляра native template, три именованных слота, выборочное
  удаление редактора, move/resize, input binding, закрытие/повторное открытие и ui_reset.
- `localization.das`: три языка, plural forms, fallback, native RML translation,
  внешний set_locale без изменения модели, сохранение input/focus.
- `progress_lab.das`: 0/50/100%, opacity разных участков кривой, позиция спрайта,
  размер/значение radial progress, reset и play/pause.
- `expedition.das`: range/radio/tabset/textarea/sprite selection и resize.
- `effects.das`: filter controls, вкладки transform/type и reset.
- `animations.das`: плавающий корабль, циклический beacon, отмена exit панели без
  remount, уведомления с отложенным удалением, completion запуска и stop ambient.
- `style_lab.das`: две темы, dp-масштаб, media layout, один atlas для рамок разных
  размеров, сохранение текста. Отдельный ninepatch pixel test работает на SDL.
- `event_studio.das`: keyboard/context menu, popup, modal и скрываемый локальный
  редактор. `events.das` и `documents.das` проверяют фазы/параметры событий,
  cancellation, подписки/GC, фокус, слои, modal, popup и отбрасывание stale команд.
- `navigation_lab.das`: native nav, ID-переходы, scroll, popup и штатный Debugger.
  `navigation.das` и `debugger.das` проверяют режимы, фокус, picking, styles,
  lifecycle/GC, restart и отсутствие лишних обновлений; есть отрицательный ID test.

- `vector_lab.das`: SVG file/inline/crop/decorator и native Lottie, смена источника,
  цвета, размеров и remount. Runtime и pixel tests проверяют независимые bindings,
  native factories, templates, DPI, lifecycle, загрузку и кадры анимации по времени.

Все одиннадцать зарегистрированы в CTest. Effects, Progress Lab, Animations, Style Lab и Vector Lab имеют метку `opengl`
и требуют настоящего OpenGL 3.3 context; остальные используют SDL dummy для smoke.
Для визуальной проверки SDL-примеры отдельно запущены с Windows renderer.

## Приоритет дальнейшей работы

1. **Готово:** анимации — DSL keyframes, запуск/повтор/остановка, enter/exit lifecycle,
   пример Orbital и регрессионные тесты.
2. **Готово:** универсальные именованные слоты — `slot(name)`, заполнение через
   `document_content(document, name)`, проверки имён, изоляции экземпляров,
   обновлений и lifecycle; Field Office с тремя слотами. Прежний `content_slot`
   удалён без alias, главного слота больше нет.
3. **Готово:** media/themes/DPI и ninepatch — DSL, пример Relay Station,
   проверки runtime и pixels; реальный перенос между мониторами остаётся непроверенным.
4. **Готово:** события элементов/документов с snapshots и синхронными параметрами
   остановки; hide/show, modal/focus/front/back, popup с dismissal и сохранением
   фокуса; Signal desk, runtime и smoke тесты.
5. **Готово:** встроенный Debugger RmlUi и native spatial navigation — DSL, пример
   Vector deck, проверки инспектора, клавиатурных переходов, popup, фокуса и lifecycle.
6. **Готово:** SVG/Lottie — официальные плагины с закреплёнными зависимостями, DSL
   компонентов/шаблонов/стилей, Vector atelier, runtime/negative/pixel tests.
7. Расширения renderer/element instancers и совместимость с native data models — по
   конкретному сценарию, а не ради дублирования всех C++ методов.

В локальном property index нет CSS Grid: обещать его как просто неэкспортированный
режим RmlUi также нельзя.

## Расширения библиотеки

Отдельный список будущих возможностей dasrmlui поверх RmlUi. Эти пункты не относятся
к недостающей поддержке native API и не меняют очередь работ по покрытию RmlUi.
Порядок реализации пока не определён.

| Расширение | Что реализовать |
|---|---|
| Tree widget | Компонент дерева с раскрытием узлов, выбором и клавиатурной навигацией |
| Table widget | Компонент таблицы с сортировкой, выбором строк и редактированием ячеек; native RCSS table layout учитывается отдельно в покрытии RmlUi |
| Docking | Пристыковка панелей, разделители и сохранение раскладки рабочего пространства |
| Hot reload | Перезагрузка компонентов и стилей с сохранением или миграцией состояния |
| Виртуализация переменной высоты | Измерение строк разной высоты, расчёт видимого диапазона и сохранение позиции прокрутки |

## Renderer и проверка

`rui_init` использует локальный SDL_Renderer bridge: геометрия, PNG, текст и
прямоугольный scissor. Он не реализует transforms, clip masks, layers, filters и
shader hooks. `rui_init_gl` использует upstream GL3 renderer с этими расширениями;
SDL3 по-прежнему создаёт окно/context и доставляет ввод.

На момент аудита `ctest --test-dir build --output-on-failure`:
**53/53 passed** в полном прогоне. Включены одиннадцать примеров native возможностей,
пять OpenGL тестов и два SDL pixel tests,
генерация/слоты шаблонов, анимации, media/theme/DPI, события/режимы документов,
Debugger/spatial navigation, SVG/Lottie, регрессии и отрицательные проверки DSL.
После финальных правок примера/тестов и повторной сборки все пять SVG/Lottie проверок
повторены отдельно: **5/5 passed** (`logs/ctest-vectors-final.log`).
Signal desk и Vector deck также проверены на Windows renderer по снимкам редактора,
modal, popup и штатного инспектора RmlUi.
Vector atelier визуально проверен в OpenGL. SVG/Lottie pixel test на SDL проверяет
прозрачные поля/crop, декоратор, tint/opacity, inline replacement, DPI, resize,
смену источника и реальные положения анимированной фигуры через 0/0.5/1/2 секунды.
Runtime дополнительно проверяет in-memory и повреждённые ресурсы, ошибки загрузки
с последующим восстановлением и повторную регистрацию плагинов после shutdown.
Ninepatch отдельно проверяется по пикселям четырёх углов и центра на SDL при
разных размерах, 1x/2x и смене темы. Это не проверка всех строк матрицы и не полное
pixel-golden сравнение всех экранов.

## Источники

- [Native elements](https://mikke89.github.io/RmlUiDoc/pages/rml/element_index.html)
- [RCSS property index](https://mikke89.github.io/RmlUiDoc/pages/rcss/property_index.html)
- [Media queries и темы](https://mikke89.github.io/RmlUiDoc/pages/rcss/media_queries.html)
- [Decorators и требования к renderer](https://mikke89.github.io/RmlUiDoc/pages/rcss/decorators.html)
- [Ninepatch](https://mikke89.github.io/RmlUiDoc/pages/rcss/decorators/ninepatch.html)
- [Documents и modal state](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/documents.html)
- [User interface, drag и navigation](https://mikke89.github.io/RmlUiDoc/pages/rcss/user_interface.html)
- [Встроенный Debugger](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/debugger.html)
- [SVG plugin](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/svg.html)
- [Lottie plugin](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/lottie.html)
- [C++ API и плагины](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual.html)
- [Native data binding](https://mikke89.github.io/RmlUiDoc/pages/data_bindings.html)

Также сверены локальные `Context.h`, `Element.h`, `ElementDocument.h`,
`Factory.cpp`, `ElementFormControlInput.cpp`, SDL/GL3 backends и состав Samples.
