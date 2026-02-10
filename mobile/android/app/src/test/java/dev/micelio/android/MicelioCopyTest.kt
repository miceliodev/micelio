package dev.micelio.android

import org.junit.Assert.assertEquals
import org.junit.Test

class MicelioCopyTest {
    @Test
    fun defaultCopyIsStable() {
        assertEquals("Micelio", MicelioCopy.welcomeTitle())
        assertEquals("Agent-first forge, now in your pocket.", MicelioCopy.welcomeSubtitle())
        assertEquals("Sign in", MicelioCopy.ctaLabel())
        assertEquals("Projects", MicelioCopy.projectListTitle())
    }
}
