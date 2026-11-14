# A self-contained runtime folder: the binary, the script folders it loads and
# the default font with its licence.
#
#   cmake --install <build> --component runtime --prefix <dir>
#
# The host looks for these folders beside the executable before anything else,
# so the result runs from wherever it is copied. Configure with
# -DDASRMLUI_DEV_PATHS=OFF to leave the build tree's paths out of the binary.
# The layout is the one src/host.cpp expects:
#   bin/dasrmlui(.exe)   daScript/daslib   dassdl3   dasrmlui   examples   assets
install(TARGETS dasrmlui RUNTIME DESTINATION bin COMPONENT runtime)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE" DESTINATION licenses RENAME dasrmlui-LICENSE.txt COMPONENT runtime)
install(DIRECTORY "${DAS}/daslib" DESTINATION daScript COMPONENT runtime)
install(DIRECTORY "${DAS}/modules/dasGlsl/glsl" DESTINATION daScript/modules/dasGlsl COMPONENT runtime)
install(FILES "${DAS}/LICENSE" DESTINATION licenses RENAME daScript-LICENSE.txt COMPONENT runtime)
install(DIRECTORY "${DASSDL3_DIR}/dassdl3" DESTINATION . COMPONENT runtime)
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/dasrmlui" "${CMAKE_CURRENT_SOURCE_DIR}/examples"
  DESTINATION . COMPONENT runtime)
install(FILES "${RMLUI_DIR}/Samples/assets/LatoLatin-Regular.ttf"
  "${RMLUI_DIR}/Samples/assets/LatoLatin-Bold.ttf" "${RMLUI_DIR}/Samples/assets/LatoLatin-Italic.ttf"
  "${RMLUI_DIR}/Samples/assets/LatoLatin-BoldItalic.ttf" DESTINATION assets COMPONENT runtime)
install(FILES "${RMLUI_DIR}/Samples/assets/LICENSE.txt" DESTINATION assets
  RENAME LatoLatin-LICENSE.txt COMPONENT runtime)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/web/assets/DejaVuSans.ttf"
  DESTINATION web/assets COMPONENT runtime)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/web/assets/LICENSE-DejaVuSans.ttf.txt" DESTINATION licenses
  RENAME DejaVuSans-LICENSE.txt COMPONENT runtime)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/src/gl3/LICENSE.txt" DESTINATION licenses
  RENAME RmlUi-GL3-LICENSE.txt COMPONENT runtime)

install(DIRECTORY "${DAS}/modules/dasLiveHost/live" DESTINATION daScript/modules/dasLiveHost COMPONENT runtime)
