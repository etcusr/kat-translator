cmake_minimum_required(VERSION 3.20)
project(OmniVoiceRuntime LANGUAGES C CXX OBJC)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO)
set(OV_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../../../Dependencies/vendor/omnivoice-mobile")
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_METAL ON CACHE BOOL "" FORCE)
set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
set(GGML_BLAS ON CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
add_compile_definitions(GGML_MAX_NAME=128)
add_subdirectory("${OV_SOURCE}/ggml" ggml)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/version.h" "#pragma once\n#define OMNIVOICE_VERSION \"53e6c206-ios\"\n")
add_library(OmniVoiceRuntime SHARED
 "${OV_SOURCE}/src/omnivoice.cpp"
 "${OV_SOURCE}/src/pipeline-codec.cpp"
 "${OV_SOURCE}/src/pipeline-tts.cpp")
target_compile_definitions(OmniVoiceRuntime PRIVATE OMNIVOICE_BUILD)
target_include_directories(OmniVoiceRuntime PRIVATE "${OV_SOURCE}/src" "${OV_SOURCE}" "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(OmniVoiceRuntime PRIVATE ggml ggml-base ggml-cpu ggml-metal ggml-blas)
target_link_options(OmniVoiceRuntime PRIVATE "-Wl,-exported_symbols_list,${CMAKE_CURRENT_SOURCE_DIR}/exports.txt")
set_target_properties(OmniVoiceRuntime PROPERTIES
 FRAMEWORK TRUE FRAMEWORK_VERSION A
 MACOSX_FRAMEWORK_BUNDLE_VERSION 1
 MACOSX_FRAMEWORK_SHORT_VERSION_STRING 1.0
 MACOSX_FRAMEWORK_IDENTIFIER org.openoffline.OmniVoiceRuntime
 PUBLIC_HEADER "${OV_SOURCE}/src/omnivoice.h")
