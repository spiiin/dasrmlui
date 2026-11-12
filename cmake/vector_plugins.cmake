include(FetchContent)

# Reproducible sources for the official RmlUi plugins. Downloads and builds stay
# under build/_deps; FETCHCONTENT_SOURCE_DIR_* can point at offline checkouts.
set(LUNASVG_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(PLUTOVG_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LOTTIE_MODULE OFF CACHE BOOL "No external image-loader DLL" FORCE)
set(LOTTIE_THREAD OFF CACHE BOOL "RmlUi uses renderSync" FORCE)
set(LOTTIE_TEST OFF CACHE BOOL "" FORCE)
set(LOTTIE_CACHE ON CACHE BOOL "" FORCE)
set(CMAKE_EXPORT_PACKAGE_REGISTRY OFF)

FetchContent_Declare(lunasvg
  GIT_REPOSITORY https://github.com/sammycage/lunasvg.git
  GIT_TAG f8aabfb444bb37f69df7290790f57e4a27730a93 # v3.2.1, including pinned PlutoVG submodule
  GIT_SUBMODULES plutovg
  GIT_SUBMODULES_RECURSE TRUE)
FetchContent_Declare(rlottie
  GIT_REPOSITORY https://github.com/Samsung/rlottie.git
  GIT_TAG ea06d2f29ba01b8d06c00a838d107f5e484ae59b
  PATCH_COMMAND ${CMAKE_COMMAND} -DSOURCE_DIR=<SOURCE_DIR> -P ${CMAKE_CURRENT_LIST_DIR}/patch_rlottie.cmake)
FetchContent_MakeAvailable(lunasvg rlottie)
if(TARGET lottie2gif)
  set_target_properties(lottie2gif PROPERTIES EXCLUDE_FROM_ALL TRUE)
endif()

list(PREPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/modules")
set(RMLUI_SVG_PLUGIN ON CACHE BOOL "Official SVG element and decorator" FORCE)
set(RMLUI_LOTTIE_PLUGIN ON CACHE BOOL "Official Lottie element" FORCE)
