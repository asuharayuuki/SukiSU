package com.sukisu.nova.data.update

import org.junit.Assert.assertEquals
import org.junit.Test

class UpdateSourceConfigTest {

    @Test
    fun defaultSourcePublishesRawManifestBranches() {
        val source = UpdateSourceDefaults.DEFAULT

        assertEquals(UpdateSourcePlatform.CNB_RAW, source.platform)
        assertEquals(
            "https://cnb.cool/sukisu-nova/Release/-/git/raw/stable/manifest.json",
            source.releasesApiUrl(UpdateSourceDefaults.STABLE_ENDPOINT),
        )
        assertEquals(
            "https://cnb.cool/sukisu-nova/Release/-/git/raw/manager-ci/manifest.json",
            source.releasesApiUrl("tags/${UpdateSourceDefaults.CI_TAG}"),
        )
        assertEquals(
            "https://cnb.cool/sukisu-nova/Release/-/git/raw/",
            source.downloadUrlPrefix(),
        )
    }

    @Test
    fun devTagMapsToItsOwnRawBranch() {
        assertEquals(
            "https://cnb.cool/sukisu-nova/Release/-/git/raw/manager-dev/manifest.json",
            UpdateSourceDefaults.DEFAULT.releasesApiUrl("tags/manager-dev"),
        )
    }
}
