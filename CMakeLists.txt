cmake_minimum_required(VERSION 3.24)
# project() fills in a platform default, so note first whether one was asked for.
if(NOT DEFINED CMAKE_BUILD_TYPE)
  set(DASRMLUI_BUILD_TYPE_UNSET TRUE)
endif()
project(dasrmlui LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
# Locates the dasSDL3 build, checks that this configuration can link it and
# defines the dependency variables used below.
include(cmake/dependencies.cmake)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(RMLUI_SAMPLES OFF CACHE BOOL "" FORCE)
set(RMLUI_PRECOMPILED_HEADERS OFF CACHE BOOL "" FORCE)
set(RMLUI_THIRDPARTY_CONTAINERS OFF CACHE BOOL "" FORCE)
include(cmake/vector_plugins.cmake)
add_subdirectory(${RMLUI_DIR} ${CMAKE_BINARY_DIR}/rmlui EXCLUDE_FROM_ALL)
add_executable(dasrmlui src/host.cpp src/rml_module.cpp ${RMLUI_DIR}/Backends/RmlUi_Platform_SDL.cpp
  src/gl3/RmlUi_Renderer_GL3.cpp)
target_include_directories(dasrmlui PRIVATE
  ${RMLUI_DIR}/Source/Core
  ${DASSDL3_DIR}/src ${DAS}/include ${DAS}/3rdparty/fmt/include
  ${DAS}/3rdparty/uriparser/include ${DASSDL3_BUILD}/third_party/daScript/include
  ${DS_FETCHCONTENT_SOURCE_DIR_SDL3}/include ${DASSDL3_BUILD}/_deps/sdl3-build/include-revision
  ${RMLUI_DIR}/Backends)
target_compile_definitions(dasrmlui PRIVATE
  DAS_ENABLE_DYN_INCLUDES=1 DAS_ENABLE_EXCEPTIONS=1 DAS_FUSION=2 DAS_NO_ASSERTIONS
  URIPARSER_BUILD_CHAR URI_STATIC_BUILD RMLUI_SDL_VERSION_MAJOR=3)
# A development build falls back to the tree it was built from. A packaged build
# turns this off and records no absolute path: the host then takes its script
# folders and font from beside the executable or from DASRMLUI_HOME.
option(DASRMLUI_DEV_PATHS "Fall back to this source tree for scripts, examples and the default font" ON)
if(DASRMLUI_DEV_PATHS)
  target_compile_definitions(dasrmlui PRIVATE
    DAS_ROOT="${DAS}" SDL_MODULE_ROOT="${DASSDL3_DIR}/dassdl3"
    UI_MODULE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/dasrmlui"
    EXAMPLES_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/examples"
    RMLUI_FONT="${RMLUI_DIR}/Samples/assets/LatoLatin-Regular.ttf")
endif()
if(MSVC)
  target_compile_options(dasrmlui PRIVATE /bigobj /utf-8)
endif()
target_link_libraries(dasrmlui PRIVATE RmlUi::RmlUi RmlUi::Debugger
  ${DASRMLUI_DASSDL3_LIBRARY} ${DASRMLUI_DASCRIPT_LIBRARIES} SDL3::SDL3-static ${DASRMLUI_SYSTEM_LIBRARIES})
set_target_properties(dasrmlui PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
include(cmake/package.cmake)

# Isolated measurement runner: the normal application has no allocation interposer
# and no benchmark-only APIs. The hybrid adapter uses pinned RmlUi internals.
option(DASRMLUI_BUILD_BENCHMARKS "Build DSL/native data binding benchmark" OFF)
if(DASRMLUI_BUILD_BENCHMARKS)
  add_executable(dasrmlui_bench src/host.cpp src/rml_module.cpp src/benchmark_alloc.cpp
    ${RMLUI_DIR}/Backends/RmlUi_Platform_SDL.cpp src/gl3/RmlUi_Renderer_GL3.cpp)
  foreach(prop INCLUDE_DIRECTORIES COMPILE_DEFINITIONS COMPILE_OPTIONS LINK_LIBRARIES)
    get_target_property(value dasrmlui ${prop})
    if(value)
      set_property(TARGET dasrmlui_bench PROPERTY ${prop} "${value}")
    endif()
  endforeach()
  target_include_directories(dasrmlui_bench PRIVATE ${RMLUI_DIR}/Source/Core ${DAS}/src/misc)
  target_compile_definitions(dasrmlui_bench PRIVATE DASRMLUI_BENCHMARK=1)
  set_target_properties(dasrmlui_bench PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
endif()
enable_testing()
if(DASRMLUI_BUILD_BENCHMARKS)
  add_test(NAME binding_benchmark_smoke COMMAND dasrmlui_bench ${CMAKE_SOURCE_DIR}/benchmarks/bindings.das --smoke-test)
  set_tests_properties(binding_benchmark_smoke PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    ENVIRONMENT "SDL_VIDEODRIVER=windows" LABELS "benchmark;graphics;opengl" RUN_SERIAL TRUE TIMEOUT 120)
endif()
add_test(NAME runtime COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/tests/runtime.das --smoke-test)
set_tests_properties(runtime PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
add_test(NAME component_macro COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/tests/macros_probe.das --smoke-test)
add_test(NAME incremental COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/tests/incremental.das --smoke-test)
set_tests_properties(incremental PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
add_test(NAME bindings COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/tests/bindings.das --smoke-test)
set_tests_properties(bindings PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
foreach(feature lifecycle composition viewport forms templates template_slots animations style_environment events documents regressions navigation debugger vector_plugins native_elements native_safety gpu_backend hybrid hybrid_lifecycle rich_text state_api data_models native_data_dsl)
  add_test(NAME ${feature} COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/tests/${feature}.das --smoke-test)
  set_tests_properties(${feature} PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
endforeach()
foreach(demo dashboard settings kanban catalog component_lab expedition drag_drop templates localization event_studio navigation_lab rich_text_lab data_models)
  add_test(NAME demo_${demo} COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/examples/${demo}.das --smoke-test)
  set_tests_properties(demo_${demo} PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
endforeach()
foreach(demo effects progress_lab animations style_lab vector_lab native_lab mesh_lab decorator_lab shader_lab)
  add_test(NAME demo_${demo} COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/examples/${demo}.das --smoke-test)
  # SDL dummy has no OpenGL context. These tests need the Windows desktop driver
  # and a real GL3 renderer, even though their windows are hidden.
  set_tests_properties(demo_${demo} PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    ENVIRONMENT "SDL_VIDEODRIVER=windows" LABELS "graphics;opengl" RUN_SERIAL TRUE TIMEOUT 60)
endforeach()
find_program(DASRML_POWERSHELL NAMES pwsh powershell REQUIRED)
add_test(NAME data_model_type_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_data_model_type.das -Expected "DataModel supports scalar values, structs and arrays")
set_tests_properties(data_model_type_error PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
function(native_data_failure name expected)
  add_test(NAME native_data_${name}_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
    -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_native_data_${name}.das -Expected "${expected}")
  set_tests_properties(native_data_${name}_error PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
endfunction()
native_data_failure(capture "native_data arguments must be constant")
native_data_failure(managed "native_data does not support when")
native_data_failure(nested "native_data scopes cannot be nested")
native_data_failure(scope "data_* bindings require native_data")
function(state_failure name expected)
  add_test(NAME state_${name}_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
    -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_state_${name}.das -Expected "${expected}")
  set_tests_properties(state_${name}_error PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
endfunction()
state_failure(read "can't write to a constant value")
state_failure(private "can't access private field 'data'")
state_failure(pointer "ui_state cannot own borrowed pointers or closures")
state_failure(frame "ui_frame/ui_edit require ui_state and a model block")
state_failure(scalar "ui_state requires a model struct")
add_test(NAME rich_text_syntax_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_rich_text.das -Expected "link requires name, target")
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
add_test(NAME smoke_warning_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_smoke_warning.das -Expected "smoke run: RmlUi reported")
set_tests_properties(smoke_warning_error PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
# Installs the runtime component into <build>/package and runs it from there.
add_test(NAME runtime_package COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/check_package.ps1
  -Build ${CMAKE_BINARY_DIR} -Config $<CONFIG>)
set_tests_properties(runtime_package PROPERTIES RUN_SERIAL TRUE TIMEOUT 180 LABELS "graphics;opengl")
# State classes, pseudo-classes and arbitrary tags.
add_test(NAME elements COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/tests/elements.das --smoke-test)
set_tests_properties(elements PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
# The typed style helpers: what they write, a wrong argument type, a wrong keyword.
add_test(NAME style_helpers COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/tests/style_helpers.das --smoke-test)
set_tests_properties(style_helpers PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
add_test(NAME style_helper_type_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_style_helper.das -Expected "no matching functions or generics: border_radius(ui::UiColor)")
add_test(NAME style_keyword_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_position.das -Expected "position: use static, relative, absolute or fixed")
# Fast-path coverage: by-value component arguments and computed primitive arguments.
add_test(NAME hybrid_arguments COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/tests/hybrid_arguments.das --smoke-test)
set_tests_properties(hybrid_arguments PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
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
add_test(NAME native_host_lifetime COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/check_native_host.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/native_host_lifetime.das)
set_tests_properties(native_host_lifetime PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
add_test(NAME native_pixels COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/check_native_pixels.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/native_render.das)
set_tests_properties(native_pixels PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
  ENVIRONMENT "SDL_VIDEODRIVER=windows" LABELS "graphics;sdl" RUN_SERIAL TRUE TIMEOUT 60)
add_test(NAME native_mesh_pixels COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/check_native_mesh.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/native_mesh.das)
set_tests_properties(native_mesh_pixels PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
  ENVIRONMENT "SDL_VIDEODRIVER=windows" LABELS "graphics;sdl;opengl" RUN_SERIAL TRUE TIMEOUT 60)
add_test(NAME decorator_pixels COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/check_decorators.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/decorators.das)
set_tests_properties(decorator_pixels PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
  ENVIRONMENT "SDL_VIDEODRIVER=windows" LABELS "graphics;sdl;opengl" RUN_SERIAL TRUE TIMEOUT 60)
add_test(NAME decorator_host_lifetime COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/check_decorator_host.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/decorator_host_lifetime.das)
set_tests_properties(decorator_host_lifetime PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} ENVIRONMENT "SDL_VIDEODRIVER=dummy")
add_test(NAME gpu_effect_pixels COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/check_gpu_effects.ps1
  -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/gpu_effects.das)
set_tests_properties(gpu_effect_pixels PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
  ENVIRONMENT "SDL_VIDEODRIVER=windows" LABELS "graphics;opengl" RUN_SERIAL TRUE TIMEOUT 60)
add_test(NAME shader_dsl_compiler COMMAND dasrmlui ${CMAKE_SOURCE_DIR}/tests/shader_dsl_probe.das --smoke-test)
set_tests_properties(shader_dsl_compiler PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
function(shader_dsl_failure name expected)
  add_test(NAME shader_dsl_${name}_error COMMAND ${DASRML_POWERSHELL} -NoProfile -File ${CMAKE_SOURCE_DIR}/tools/expect_failure.ps1
    -Runner $<TARGET_FILE:dasrmlui> -Script ${CMAKE_SOURCE_DIR}/tests/bad_shader_${name}.das -Expected "${expected}")
  set_tests_properties(shader_dsl_${name}_error PROPERTIES WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
endfunction()
shader_dsl_failure(return "must return float4")
shader_dsl_failure(param "parameters must be float")
shader_dsl_failure(builtin "uv/size/texel must be float2")
shader_dsl_failure(capture "cannot capture mutable CPU globals")
shader_dsl_failure(sampling "sample_source is only available in [ui_filter]")
shader_dsl_failure(cpu "dasGlsl:")
shader_dsl_failure(mutable "must be read-only, without defaults")
shader_dsl_failure(default "must be read-only, without defaults")
