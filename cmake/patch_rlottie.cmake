# Patch only the fetched, pinned build copy. This is idempotent and also works
# when CMake re-runs the FetchContent patch step. Keep /MD consistent with dasSDL3.
set(path "${SOURCE_DIR}/CMakeLists.txt")
file(READ "${path}" source)
string(REPLACE "cmake_minimum_required( VERSION 3.3 )" "cmake_minimum_required( VERSION 3.15 )" source "${source}")
string(REPLACE "    set(CMAKE_CXX_FLAGS_RELEASE \"\${CMAKE_CXX_FLAGS_RELEASE} /MT\")" "" source "${source}")
string(REPLACE "    set(CMAKE_CXX_FLAGS_DEBUG \"\${CMAKE_CXX_FLAGS_DEBUG} /MTd\")" "" source "${source}")
file(WRITE "${path}" "${source}")
