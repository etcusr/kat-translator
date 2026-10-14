package org.openoffline.translator.android

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.rules.TestRule
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** UI tests must not load a 9B model just by creating an Activity.
 * Restore the user's preference only after the Activity rule has closed. */
object UiTestEnvironment {
    fun wrap(activity:TestRule=TestRule { statement,_ -> statement }):TestRule=RuleChain.outerRule(object:ExternalResource() {
        private val prefs get()=InstrumentationRegistry.getInstrumentation().targetContext.getSharedPreferences("kat",0)
        override fun before() {
            // A thermal force-stop skips JUnit finally/after. Recover the previous
            // run before taking a new durable snapshot, including absent keys.
            restore()
            val values=JSONObject()
            prefs.all.filterKeys { it in changedKeys || it.startsWith("voice.") }.forEach { (key,value) ->
                values.put(key,if(value is Set<*>)JSONArray(value.toList()) else value)
            }
            val temporary=File(journal.parentFile,journal.name+".tmp")
            temporary.outputStream().use { it.write(values.toString().toByteArray());it.fd.sync() }
            check(temporary.renameTo(journal))
            check(prefs.edit().putBoolean("automaticModelLoad",false).commit())
        }
        override fun after() = restore()
    }).around(activity)

    private val changedKeys=setOf("unfinishedAutomaticModelLoad","automaticModelLoad","interfaceLanguage","recordingMode","recordingLimitMinutes",
        "recordingSilenceSeconds","recordingPreprocessing","recordingPreviewVerification","recognitionPreference",
        "historyRecordText","historyRecordAudio","historyRecordImages","translationModel","recognitionModel",
        "source","target","manualSource","automaticSpeech","automaticSpeechVoice","automaticSpeechText","favoriteLanguages",
        "historyCount","historyDays","audioCount","audioDays","imageCount","imageDays","memorySaving","playbackSpeed")
    private val journal get()=File(InstrumentationRegistry.getInstrumentation().targetContext.noBackupFilesDir,"ui-test-preferences.json")
    fun restore() {
        if(!journal.isFile)return
        val saved=JSONObject(journal.readText())
        val prefs=InstrumentationRegistry.getInstrumentation().targetContext.getSharedPreferences("kat",0)
        val keys=changedKeys+prefs.all.keys.filter { it.startsWith("voice.") }+saved.keys().asSequence().toList()
        val editor=prefs.edit()
        for(key in keys) {
            if(!saved.has(key)) { editor.remove(key);continue }
            if(key=="playbackSpeed") { editor.putFloat(key,saved.getDouble(key).toFloat());continue }
            when(val value=saved.get(key)) {
                is Boolean -> editor.putBoolean(key,value)
                is String -> editor.putString(key,value)
                is Int -> editor.putInt(key,value)
                is Long -> editor.putLong(key,value)
                is Number -> editor.putFloat(key,value.toFloat())
                is JSONArray -> editor.putStringSet(key,(0 until value.length()).map { value.getString(it) }.toSet())
            }
        }
        check(editor.commit());check(journal.delete())
    }
}
