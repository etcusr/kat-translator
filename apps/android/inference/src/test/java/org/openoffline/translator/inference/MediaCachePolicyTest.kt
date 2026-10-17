package org.openoffline.translator.inference
import org.junit.Assert.*
import org.junit.Test
class MediaCachePolicyTest {
    @Test fun retainsOnlyWithCapacityAndHeadroom() {
        assertTrue(MediaCachePolicy.retain(16_000_000_000,5_000_000_000,500_000_000,false))
        assertFalse(MediaCachePolicy.retain(8_000_000_000,5_000_000_000,500_000_000,false))
        assertFalse(MediaCachePolicy.retain(16_000_000_000,1_000_000_000,500_000_000,false))
        assertFalse(MediaCachePolicy.retain(16_000_000_000,5_000_000_000,500_000_000,true))
        assertFalse(MediaCachePolicy.retain(16_000_000_000,3_000_000_000,2_000_000_000,false))
    }
}
