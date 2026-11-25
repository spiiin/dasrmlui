cmake_minimum_required(VERSION 3.24)
project(dasrmlui_ios VERSION 0.1.0 LANGUAGES C CXX)
if(NOT IOS OR NOT CMAKE_OSX_SYSROOT MATCHES "iphoneos")
  message(FATAL_ERROR "Configure with -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos")
endif()

get_filename_component(ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(DASSDL3_DIR "${ROOT}/../dasSDL3" CACHE PATH "dasSDL3 checkout with iOS support")
set(RMLUI_DIR "${ROOT}/../RmlUi" CACHE PATH "Pinned RmlUi checkout")
set(FREETYPE_SOURCE "" CACHE PATH "FreeType source tree")
set(DASRMLUI_IOS_BUNDLE_ID "org.dasrmlui.inventory" CACHE STRING "Application bundle identifier")
set(DASRMLUI_IOS_TEAM "" CACHE STRING "Apple development team for Xcode signing")
set(DAS "${DASSDL3_DIR}/third_party/daScript")

if(NOT EXISTS "${DASSDL3_DIR}/ios/bundle_scripts.h" OR NOT EXISTS "${DAS}/CMakeLists.txt")
  message(FATAL_ERROR "Use a dasSDL3 checkout with iOS support and initialize its daScript submodule")
endif()
if(NOT EXISTS "${FREETYPE_SOURCE}/CMakeLists.txt")
  message(FATAL_ERROR "Set FREETYPE_SOURCE to a FreeType checkout")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(BUILD_TESTING OFF CACHE BOOL "Build dependency tests")
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build static dependencies" FORCE)
add_compile_options($<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>)
add_subdirectory("${DASSDL3_DIR}" dassdl3 EXCLUDE_FROM_ALL)

foreach(dep ZLIB BZIP2 PNG HARFBUZZ BROTLI)
  set(FT_DISABLE_${dep} ON CACHE BOOL "Build standalone FreeType" FORCE)
endforeach()
add_subdirectory("${FREETYPE_SOURCE}" freetype EXCLUDE_FROM_ALL)
add_library(Freetype::Freetype ALIAS freetype)
set(FREETYPE_INCLUDE_DIR_ft2build "${FREETYPE_SOURCE}/include" CACHE PATH "" FORCE)
set(FREETYPE_INCLUDE_DIR_freetype2 "${FREETYPE_SOURCE}/include" CACHE PATH "" FORCE)
set(FREETYPE_LIBRARY freetype CACHE STRING "" FORCE)
set(RMLUI_SAMPLES OFF CACHE BOOL "" FORCE)
set(RMLUI_THIRDPARTY_CONTAINERS OFF CACHE BOOL "" FORCE)
set(RMLUI_PRECOMPILED_HEADERS OFF CACHE BOOL "" FORCE)
include("${ROOT}/cmake/vector_plugins.cmake")
add_subdirectory("${RMLUI_DIR}" rmlui EXCLUDE_FROM_ALL)
find_library(OPENGLES OpenGLES REQUIRED)

add_executable(dasrmlui_iphone MACOSX_BUNDLE runner.cpp "${ROOT}/src/live_host.cpp"
  "${DAS}/modules/dasLiveHost/src/dasLiveHost.cpp"
  "${ROOT}/src/rml_module.cpp" "${ROOT}/src/gl3/RmlUi_Renderer_GL3.cpp"
  "${RMLUI_DIR}/Backends/RmlUi_Platform_SDL.cpp")
target_include_directories(dasrmlui_iphone PRIVATE
  "${ROOT}/ios" "${ROOT}/src" "${DASSDL3_DIR}/ios" "${DAS}/modules/dasLiveHost/src"
  "${RMLUI_DIR}/Source/Core" "${RMLUI_DIR}/Backends")
target_compile_definitions(dasrmlui_iphone PRIVATE RMLUI_SDL_VERSION_MAJOR=3 DASRMLUI_IOS=1)
target_link_libraries(dasrmlui_iphone PRIVATE dasSDL3 RmlUi::RmlUi RmlUi::Debugger "${OPENGLES}")

set_target_properties(dasrmlui_iphone PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_LIST_DIR}/Info.plist.in"
  MACOSX_BUNDLE_GUI_IDENTIFIER "${DASRMLUI_IOS_BUNDLE_ID}"
  MACOSX_BUNDLE_BUNDLE_NAME "dasrmlui Examples"
  XCODE_GENERATE_SCHEME ON
  XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${DASRMLUI_IOS_BUNDLE_ID}"
  XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2")
if(DASRMLUI_IOS_TEAM)
  set_target_properties(dasrmlui_iphone PROPERTIES
    XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${DASRMLUI_IOS_TEAM}"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic)
endif()

function(bundle_resource file directory)
  target_sources(dasrmlui_iphone PRIVATE "${file}")
  set_source_files_properties("${file}" PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/${directory}")
endfunction()

function(bundle_scripts source directory)
  file(GLOB_RECURSE scripts RELATIVE "${source}" CONFIGURE_DEPENDS "${source}/*.das")
  foreach(script IN LISTS scripts)
    get_filename_component(subdir "${script}" DIRECTORY)
    bundle_resource("${source}/${script}" "${directory}/${subdir}")
  endforeach()
endfunction()

bundle_scripts("${DAS}/daslib" daslib)
bundle_scripts("${DASSDL3_DIR}/dassdl3" dassdl3)
bundle_scripts("${ROOT}/dasrmlui" dasrmlui)
bundle_scripts("${ROOT}/examples" examples)
bundle_scripts("${DAS}/modules/dasGlsl/glsl" modules/dasGlsl/glsl)
bundle_scripts("${DAS}/modules/dasLiveHost/live" modules/dasLiveHost/live)
file(GLOB example_assets CONFIGURE_DEPENDS "${ROOT}/examples/assets/*")
foreach(asset IN LISTS example_assets)
  bundle_resource("${asset}" examples/assets)
endforeach()
foreach(style Regular Bold Italic BoldItalic)
  bundle_resource("${RMLUI_DIR}/Samples/assets/LatoLatin-${style}.ttf" assets)
endforeach()
bundle_resource("${RMLUI_DIR}/Samples/assets/LICENSE.txt" licenses/Lato)
bundle_resource("${ROOT}/web/assets/DejaVuSans.ttf" web/assets)
bundle_resource("${ROOT}/web/assets/LICENSE-DejaVuSans.ttf.txt" licenses)
bundle_resource("${ROOT}/LICENSE" licenses/dasrmlui)
