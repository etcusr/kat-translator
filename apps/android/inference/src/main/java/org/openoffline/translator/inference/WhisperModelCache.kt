package org.openoffline.translator.inference

/** Native Whisper library that owns a model handle. A handle is freed only by the library that created it. */
enum class WhisperBackend { BASELINE, ARM82, I8MM }

/** The verified i8mm path applies only to the measured Q8 model file; everything else keeps the existing selection. */
private const val I8MM_VERIFIED_MODEL = "ggml-large-v3-turbo-q8_0.bin"

fun whisperBackendFor(modelFileName: String, arm82Available: Boolean, i8mmAvailable: Boolean): WhisperBackend = when {
    !arm82Available -> WhisperBackend.BASELINE
    i8mmAvailable && modelFileName == I8MM_VERIFIED_MODEL -> WhisperBackend.I8MM
    else -> WhisperBackend.ARM82
}

/** One Whisper model with its owning backend. Never caches a failed load; replacement frees the old owner first. */
internal class WhisperModelCache(private val release: (WhisperBackend, Long) -> Unit) : AutoCloseable {
    private var identity: String? = null
    private var handle = 0L
    var backend: WhisperBackend? = null; private set
    var loads = 0; private set

    fun acquire(identity: String, backend: WhisperBackend, create: (WhisperBackend) -> Long): Long {
        if (handle != 0L && this.identity == identity && this.backend == backend) return handle
        close()
        val loaded = create(backend)
        check(loaded != 0L) { "Whisper model could not be loaded" }
        handle = loaded; this.identity = identity; this.backend = backend; loads++
        return loaded
    }

    override fun close() {
        val owner = backend; val current = handle
        handle = 0L; identity = null; backend = null
        if (current != 0L && owner != null) release(owner, current)
    }
}
