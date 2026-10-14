package org.openoffline.translator.inference

import android.content.Context
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipInputStream

/** Installs code shipped inside the signed APK, never code from downloaded voice packages. */
object WayuAssets {
    @Synchronized fun prepare(context:Context):String {
        val digest=context.assets.open("wayu-runtime.sha256").bufferedReader().use{it.readText().trim()}
        require(digest.matches(Regex("[0-9a-f]{64}")))
        val target=File(context.noBackupFilesDir,"wayu-runtime-${digest.take(16)}")
        if(File(target,".complete").readTextOrNull()==digest)return target.absolutePath
        val temporary=File(context.noBackupFilesDir,"wayu-runtime-${digest.take(16)}.partial")
        if(temporary.exists())check(temporary.deleteRecursively())
        check(temporary.mkdirs())
        val archive=File(temporary,"runtime.zip")
        try {
            val actual=MessageDigest.getInstance("SHA-256")
            context.assets.open("wayu-runtime.zip").use{input->archive.outputStream().use{output->
                val buffer=ByteArray(65536);var size=0L
                while(true){val n=input.read(buffer);if(n<0)break;size+=n;require(size<=64L*1024*1024);actual.update(buffer,0,n);output.write(buffer,0,n)}
            }}
            check(actual.digest().joinToString(""){"%02x".format(it)}==digest){"Wayu runtime asset digest mismatch"}
            var total=0L;var count=0
            ZipInputStream(archive.inputStream().buffered()).use{zip->
                while(true){val entry=zip.nextEntry?:break;require(++count<=5000)
                    val name=entry.name;require(!name.startsWith('/') && !name.contains('\\') && name.split('/').none{it==".."||it=="."})
                    val output=File(temporary,name);require(output.canonicalPath.startsWith(temporary.canonicalPath+File.separator))
                    if(entry.isDirectory){check(output.mkdirs()||output.isDirectory);continue}
                    check(output.parentFile!!.mkdirs()||output.parentFile!!.isDirectory);check(!output.exists())
                    output.outputStream().use{stream->val buffer=ByteArray(65536);while(true){val n=zip.read(buffer);if(n<0)break;total+=n;require(total<=160L*1024*1024);stream.write(buffer,0,n)}}
                    check(output.setReadOnly())
                }
            }
            check(archive.delete());File(temporary,".complete").writeText(digest)
            if(target.exists())check(target.deleteRecursively())
            check(temporary.renameTo(target)){"Cannot install Wayu runtime"}
            return target.absolutePath
        }catch(t:Throwable){temporary.deleteRecursively();throw t}
    }
    /** Diagnostic/frontend API, identical phoneme IDs to the shared Apple implementation. */
    fun tokens(context:Context,text:String):LongArray {
        require(text.isNotBlank() && text.length<=2000 && '\u0000' !in text)
        return MediaNative.wayuTokens(prepare(context).toByteArray(Charsets.UTF_8),text.toByteArray(Charsets.UTF_8))
    }
    private fun File.readTextOrNull():String?=if(isFile)readText() else null
}
