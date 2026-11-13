cmake_minimum_required(VERSION 3.24)
project(dasrmlui_web LANGUAGES C CXX)
if(NOT EMSCRIPTEN)
  message(FATAL_ERROR "Use emcmake; see docs/web.md")
endif()
set(CMAKE_CXX_STANDARD 17)
if(NOT EMSCRIPTEN_VERSION VERSION_EQUAL "5.0.3")
  message(FATAL_ERROR "Use Emscripten 5.0.3 to match the dasSDL3 Web profile")
endif()
get_filename_component(ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
get_filename_component(NEIGHBOURS "${ROOT}/.." ABSOLUTE)
set(DASSDL3_DIR "${NEIGHBOURS}/dasSDL3" CACHE PATH "dasSDL3 checkout")
set(DASSDL3_WEB_BUILD "${DASSDL3_DIR}/build/web" CACHE PATH "Matching Emscripten dasSDL3 build")
set(DAS "${DASSDL3_DIR}/third_party/daScript")
set(RMLUI_DIR "${NEIGHBOURS}/RmlUi" CACHE PATH "Pinned RmlUi checkout")
set(FREETYPE_SOURCE "" CACHE PATH "FreeType source checkout")
add_compile_options(-msimd128 -mnontrapping-fptoint -fwasm-exceptions -sWASM_LEGACY_EXCEPTIONS=0)
add_link_options(-fwasm-exceptions -sWASM_LEGACY_EXCEPTIONS=0)
add_compile_definitions(DAS_ENABLE_EXCEPTIONS=1 _EMSCRIPTEN_VER)
foreach(feature FLEX_BISON CLANG_BIND LLVM SMT HV GLFW IMGUI VULKAN AUDIO STDDLG
    MESHOPTIMIZER STBIMAGE METAL ACCELERATE CLIPBOARD PUGIXML SQLITE CRYPTO TREE_SITTER
    TERMINAL AOT_EXAMPLES TUTORIAL TESTS TOOLS)
  set(DAS_${feature}_DISABLED ON CACHE BOOL "Minimal Web runtime" FORCE)
endforeach()
add_subdirectory("${DAS}" dascript EXCLUDE_FROM_ALL)
# Keep all generated archives/binaries inside this build, never the shared SDK.
function(isolate_das_outputs dir)
  get_property(targets DIRECTORY "${dir}" PROPERTY BUILDSYSTEM_TARGETS)
  foreach(t IN LISTS targets)
    set_target_properties(${t} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
      LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib" RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tools")
  endforeach()
  get_property(children DIRECTORY "${dir}" PROPERTY SUBDIRECTORIES)
  foreach(child IN LISTS children)
    isolate_das_outputs("${child}")
  endforeach()
endfunction()
isolate_das_outputs("${DAS}")
set(SDL3_SOURCE "" CACHE PATH "Optional SDL3 source tree for a self-contained Web build")
if(SDL3_SOURCE)
  set(SDL_SHARED OFF CACHE BOOL "" FORCE)
  set(SDL_STATIC ON CACHE BOOL "" FORCE)
  set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
  set(SDL_TESTS OFF CACHE BOOL "" FORCE)
  add_subdirectory("${SDL3_SOURCE}" sdl3 EXCLUDE_FROM_ALL)
else()
  find_package(SDL3 CONFIG REQUIRED PATHS "${DASSDL3_WEB_BUILD}/_deps/sdl3-build" NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH)
endif()
set(FT_DISABLE_ZLIB ON CACHE BOOL "" FORCE)
set(FT_DISABLE_BZIP2 ON CACHE BOOL "" FORCE)
set(FT_DISABLE_PNG ON CACHE BOOL "" FORCE)
set(FT_DISABLE_HARFBUZZ ON CACHE BOOL "" FORCE)
set(FT_DISABLE_BROTLI ON CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
add_subdirectory("${FREETYPE_SOURCE}" freetype EXCLUDE_FROM_ALL)
add_library(Freetype::Freetype ALIAS freetype)
set(FREETYPE_INCLUDE_DIR_ft2build "${FREETYPE_SOURCE}/include" CACHE PATH "" FORCE)
set(FREETYPE_INCLUDE_DIR_freetype2 "${FREETYPE_SOURCE}/include" CACHE PATH "" FORCE)
set(FREETYPE_LIBRARY freetype CACHE STRING "" FORCE)
include("${ROOT}/cmake/vector_plugins.cmake")
# rlottie publishes ELF-only flags, which wasm-ld cannot accept.
get_target_property(LOTTIE_LINK_OPTIONS rlottie INTERFACE_LINK_OPTIONS)
if(LOTTIE_LINK_OPTIONS)
  list(FILTER LOTTIE_LINK_OPTIONS EXCLUDE REGEX "no-undefined|version-script")
  set_property(TARGET rlottie PROPERTY INTERFACE_LINK_OPTIONS "${LOTTIE_LINK_OPTIONS}")
endif()
get_target_property(LOTTIE_LINK_LIBRARIES rlottie INTERFACE_LINK_LIBRARIES)
if(LOTTIE_LINK_LIBRARIES)
  list(FILTER LOTTIE_LINK_LIBRARIES EXCLUDE REGEX "no-undefined|version-script")
  set_property(TARGET rlottie PROPERTY INTERFACE_LINK_LIBRARIES "${LOTTIE_LINK_LIBRARIES}")
endif()
set(RMLUI_SAMPLES OFF CACHE BOOL "" FORCE)
set(RMLUI_THIRDPARTY_CONTAINERS OFF CACHE BOOL "" FORCE)
set(RMLUI_PRECOMPILED_HEADERS OFF CACHE BOOL "" FORCE)
add_subdirectory("${RMLUI_DIR}" rmlui EXCLUDE_FROM_ALL)
add_executable(dasrmlui_web "${ROOT}/src/host.cpp" "${ROOT}/src/live_host.cpp"
  "${ROOT}/src/rml_module.cpp" "${ROOT}/src/gl3/RmlUi_Renderer_GL3.cpp"
  "${RMLUI_DIR}/Backends/RmlUi_Platform_SDL.cpp" "${DASSDL3_DIR}/web/module_web.cpp"
  "${DAS}/modules/dasLiveHost/src/dasLiveHost.cpp")
target_compile_options(dasrmlui_web PRIVATE -fno-rtti)
target_include_directories(dasrmlui_web PRIVATE "${DAS}/include" "${DAS}/3rdparty/fmt/include"
  "${DAS}/3rdparty/uriparser/include" "${CMAKE_BINARY_DIR}/dascript/include"
  "${DAS}/modules/dasLiveHost/src" "${DASSDL3_DIR}/src" "${DASSDL3_DIR}/web"
  "${RMLUI_DIR}/Source/Core" "${RMLUI_DIR}/Backends")
target_compile_definitions(dasrmlui_web PRIVATE DAS_ENABLE_DYN_INCLUDES=1 DAS_FUSION=2 DAS_NO_ASSERTIONS
  URIPARSER_BUILD_CHAR URI_STATIC_BUILD RMLUI_SDL_VERSION_MAJOR=3
  DAS_ROOT="/daScript" SDL_MODULE_ROOT="/dassdl3" UI_MODULE_ROOT="/dasrmlui" EXAMPLES_ROOT="/examples"
  RMLUI_FONT="/assets/LatoLatin-Regular.ttf")
target_link_libraries(dasrmlui_web PRIVATE RmlUi::RmlUi RmlUi::Debugger SDL3::SDL3
  libDaScript)
set_target_properties(dasrmlui_web PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/site" SUFFIX ".js")
target_link_options(dasrmlui_web PRIVATE -O1 -sJSPI=1
  -sSTACK_SIZE=8MB -sINITIAL_MEMORY=256MB -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=2GB
  -sFULL_ES3=1 -sMIN_WEBGL_VERSION=2 -sMAX_WEBGL_VERSION=2 -sFORCE_FILESYSTEM=1
  -sMODULARIZE=1 -sEXPORT_NAME=createDasRmlUi -sINVOKE_RUN=0 -sEXIT_RUNTIME=0
  "-sEXPORTED_FUNCTIONS=['_main','_rui_web_stop']"
  "-sEXPORTED_RUNTIME_METHODS=['callMain','FS']"
  "SHELL:--preload-file ${CMAKE_BINARY_DIR}/preload@/"
  "SHELL:--exclude-file */_aot_generated/*" "SHELL:--exclude-file */.jitted_scripts/*")
if(CMAKE_HOST_WIN32)
  add_custom_command(TARGET dasrmlui_web POST_BUILD COMMAND icacls "$<TARGET_FILE:dasrmlui_web>" /reset VERBATIM)
endif()

file(GLOB_RECURSE WEB_PRELOAD CONFIGURE_DEPENDS "${CMAKE_BINARY_DIR}/preload/*")
set_property(TARGET dasrmlui_web APPEND PROPERTY LINK_DEPENDS ${WEB_PRELOAD})
