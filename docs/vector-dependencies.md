# Зависимости SVG/Lottie

`cmake/vector_plugins.cmake` включает официальные RmlUi plugins и статически собирает:

| Библиотека | Закреплённая ревизия | Лицензия |
|---|---|---|
| LunaSVG 3.2.1 | `f8aabfb444bb37f69df7290790f57e4a27730a93` | MIT |
| PlutoVG | submodule, закреплённый LunaSVG | MIT |
| Samsung rlottie | `ea06d2f29ba01b8d06c00a838d107f5e484ae59b` | MIT; сторонние файлы имеют собственные notices |

Первый `./tools/build.ps1` требует Git и сеть для FetchContent. Исходники, лицензии
и сборки сохраняются под `build/_deps`; существующие checkout RmlUi и dasSDL3 не
изменяются. При распространении бинарника сохраните LICENSE/COPYING и notices этих
зависимостей, включая вложенные third-party файлы rlottie.

`patch_rlottie.cmake` исправляет только полученную build-копию: поднимает минимальную
версию CMake с 3.3 до 3.15 и убирает навязанный `/MT`, чтобы все библиотеки использовали
один CRT `/MD`. `renderSync` работает без фоновых потоков; внешний image-loader DLL
отключён. Утилита lottie2gif не входит в обычную сборку.

Для offline configure можно передать `FETCHCONTENT_SOURCE_DIR_LUNASVG` (с заполненным
submodule PlutoVG) и `FETCHCONTENT_SOURCE_DIR_RLOTTIE`. CMake пропускает PATCH_COMMAND
при таком override: используйте подготовленную build-копию либо примените
`cmake -DSOURCE_DIR=<rlottie-copy> -P cmake/patch_rlottie.cmake` к отдельной копии заранее.

SVG/JSON из `examples/assets/vector_*` — оригинальные геометрические рисунки этого
проекта. Они воспроизводятся `python tools/make_vector_assets.py` и не требуют
скачивания чужих иллюстраций. Probe assets предназначены для детерминированных tests;
flower/orbit/motion/pulse — для интерактивного примера.

Native API: [SVG](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/svg.html),
[Lottie](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/lottie.html).
