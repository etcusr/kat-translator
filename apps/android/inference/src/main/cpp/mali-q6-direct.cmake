# Q6 direct scale loads: production Mali-G715, explicit opt-in for diagnostic controls.
set(KAT_Q6_DIR "${CMAKE_CURRENT_BINARY_DIR}/q6-direct")
execute_process(COMMAND python3 "${KAT_ROOT}/scripts/android/prepare-q6-direct.py" "${KAT_ROOT}" "${KAT_Q6_DIR}/shaders" COMMAND_ERROR_IS_FATAL ANY)
file(GLOB KAT_Q6_INCLUDES "${KAT_VK_SOURCE_DIR}/vulkan-shaders/*.glsl")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${KAT_ROOT}/scripts/android/prepare-q6-direct.py"
    "${KAT_VK_SOURCE_DIR}/vulkan-shaders/mul_mat_vec_q6_k.comp" ${KAT_Q6_INCLUDES})
set(KAT_Q6_CPP "${KAT_Q6_DIR}/mul_mat_vec_q6_k.comp.cpp")
add_custom_command(OUTPUT "${KAT_Q6_CPP}"
    COMMAND "${CMAKE_BINARY_DIR}/$<CONFIG>/vulkan-shaders-gen"
        --glslc "${Vulkan_GLSLC_EXECUTABLE}"
        --source "${KAT_Q6_DIR}/shaders/mul_mat_vec_q6_k.comp"
        --output-dir "${KAT_Q6_DIR}/spv"
        --target-hpp "${CMAKE_CURRENT_BINARY_DIR}/llama/ggml/src/ggml-vulkan/ggml-vulkan-shaders.hpp"
        --target-cpp "${KAT_Q6_CPP}"
    DEPENDS "${KAT_Q6_DIR}/shaders/mul_mat_vec_q6_k.comp" ${KAT_Q6_INCLUDES} vulkan-shaders-gen)
set_source_files_properties("${KAT_Q6_CPP}" TARGET_DIRECTORY ggml-vulkan PROPERTIES GENERATED TRUE)
add_custom_target(kat_q6_shader DEPENDS "${KAT_Q6_CPP}")
add_dependencies(ggml-vulkan kat_q6_shader)
get_target_property(KAT_Q6_SOURCES ggml-vulkan SOURCES)
set(KAT_Q6_NEW "")
set(KAT_Q6_REPLACED 0)
foreach(KAT_Q6_SOURCE IN LISTS KAT_Q6_SOURCES)
    if(KAT_Q6_SOURCE MATCHES "/mul_mat_vec_q6_k.comp.cpp$")
        list(APPEND KAT_Q6_NEW "${KAT_Q6_CPP}")
        math(EXPR KAT_Q6_REPLACED "${KAT_Q6_REPLACED} + 1")
    else()
        list(APPEND KAT_Q6_NEW "${KAT_Q6_SOURCE}")
    endif()
endforeach()
if(NOT KAT_Q6_REPLACED EQUAL 1)
    message(FATAL_ERROR "Expected exactly one generated Q6 shader source")
endif()
set_property(TARGET ggml-vulkan PROPERTY SOURCES "${KAT_Q6_NEW}")
set(KAT_Q6_NEEDLE "arr_dmmv_q6_k_f32_f32_data[reduc16], \"main\", mul_mat_vec_num_bindings, sizeof(vk_mat_vec_push_constants), {rm_kq, 1, 1}, {wg_size_subgroup16, rm_kq, i+1}")
string(FIND "${KAT_VK_PATCHED}" "${KAT_Q6_NEEDLE}" KAT_Q6_MATCH)
if(KAT_Q6_MATCH EQUAL -1)
    message(FATAL_ERROR "Pinned Q6 pipeline changed")
endif()
set(KAT_Q6_ENABLE "!getenv(\"KAT_VK_STOCK_G715_Q6_DIRECT\")")
if(KAT_GPU_DIAGNOSTICS)
    set(KAT_Q6_ENABLE "getenv(\"KAT_VK_Q6_DIRECT\")")
endif()
set(KAT_Q6_REPLACE "arr_dmmv_q6_k_f32_f32_data[reduc16], \"main\", mul_mat_vec_num_bindings, sizeof(vk_mat_vec_push_constants), {rm_kq, 1, 1}, {wg_size_subgroup16, rm_kq, i+1, uint32_t(std::string(device->properties.deviceName.data()) == \"Mali-G715\" && ${KAT_Q6_ENABLE})}")
string(REPLACE "${KAT_Q6_NEEDLE}" "${KAT_Q6_REPLACE}" KAT_VK_PATCHED "${KAT_VK_PATCHED}")
