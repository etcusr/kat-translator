# Optional voice engine compiled separately to isolate its pinned ggml ABI.
if(NOT EXISTS "${KAT_ROOT}/.build/android-media/omnivoice/libkat_omnivoice.so")
 message(FATAL_ERROR "Run scripts/android/setup-omnivoice.sh")
endif()
add_library(kat_omnivoice SHARED IMPORTED)
set_target_properties(kat_omnivoice PROPERTIES IMPORTED_LOCATION "${KAT_ROOT}/.build/android-media/omnivoice/libkat_omnivoice.so")
target_link_libraries(kat_media PRIVATE kat_omnivoice)
