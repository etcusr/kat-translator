# Android-only workaround for https://github.com/ggml-org/llama.cpp/issues/26921.
# Keep the pinned shared vendor tree unchanged. Fail closed when upstream changes.
set(KAT_VK_SOURCE_DIR "${KAT_ROOT}/Dependencies/vendor/llama.cpp/ggml/src/ggml-vulkan")
file(READ "${KAT_VK_SOURCE_DIR}/ggml-vulkan.cpp" KAT_VK_SOURCE)
set(KAT_VK_NEEDLE [=[device->matmul_tile_selector = [](uint32_t m, uint32_t n, uint32_t /*k*/, uint32_t /*shader_core_count*/,
                                          const std::vector<vk_matmul_pipeline_pair>& configs) -> uint32_t {
            if (configs.size() <= 1) return 0;
            if (m <= 32 || n <= 32) return 0;]=])
set(KAT_VK_REPLACEMENT [=[device->matmul_tile_selector = [vendor_id = device->vendor_id](uint32_t m, uint32_t n, uint32_t /*k*/, uint32_t /*shader_core_count*/,
                                          const std::vector<vk_matmul_pipeline_pair>& configs) -> uint32_t {
            if (configs.size() <= 1) return 0;
            if (vendor_id == 0x13B5 && !std::getenv("KAT_VK_ALLOW_NARROW_TILES") && m <= 32 && n > 32) return 1;
            if (m <= 32 || n <= 32) return 0;]=])
string(FIND "${KAT_VK_SOURCE}" "${KAT_VK_NEEDLE}" KAT_VK_MATCH)
if(KAT_VK_MATCH EQUAL -1)
    message(FATAL_ERROR "Pinned Vulkan tile selector changed; review Mali experiment")
endif()
string(REPLACE "${KAT_VK_NEEDLE}" "${KAT_VK_REPLACEMENT}" KAT_VK_PATCHED "${KAT_VK_SOURCE}")
# Pixel 9 Pro measurements: native scalar/vector kernels beat KHR cooperative
# matrices on Mali-G715. Keep other GPUs' upstream policy and an A/B escape.
foreach(KAT_COOP_ASSIGN IN ITEMS "device->coopmat_support" "coopmat_support")
    if(KAT_COOP_ASSIGN STREQUAL "device->coopmat_support")
        set(KAT_COOP_INDENT "                ")
        set(KAT_COOP_DEVICE "device->physical_device")
    else()
        set(KAT_COOP_INDENT "            ")
        set(KAT_COOP_DEVICE "physical_device")
    endif()
    set(KAT_COOP_NEEDLE "!getenv(\"GGML_VK_DISABLE_COOPMAT\")) {\n${KAT_COOP_INDENT}${KAT_COOP_ASSIGN} = true;")
    set(KAT_COOP_REPLACEMENT "!getenv(\"GGML_VK_DISABLE_COOPMAT\") && (std::string(${KAT_COOP_DEVICE}.getProperties().deviceName.data()) != \"Mali-G715\" || getenv(\"KAT_VK_ENABLE_G715_COOPMAT\"))) {\n${KAT_COOP_INDENT}${KAT_COOP_ASSIGN} = true;")
    string(FIND "${KAT_VK_PATCHED}" "${KAT_COOP_NEEDLE}" KAT_COOP_MATCH)
    if(KAT_COOP_MATCH EQUAL -1)
        message(FATAL_ERROR "Pinned Vulkan cooperative matrix selection changed")
    endif()
    string(REPLACE "${KAT_COOP_NEEDLE}" "${KAT_COOP_REPLACEMENT}" KAT_VK_PATCHED "${KAT_VK_PATCHED}")
endforeach()
# Pixel 9 Pro: F32-activation matvec beats MMVQ for single-token decode.
# Retain integer-dot MMQ for prefill and upstream policy for other devices.
# GGML_VK_FORCE_MMVQ / DISABLE_MMVQ still take precedence for diagnostics.
set(KAT_MMV_NEEDLE "    // q6_k only has 2-byte alignment which makes it somewhat problematic,")
set(KAT_MMV_REPLACEMENT [=[    if ((n == 1 || (n == 2 && !getenv("KAT_VK_STOCK_G715_MULTI"))) && std::string(device->properties.deviceName.data()) == "Mali-G715" && !getenv("KAT_VK_STOCK_G715_MMVQ")) {
        return false;
    }

    // q6_k only has 2-byte alignment which makes it somewhat problematic,]=])
string(FIND "${KAT_VK_PATCHED}" "${KAT_MMV_NEEDLE}" KAT_MMV_MATCH)
if(KAT_MMV_MATCH EQUAL -1)
    message(FATAL_ERROR "Pinned Vulkan matvec selection changed; review Mali policy")
endif()
string(REPLACE "${KAT_MMV_NEEDLE}" "${KAT_MMV_REPLACEMENT}" KAT_VK_PATCHED "${KAT_VK_PATCHED}")
set(KAT_VK_COPY "${CMAKE_CURRENT_BINARY_DIR}/ggml-vulkan-mali.cpp")
include("${CMAKE_CURRENT_LIST_DIR}/mali-prefill.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/mali-q6-direct.cmake")
file(WRITE "${KAT_VK_COPY}" "${KAT_VK_PATCHED}")
get_target_property(KAT_VK_SOURCES ggml-vulkan SOURCES)
set(KAT_VK_NEW_SOURCES "")
foreach(KAT_VK_FILE IN LISTS KAT_VK_SOURCES)
    if(KAT_VK_FILE STREQUAL "ggml-vulkan.cpp" OR KAT_VK_FILE STREQUAL "${KAT_VK_SOURCE_DIR}/ggml-vulkan.cpp")
        list(APPEND KAT_VK_NEW_SOURCES "${KAT_VK_COPY}")
    elseif(IS_ABSOLUTE "${KAT_VK_FILE}" OR KAT_VK_FILE MATCHES "^\\$<")
        list(APPEND KAT_VK_NEW_SOURCES "${KAT_VK_FILE}")
    else()
        list(APPEND KAT_VK_NEW_SOURCES "${KAT_VK_SOURCE_DIR}/${KAT_VK_FILE}")
    endif()
endforeach()
set_property(TARGET ggml-vulkan PROPERTY SOURCES "${KAT_VK_NEW_SOURCES}")
target_include_directories(ggml-vulkan PRIVATE "${KAT_VK_SOURCE_DIR}")
