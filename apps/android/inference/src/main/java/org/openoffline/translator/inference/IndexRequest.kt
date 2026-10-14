package org.openoffline.translator.inference
import java.nio.CharBuffer
import java.nio.charset.CodingErrorAction

data class IndexRequest(val text: String, val target: String) {
    val prefix: String get() {
        val name=IndexLanguages.byId[target]?.promptName ?: throw IllegalArgumentException("Unsupported target: $target")
        return "<|im_start|>user\n请将以下文本翻译为${name}，直接输出翻译结果，不要进行任何解释。\n\n"
    }
    val suffix: String get() = "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    companion object {
        fun utf8(text: String): ByteArray {
            require(!text.contains('\u0000')) { "NUL is not supported" }
            return try {
                val buffer=Charsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT).encode(CharBuffer.wrap(text))
                ByteArray(buffer.remaining()).also { buffer.get(it) }
            } catch (e: java.nio.charset.CharacterCodingException) { throw IllegalArgumentException("Invalid Unicode", e) }
        }
        fun fits(prompt: Int, source: Int): Boolean = prompt in 1..1536 && source>=0 && prompt.toLong()+(source.toLong()*3+1)/2+64<=2048
    }
}
