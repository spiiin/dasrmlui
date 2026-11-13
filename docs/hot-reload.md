# Hot reload / LiveHost

В исполняемый файл встроен upstream `Module_LiveHost` daScript. `--watch` использует
его persistent store, `@live`, lifecycle-аннотации, часы и запросы reload/reset.
SDL3/RmlUi frame driver находится в `src/live_host.cpp` и `src/live_adapter.inc`.

## Запуск

```powershell
./build/bin/dasrmlui.exe examples/live_lab.das --watch --styles examples/live_lab_styles.das
```

Оба файла — обычный daScript. Сначала измените заголовок, заметки и порядок карточек
в UI. Правка `live_lab.das` пересоберёт компоненты, восстановив значения. Правка
`live_lab_styles.das` заменит стили существующего DOM. F5 повторяет перезагрузку,
Shift+F5 или `request_reload(true)` сбрасывает данные. `request_exit()` закрывает host.

Host следит за entry-файлами и загруженными зависимостями с интервалом 250 мс.
Компиляция синхронная: во время неё кадры временно приостанавливаются. Проверяется
содержимое файлов, поэтому запись с прежним размером или временем также обнаружится.
`--frames N --smoke-test` ограничивает прогон и скрывает окно для автоматических тестов.

## Lifecycle

```das
require dasrmlui/live
struct App { title:string="Workspace" }
var app:$UiState<App>?

[export]
def init() {
    ui_live_window("My application",1100,760) // gl3=true — OpenGL 3.3
    app=ui_state("workspace",1,App())
}
[export]
def update() { ui_frame(app) $(var model:App) { workspace(model) } }
// Необязательно: [export] def shutdown() { ... }
```

Host владеет окном, SDL_Renderer или SDL_GLContext, обработкой событий и present.
`update()` строит кадр; отдельный `main(smoke)` для live-приложения не нужен.
Обычный режим `main(smoke)` продолжает работать без `--watch`.
`ui_state` можно создавать и глобально: перед simulation кандидата host сохраняет
актуальные значения предыдущего Context. Между кадрами используется стандартная
политика LiveHost `collectHeapIfMostlyFree`.
UI-операции и native-регистрации должны выполняться в `init/update`, не в глобальных
инициализаторах: кандидаты симулируются в изоляции от работающего RmlUi.

Последовательность замены:

1. Компиляция кандидата, пока работает старый UI.
2. `[before_reload]`, снимки root/local state; затем simulation и проверка entry functions
   кандидата. Так глобальные `ui_state` получают самые свежие значения. Ошибка здесь
   сохраняет работающий UI. После успешной подготовки: `shutdown`, `on_unmount`, удаление DOM.
3. Завершение RmlUi, native elements/decorators/filters и их callback-ов **до** удаления
   старого daScript Context. SDL-окно и SDL renderer/GL context сохраняются.
4. `[after_reload]`, `init` и первый `update` кандидата, включая локальные миграции.
5. При успехе старый Context удаляется, `get_reload_generation()` увеличивается.
   При отказе migration/init/первого кадра кандидат удаляется, предыдущая программа
   повторно симулируется и восстанавливает снимок. При ошибке компиляции даже remount нет.

Первый пробный `update` ещё видит прежний generation. `[before_update]` вызывается
перед обычными кадрами. Как в LiveHost, `is_reload()` остаётся true после reload;
это не однокадровый флаг. На финальном `shutdown` он false. `get_last_error()`
возвращает последнюю ошибку host. `request_reset()` соответствует полному reload.
Произвольные внешние эффекты пользовательского `init/update/shutdown` не откатываются.
Ошибка обычного `update` завершает live runner с ненулевым кодом.

При code reload создаётся новый RmlUi Context: native registrations, публичные
DataModel и дополнительные документы нужно заново создавать в `init` из сохранённых
данных. Сырые native handles нельзя считать сохранённым состоянием. Режим renderer
нельзя менять внутри одной сессии. DOM, фокус и анимации сохраняются при **style reload**;
code reload выполняет remount.

## Root и local state

```das
app=ui_state("workspace",1,App())

[ui_component]
def editor(id:int) {
    state("draft",2,Draft()) $(var draft:Draft) {
        // bind_value(...), обработчики, on_mount/on_unmount
    }
}
```

