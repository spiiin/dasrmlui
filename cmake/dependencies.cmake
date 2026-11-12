# dasrmlui links the daScript, dasSDL3 and SDL3 libraries of an existing dasSDL3
# build as they are. This file locates that build, checks that the requested
# configuration can link against it, and defines:
#   DAS                           daScript source tree
#   DASRMLUI_DASSDL3_LIBRARY      dasSDL3 static library
#   DASRMLUI_DASCRIPT_LIBRARIES   daScript static libraries, in link order
#   DASRMLUI_SYSTEM_LIBRARIES     what daScript itself needs from the system
#   SDL3::SDL3-static             SDL3, with its own system libraries attached
set(DASSDL3_DIR "C:/src/dasSDL3" CACHE PATH "dasSDL3 checkout")
set(DASSDL3_BUILD "${DASSDL3_DIR}/build/ninja" CACHE PATH "dasSDL3 build made with this toolchain")
set(RMLUI_DIR "C:/src/dascript_sdl_gui/third_party/RmlUi" CACHE PATH "RmlUi source checkout")
set(DAS "${DASSDL3_DIR}/third_party/daScript")
if(NOT EXISTS "${DASSDL3_BUILD}/CMakeCache.txt")
  message(FATAL_ERROR "DASSDL3_BUILD=${DASSDL3_BUILD} is not a configured dasSDL3 build. "
    "Build dasSDL3 with this toolchain first, then set DASSDL3_DIR and DASSDL3_BUILD.")
endif()
load_cache(${DASSDL3_BUILD} READ_WITH_PREFIX DS_
  CMAKE_BUILD_TYPE FETCHCONTENT_SOURCE_DIR_SDL3 FETCHCONTENT_SOURCE_DIR_FREETYPE_SRC)

# A debug build changes two things the prebuilt libraries were compiled with: the
# C runtime and the daScript build id. Release, RelWithDebInfo and MinSizeRel
# agree with one another on both; Debug agrees only with a Debug dasSDL3 build.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
if(DS_CMAKE_BUILD_TYPE STREQUAL "Debug")
  set(DASRMLUI_CONFIGURATIONS Debug)
else()
  set(DASRMLUI_CONFIGURATIONS Release RelWithDebInfo MinSizeRel)
endif()
get_property(DASRMLUI_MULTI_CONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(DASRMLUI_MULTI_CONFIG)
  set(CMAKE_CONFIGURATION_TYPES ${DASRMLUI_CONFIGURATIONS} CACHE STRING
    "Configurations that can link the dasSDL3 build" FORCE)
else()
  # With no build type requested, take one that links instead of the platform default.
  if(DASRMLUI_BUILD_TYPE_UNSET OR NOT CMAKE_BUILD_TYPE)
    list(GET DASRMLUI_CONFIGURATIONS 0 DASRMLUI_DEFAULT_CONFIGURATION)
    set(CMAKE_BUILD_TYPE ${DASRMLUI_DEFAULT_CONFIGURATION} CACHE STRING "Build type" FORCE)
  endif()
  if(NOT CMAKE_BUILD_TYPE IN_LIST DASRMLUI_CONFIGURATIONS)
    list(JOIN DASRMLUI_CONFIGURATIONS ", " DASRMLUI_CONFIGURATION_LIST)
    message(FATAL_ERROR "CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} cannot link the dasSDL3 build at "
      "${DASSDL3_BUILD}, which was configured as '${DS_CMAKE_BUILD_TYPE}'. "
      "Use ${DASRMLUI_CONFIGURATION_LIST}, or point DASSDL3_BUILD at a matching build.")
  endif()
endif()

# Library file names follow the toolchain. daScript gives its targets a "lib"
# prefix of their own, hence liblibDaScript.a outside MSVC.
set(DASRMLUI_LIB_PREFIX "${CMAKE_STATIC_LIBRARY_PREFIX}")
set(DASRMLUI_LIB_SUFFIX "${CMAKE_STATIC_LIBRARY_SUFFIX}")
set(DASRMLUI_DASSDL3_LIBRARY "${DASSDL3_BUILD}/src/${DASRMLUI_LIB_PREFIX}dasSDL3${DASRMLUI_LIB_SUFFIX}")
set(DASRMLUI_DASCRIPT_LIBRARIES
  "${DAS}/lib/${DASRMLUI_LIB_PREFIX}libDaScript${DASRMLUI_LIB_SUFFIX}"
  "${DAS}/lib/${DASRMLUI_LIB_PREFIX}libDaScript_runtime${DASRMLUI_LIB_SUFFIX}"
  "${DAS}/lib/${DASRMLUI_LIB_PREFIX}libUriParser${DASRMLUI_LIB_SUFFIX}")
set(DASRMLUI_FREETYPE_LIBRARY "${DAS}/lib/${DASRMLUI_LIB_PREFIX}freetype${DASRMLUI_LIB_SUFFIX}")
foreach(DASRMLUI_LIBRARY ${DASRMLUI_DASSDL3_LIBRARY} ${DASRMLUI_DASCRIPT_LIBRARIES} ${DASRMLUI_FREETYPE_LIBRARY})
  if(NOT EXISTS "${DASRMLUI_LIBRARY}")
    message(FATAL_ERROR "Missing ${DASRMLUI_LIBRARY}. dasrmlui links a dasSDL3 build made with the "
      "same toolchain; build it, then set DASSDL3_DIR and DASSDL3_BUILD.")
  endif()
endforeach()

# SDL3's own package carries the include paths and the per-platform system
# libraries, so none of them are listed by hand here.
find_package(SDL3 CONFIG REQUIRED PATHS "${DASSDL3_BUILD}/_deps/sdl3-build" NO_DEFAULT_PATH)
if(WIN32)
  set(DASRMLUI_SYSTEM_LIBRARIES dbghelp ws2_32 mswsock rpcrt4 iphlpapi)
else()
  find_package(Threads REQUIRED)
  set(DASRMLUI_SYSTEM_LIBRARIES Threads::Threads ${CMAKE_DL_LIBS})
endif()

# RmlUi is built from source here and takes FreeType from the same build.
set(FREETYPE_INCLUDE_DIR_ft2build "${DS_FETCHCONTENT_SOURCE_DIR_FREETYPE_SRC}/include" CACHE PATH "" FORCE)
set(FREETYPE_INCLUDE_DIR_freetype2 "${DS_FETCHCONTENT_SOURCE_DIR_FREETYPE_SRC}/include" CACHE PATH "" FORCE)
set(FREETYPE_LIBRARY "${DASRMLUI_FREETYPE_LIBRARY}" CACHE FILEPATH "" FORCE)
