package org.openoffline.translator.android.history

import org.junit.Assert.*
import org.junit.Test

class AudioHistoryRetentionTest {
    private val day=86_400_000L
    @Test fun pairedFilesConsumeSeparateSlots(){
        val rows=listOf(AudioRetentionEntry("new",20*day,"new.wav","new-original.wav"),AudioRetentionEntry("old",19*day,"old.wav","old-original.wav"))
        assertEquals(setOf("new.wav","new-original.wav","old.wav"),AudioHistoryRetention.select(rows,3,30,21*day))
        assertEquals(setOf("new.wav"),AudioHistoryRetention.select(rows,1,30,21*day))
    }
    @Test fun zeroDisablesOnlyItsOwnLimit(){
        val rows=listOf(AudioRetentionEntry("new",20*day,"new.wav",null),AudioRetentionEntry("old",day,null,"old-original.wav"))
        assertEquals(setOf("new.wav","old-original.wav"),AudioHistoryRetention.select(rows,0,0,100*day))
        assertEquals(setOf("new.wav"),AudioHistoryRetention.select(rows,0,30,40*day))
        assertEquals(setOf("new.wav"),AudioHistoryRetention.select(rows,1,0,100*day))
    }
    @Test fun newerFilesWinAndTiedRowsKeepInputOrder(){
        val rows=listOf(AudioRetentionEntry("old",10,null,"old.wav"),AudioRetentionEntry("first",20,"first.wav",null),AudioRetentionEntry("second",20,"second.wav",null))
        assertEquals(listOf("first.wav","second.wav"),AudioHistoryRetention.select(rows,2,0,30).toList())
    }
    @Test fun boundaryAgeAndDuplicatePathsCountExactlyOnce(){
        val rows=listOf(AudioRetentionEntry("first",70*day,"same.wav","same.wav"),AudioRetentionEntry("boundary",70*day,"boundary.wav",null),AudioRetentionEntry("expired",70*day-1,"expired.wav",null))
        assertEquals(setOf("same.wav","boundary.wav"),AudioHistoryRetention.select(rows,2,30,100*day))
    }
}