Краткие варианты: `ui_state("workspace",App())` и `state("draft",Draft())`, версия 1.
Существующие `ui_state(App())` и `state(Draft())` тоже сохраняются в live-режиме:
root получает ключ по исходному месту вызова, local — по месту объявления в компоненте.
Для редактируемого кода рекомендуются явные имена: перемещение строк root или вставка
безымянного state меняет автоматический ключ. Два одновременно живых root с одним
ключом отклоняются. Явные имена local должны быть уникальны внутри компонента.
У scalar local-значения блок принимает ссылку, например `$(var count:int&)`.

Полный local-ключ включает путь компонента и `each_keyed` key. Вставка другого
именованного local-state не сдвигает существующий. Переименование компонента,
изменение сигнатуры или identity его родителя меняет путь и создаёт новое состояние.
Обычный unmount удаляет сохранённое local-значение; удалённый и вновь добавленный item
не получает старый draft. `computed` не сохраняется — это производный кеш.
`on_mount` снова выполняется после восстановления: он может перезаписать данные,
поэтому начальные значения следует задавать в initializer, а не безусловно в hook.
Снимок делается **до** `on_unmount`; изменения в teardown в него не входят.

Значения сериализуются только на reload. В простое и при обычном `ui_edit` снимков
нет. Store содержит JSON, без ссылок на старый VM heap. Поддерживаются структуры,
массивы, таблицы, tuples, scalar/vector/enum и fixed arrays. Таблицы кодируются
массивом пар, сохраняя тип ключа; uint64 не проходит через float. Variants сохраняют
тип и проверяемый tag; изменение их схемы требует версии и миграции. Указатели и
callback-и не переносятся. Приложение может дополнительно использовать upstream
`var @live value=...` для независимых глобальных данных.

## Эволюция и миграции

При той же версии поля сопоставляются по имени: перестановка/удаление безопасны,
новые поля сохраняют initializer новой модели. Несовместимое изменение типа или
смысла требует увеличения версии. Например, переименование `text` в `note`:

```das
struct Draft { note:string=""; clicks:int }

def ui_migrate(saved:JsonValue const?; old_version:int; var value:Draft):bool {
    if (old_version!=1) { return false }
    value.note=saved?["text"] ?? value.note
    value.clicks=saved?["clicks"] ?? 0
    return true
}
// state("draft",2,Draft()) ...
```

Тот же overload применяется к root и local соответствующего типа. `value` уже
содержит новые defaults; `saved` — данные старой версии. `false` или исключение
отклоняет candidate. При отсутствии подходящего overload несовпадение версий тоже
отклоняется. Для намеренного сброса выполните full reload. Снимки существуют только
в текущем процессе: это не сохранение на диск и не формат пользовательских файлов.

## Стили без remount

В компоненте используется `use_live_style("studio")`. Независимый файл стилей:

```das
require dasrmlui/ui
[ui_style(name="studio")]
def theme() {
    rule(part("card")) { background(rgb(237,224,239)); padding(px(20)) }
}
[export]
def live_styles():string { return ui_style_sheet() { theme() } }
```

`--styles` компилирует этот entry отдельно и получает RCSS через тот же DSL.
Именованная область обеспечивает одинаковые selectors без импорта styles-файла
в component script. Правила добавляются после обычных компонентных стилей и
сохраняются при последующих ui_frame. Обновление используют и дополнительные DSL
документы. Компиляционные ошибки, ошибки выполнения и RCSS warnings сохраняют
предыдущий stylesheet. Сам styles entry не может обращаться к native RmlUi:
регистрации custom decorators/shaders нужно выполнять в основном `init`.

Изменение общей зависимости обоих entry вызывает code reload. Автоматическое
распознавание `[ui_style]` среди произвольных изменений общего component-файла не
выполняется: для пути без remount нужен отдельный `--styles` entry. Текстуры, SVG,
Lottie и внешние ресурсы не включены в этот watcher.

## Проверки

```powershell
ctest --test-dir build -R 'live_|demo_live' --output-on-failure
```

`live_reload`: root/local/keyed state, @live, full reset, GC, native teardown и SDL
window identity. `live_state_codec`: контейнеры, типы и эволюция полей. `live_watch`:
реальное изменение файлов, DOM/focus, отказ RCSS/компиляции, откат локальной миграции,
затем успешные root/local миграции с вставкой нового state. `live_gl`: GL3 reload.
`demo_live_lab`: smoke полного примера. `live_errors`: диагностика и ненулевой exit
при ошибках shutdown/native paint. Изменяемые fixtures пишутся только под `build/`.
