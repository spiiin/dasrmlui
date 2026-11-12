cmake_minimum_required(VERSION 3.24)
project(dasrmlui LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
if(NOT CMAKE_BUILD_TYPE STREQUAL "Release")
  message(FATAL_ERROR "Use Release: this profile links an existing Release /MD dasSDL3 build")
endif()
if(NOT MSVC)
  message(FATAL_ERROR "This initial build profile consumes an MSVC Release dasSDL3 build")
endif()
set(DASSDL3_DIR "C:/src/dasSDL3" CACHE PATH "dasSDL3 checkout")
set(DASSDL3_BUILD "${DASSDL3_DIR}/build/ninja" CACHE PATH "Matching Release build")
set(RMLUI_DIR "C:/src/dascript_sdl_gui/third_party/RmlUi" CACHE PATH "RmlUi source checkout")
set(DAS "${DASSDL3_DIR}/third_party/daScript")
load_cache(${DASSDL3_BUILD} READ_WITH_PREFIX DS_ FETCHCONTENT_SOURCE_DIR_SDL3 FETCHCONTENT_SOURCE_DIR_FREETYPE_SRC)
set(FREETYPE_INCLUDE_DIR_ft2build "${DS_FETCHCONTENT_SOURCE_DIR_FREETYPE_SRC}/include" CACHE PATH "" FORCE)
set(FREETYPE_INCLUDE_DIR_freetype2 "${DS_FETCHCONTENT_SOURCE_DIR_FREETYPE_SRC}/include" CACHE PATH "" FORCE)
set(FREETYPE_LIBRARY "${DAS}/lib/freetype.lib" CACHE FILEPATH "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(RMLUI_SAMPLES OFF CACHE BOOL "" FORCE)
set(RMLUI_PRECOMPILED_HEADERS OFF CACHE BOOL "" FORCE)
set(RMLUI_THIRDPARTY_CONTAINERS OFF CACHE BOOL "" FORCE)
include(cmake/vector_plugins.cmake)
add_subdirectory(${RMLUI_DIR} ${CMAKE_BINARY_DIR}/rmlui EXCLUDE_FROM_ALL)
add_executable(dasrmlui src/host.cpp src/rml_module.cpp ${RMLUI_DIR}/Backends/RmlUi_Platform_SDL.cpp
  ${RMLUI_DIR}/Backends/RmlUi_Renderer_GL3.cpp)
target_include_directories(dasrmlui PRIVATE
  ${DASSDL3_DIR}/src ${DAS}/include ${DAS}/3rdparty/fmt/include
  ${DAS}/3rdparty/uriparser/include ${DASSDL3_BUILD}/third_party/daScript/include
  ${DS_FETCHCONTENT_SOURCE_DIR_SDL3}/include ${DASSDL3_BUILD}/_deps/sdl3-build/include-revision
  ${RMLUI_DIR}/Backends)
target_compile_definitions(dasrmlui PRIVATE
  DAS_ENABLE_DYN_INCLUDES=1 DAS_ENABLE_EXCEPTIONS=1 DAS_FUSION=2 DAS_NO_ASSERTIONS
  URIPARSER_BUILD_CHAR URI_STATIC_BUILD RMLUI_SDL_VERSION_MAJOR=3
  DAS_ROOT="${DAS}" SDL_MODULE_ROOT="${DASSDL3_DIR}/dassdl3"
  UI_MODULE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/dasrmlui"
  RMLUI_FONT="${RMLUI_DIR}/Samples/assets/LatoLatin-Regular.ttf")
target_compile_options(dasrmlui PRIVATE /bigobj /utf-8)
target_link_libraries(dasrmlui PRIVATE RmlUi::RmlUi RmlUi::Debugger
  ${DASSDL3_BUILD}/src/dasSDL3.lib
  ${DAS}/lib/libDaScript.lib ${DAS}/lib/libDaScript_runtime.lib ${DAS}/lib/libUriParser.lib
  ${DASSDL3_BUILD}/_deps/sdl3-build/SDL3-static.lib
  dbghelp ws2_32 mswsock rpcrt4 iphlpapi
  user32 gdi32 winmm imm32 ole32 oleaut32 version uuid advapi32 setupapi shell32 dinput8)
set_target_properties(dasrmlui PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
enable_testing()
add_test(NAME runtime COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/tests/runtime.das --smoke-test)
set_tests_properties(runtime PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
add_test(NAME component_macro COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/tests/macros_probe.das --smoke-test)
add_test(NAME incremental COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/tests/incremental.das --smoke-test)
set_tests_properties(incremental PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
add_test(NAME bindings COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/tests/bindings.das --smoke-test)
set_tests_properties(bindings PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
foreach(feature lifecycle composition viewport forms templates template_slots animations style_environment events documents regressions navigation debugger vector_plugins)
  add_test(NAME ${feature} COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/tests/${feature}.das --smoke-test)
  set_tests_properties(${feature} PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
endforeach()
foreach(demo dashboard settings kanban catalog component_lab expedition drag_drop templates localization event_studio navigation_lab)
  add_test(NAME demo_${demo} COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/examples/${demo}.das --smoke-test)
  set_tests_properties(demo_${demo} PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
endforeach()
foreach(demo effects progress_lab animations style_lab vector_lab)
  add_test(NAME demo_${demo} COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/examples/${demo}.das --smoke-test)
  # SDL dummy has no OpenGL context. These tests need the Windows desktop driver
  # and a real GL3 renderer, even though their windows are hidden.
  set_tests_properties(demo_${demo} PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    ENVIRONMENT "SDL_VIDEODRIVER=windows" LABELS "graphics;opengl" RUN_SERIAL TRUE TIMEOUT 60)
endforeach()
find_program(DASRML_POWERSHELL NAMES pwsh powershell REQUIRED)
add_test(NAME duplicate_keys COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/duplicate_keys.das -Expected "each_keyed: duplicate key")
add_test(NAME style_type_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_style.das -Expected "no matching functions or generics: width(ui::UiColor)")
set_tests_properties(duplicate_keys PROPERTIES ENVIRONMENT "SDL_VIDEODRIVER=dummy")
add_test(NAME template_static_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_template.das -Expected "[ui_template] is static; put when in [ui_component] content")
add_test(NAME template_duplicate COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/template_duplicate.das -Expected "[ui_template]: duplicate node name")
add_test(NAME template_missing_slot COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/template_missing_slot.das -Expected "document_content: missing target 'typo_slot'")
add_test(NAME template_not_slot COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/template_not_slot.das -Expected "target 'decoration' is not a declared template slot")
set_tests_properties(template_missing_slot template_not_slot PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
add_test(NAME template_empty_slot COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/template_empty_slot.das -Expected "slot requires a non-empty name")
add_test(NAME template_slot_children COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/template_slot_children.das -Expected "slot accepts styles/attributes")
add_test(NAME template_slot_duplicate COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/template_slot_duplicate.das -Expected "[ui_template]: duplicate node name")
add_test(NAME keyframe_order_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_keyframes.das -Expected "keyframes require increasing percentages")
add_test(NAME media_nested_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_media.das -Expected "nested media is not supported")
add_test(NAME media_negation_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_media_negation.das -Expected "Combine positive media queries first")
add_test(NAME atlas_resolution_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_atlas_resolution.das -Expected "Spritesheet resolution must be positive")
add_test(NAME navigation_id_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_navigation.das -Expected "Navigation ID must be non-empty, without # or whitespace")
add_test(NAME binding_arity_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_binding_arity.das -Expected "no matching functions or generics: bind_int")
add_test(NAME ninepatch_pixels COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/check_ninepatch.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/ninepatch_render.das)
set_tests_properties(ninepatch_pixels PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
  ENVIRONMENT "SDL_VIDEODRIVER=windows" LABELS "graphics;sdl" RUN_SERIAL TRUE TIMEOUT 60)
add_test(NAME svg_size_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_svg_size.das -Expected "Inline SVG viewport dimensions must be finite and positive")
add_test(NAME svg_decorator_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_svg_decorator.das -Expected "Invalid SVG decorator paint area")
add_test(NAME vector_pixels COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/check_vectors.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/vector_render.das)
set_tests_properties(vector_pixels PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
  ENVIRONMENT "SDL_VIDEODRIVER=windows" LABELS "graphics;sdl" RUN_SERIAL TRUE TIMEOUT 60)
