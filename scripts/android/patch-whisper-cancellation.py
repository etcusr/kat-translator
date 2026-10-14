#!/usr/bin/env python3
"""Generate an Android-only Whisper source with scheduler-level cancellation.

The pinned upstream scheduler overload drops the abort callback, unlike its
legacy CPU overload. Keep vendor/Apple sources intact and fail on source drift.
"""
import pathlib
import sys


def patch(source: str) -> str:
    def replace(old: str, new: str, count: int) -> None:
        nonlocal source
        if source.count(old) != count:
            raise ValueError(f"Whisper cancellation patch drift: expected {count}: {old!r}")
        source = source.replace(old, new)

    replace("bool   sched_reset = true) {", "bool   sched_reset = true,\n"
            "      ggml_abort_callback   abort_callback = nullptr,\n"
            "                    void * abort_callback_data = nullptr) {", 1)
    replace("        auto * fn_set_n_threads =", "        auto * fn_set_abort = (ggml_backend_set_abort_callback_t)\n"
            "            ggml_backend_reg_get_proc_address(reg, \"ggml_backend_set_abort_callback\");\n"
            "        if (fn_set_abort) fn_set_abort(backend, abort_callback, abort_callback_data);\n\n"
            "        auto * fn_set_n_threads =", 1)
    # Convolution, encoder, cross-attention and decoder all share this overload.
    replace("ggml_graph_compute_helper(sched, gf, n_threads)",
            "ggml_graph_compute_helper(sched, gf, n_threads, true, abort_callback, abort_callback_data)", 4)
    return source


if __name__ == "__main__":
    original, output = map(pathlib.Path, sys.argv[1:])
    result = patch(original.read_text())
    if not output.exists() or output.read_text() != result:
        output.write_text(result)
