# RmlUi's dependency discovery should reuse our pinned in-tree target.
if(TARGET rlottie::rlottie)
  set(rlottie_FOUND TRUE)
  set(rlottie_VERSION "0.2")
else()
  find_package(rlottie CONFIG REQUIRED)
endif()
