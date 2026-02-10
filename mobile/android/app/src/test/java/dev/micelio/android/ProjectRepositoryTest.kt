package dev.micelio.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProjectRepositoryTest {
    @Test
    fun inMemoryRepositoryReturnsProjects() {
        val repository = InMemoryProjectRepository()
        val projects = repository.listProjects()

        assertTrue(projects.isNotEmpty())
        assertEquals(projects.size, projects.map { it.id }.distinct().size)
        assertNotNull(repository.getProject(projects.first().id))
    }
}
