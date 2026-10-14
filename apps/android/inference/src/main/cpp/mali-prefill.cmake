# Pixel 9 Pro measurements: Q4_K medium tiles avoid the expensive large tile;
# Q6_K uses measured small/large replacements. Keep weights and activation quantization.
set(KAT_TILE_NEEDLE "std::vector<vk_tile_config> tc_mmq_int_k = {{s_warptile_mmq_int_k, s_mmq_wg_denoms, s_align}, {m_warptile_mmq_int_k, m_mmq_wg_denoms, m_align}, {l_warptile_mmq_int_k, l_mmq_wg_denoms, l_align}};")
set(KAT_TILE_MODE "nullptr")
set(KAT_TILE_EXPERIMENTS "")
if(KAT_GPU_DIAGNOSTICS)
    string(REPLACE "if ((n == 1 || (n == 2 && !getenv(\"KAT_VK_STOCK_G715_MULTI\"))) && std::string(device->properties.deviceName.data())"
        "if ((n == 1 || (n <= 8 && getenv(\"KAT_VK_MALI_MMV_MULTI\"))) && std::string(device->properties.deviceName.data())"
        KAT_VK_PATCHED "${KAT_VK_PATCHED}")
    set(KAT_TILE_MODE "getenv(\"KAT_VK_MALI_MMQ_TILE\")")
    set(KAT_TILE_EXPERIMENTS [=[
                    if (tile && std::string(tile) == "medium") {
                        vk_tile_config config = {m_warptile_mmq_int_k, m_mmq_wg_denoms, m_align};
                        tc_mmq_int_q4 = tc_mmq_int_q6 = {config, config, config};
                    } else if (tile && std::string(tile) == "compact") {
                        vk_tile_config config = {{64,64,32,32,16,32,1,1,2,1,16}, {64,32,1}, 32};
                        tc_mmq_int_q4 = tc_mmq_int_q6 = {config, config, config};
                    } else if (tile && std::string(tile) == "lean") {
                        vk_tile_config config = {{128,64,64,32,16,32,1,1,2,1,16}, {64,64,1}, 64};
                        tc_mmq_int_q4 = tc_mmq_int_q6 = {config, config, config};
                    } else if (tile && std::string(tile) == "strip16") {
                        // Four subgroup16 warps cover 64x16, 16 accumulators per lane.
                        vk_tile_config config = {{64,64,16,32,16,16,1,1,1,1,16}, {64,16,1}, 32};
                        tc_mmq_int_q4 = tc_mmq_int_q6 = {config, config, config};
                    } else if (tile && std::string(tile) == "strip32") {
                        // Eight warps cover 64x32 without increasing per-lane registers.
                        vk_tile_config config = {{128,64,32,32,16,16,1,1,1,1,16}, {64,32,1}, 32};
                        tc_mmq_int_q4 = tc_mmq_int_q6 = {config, config, config};
                    } else if (tile && std::string(tile) == "q6wide") {
                        vk_tile_config q4 = {m_warptile_mmq_int_k, m_mmq_wg_denoms, m_align};
                        tc_mmq_int_q4 = {q4,q4,q4};
                        tc_mmq_int_q6[0] = {{64,64,32,32,16,32,1,1,2,1,16}, {64,32,1}, 32};
                        tc_mmq_int_q6[2] = {{128,64,32,32,16,16,1,1,1,1,16}, {64,32,1}, 32};
                        // Upstream filtered the original large tile before this override.
                        // Recompute capacity for the replacement instead of inheriting its rejection.
                        device->mul_mat_l_int[GGML_TYPE_Q6_K] = ggml_vk_matmul_int_shmem_support(device, tc_mmq_int_q6[2].warptile, false, GGML_TYPE_Q6_K);
                    }
]=])
endif()
set(KAT_TILE_EXTRA [=[
                auto tc_mmq_int_q4 = tc_mmq_int_k;
                auto tc_mmq_int_q6 = tc_mmq_int_k;
                if (std::string(device->properties.deviceName.data()) == "Mali-G715" &&
                    device->subgroup_size == 16 && !device->coopmat_support) {
                    const char *tile = @KAT_TILE_MODE@;
                    if ((!tile && !getenv("KAT_VK_STOCK_G715_PREFILL")) || (tile && std::string(tile) == "index")) {
                        vk_tile_config q4 = {m_warptile_mmq_int_k, m_mmq_wg_denoms, m_align};
                        tc_mmq_int_q4 = {q4,q4,q4};
                        // 64/16=4 warps = (64/16)*(32/32); TM=1 limits A register cache.
                        tc_mmq_int_q6[0] = {{64,64,32,32,16,32,1,1,2,1,16}, {64,32,1}, 32};
                        // Keep explicit diagnostic "index" as the previous production control.
                        if (!tile && !getenv("KAT_VK_STOCK_G715_Q6_WIDE")) {
                            tc_mmq_int_q6[2] = {{128,64,32,32,16,16,1,1,1,1,16}, {64,32,1}, 32};
                            device->mul_mat_l_int[GGML_TYPE_Q6_K] = ggml_vk_matmul_int_shmem_support(device, tc_mmq_int_q6[2].warptile, false, GGML_TYPE_Q6_K);
                        }
                    }
@KAT_TILE_EXPERIMENTS@
                }
]=])
string(CONFIGURE "${KAT_TILE_EXTRA}" KAT_TILE_EXTRA @ONLY)
string(FIND "${KAT_VK_PATCHED}" "${KAT_TILE_NEEDLE}" KAT_TILE_MATCH)
if(KAT_TILE_MATCH EQUAL -1)
    message(FATAL_ERROR "Pinned integer MMQ configurations changed")
endif()
string(REPLACE "${KAT_TILE_NEEDLE}" "${KAT_TILE_NEEDLE}\n${KAT_TILE_EXTRA}" KAT_VK_PATCHED "${KAT_VK_PATCHED}")
string(REPLACE "{GGML_TYPE_Q4_K, GGML_TYPE_Q8_1, false, false}, tc_mmq_int_k," "{GGML_TYPE_Q4_K, GGML_TYPE_Q8_1, false, false}, tc_mmq_int_q4," KAT_VK_PATCHED "${KAT_VK_PATCHED}")
string(REPLACE "{GGML_TYPE_Q6_K, GGML_TYPE_Q8_1, false, false}, tc_mmq_int_k," "{GGML_TYPE_Q6_K, GGML_TYPE_Q8_1, false, false}, tc_mmq_int_q6," KAT_VK_PATCHED "${KAT_VK_PATCHED}")
