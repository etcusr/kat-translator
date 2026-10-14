package org.openoffline.translator.android
import org.junit.Assert.*
import org.junit.Test
import org.json.JSONArray
import java.io.File

class CatMotionTest {
    @Test fun twoMinutesMatchCurrentIosIncludingTurnsJumpsAndContinuousLandings() {
        var root=File(System.getProperty("user.dir"))
        while(!File(root,"tests/fixtures/android/cat-motion-ios.json").isFile)root=root.parentFile ?: error("fixture missing")
        val reference=JSONArray(File(root,"tests/fixtures/android/cat-motion-ios.json").readText())
        val scene=CatPreparation(42)
        var row=0;var sawLeft=false;var sawRight=false
        for(tick in 0..3600) {
            scene.advance(tick/30.0,.28)
            if(scene.facingRight)sawRight=true else sawLeft=true
            assertTrue(scene.position in 0.0..1.0)
            if(tick%15!=0)continue
            val m=scene.motion;val p=scene.play
            val actual=listOf(tick.toDouble(),scene.position,if(scene.facingRight)1.0 else 0.0,m.standing,m.stride,m.leap,p.leap,p.crouch,p.rotation,p.turn,p.travel,p.retreat,p.digging,p.retching,p.spill,p.heave)
            val expected=reference.getJSONArray(row++)
            actual.forEachIndexed { index,value -> assertEquals("tick=$tick component=$index",expected.getDouble(index),value,1e-7) }
        }
        assertTrue(sawLeft && sawRight)
    }
    @Test fun wallLandingDoesNotTeleportInEitherDirection() {
        for(right in listOf(true,false)) {
            val p=CatPlay(0.0,42);assertTrue(p.beginWallKick(0.0))
            val takeoff=CatPlay.wallTakeoff(.28)
            p.advance(.91,if(right)takeoff else 1-takeoff,right)
            assertEquals(1.0,p.turn,1e-8)
            val before=(if(right)takeoff else 1-takeoff)+(if(right)-p.retreat else p.retreat)
            val after=if(right)1-CatPlay.wallLanding(takeoff) else CatPlay.wallLanding(takeoff)
            assertEquals(before,after,1e-8)
        }
    }
}
