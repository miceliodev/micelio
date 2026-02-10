package dev.micelio.android

interface ProjectRepository {
    fun listProjects(): List<Project>
    fun getProject(id: String): Project?
}

class InMemoryProjectRepository : ProjectRepository {
    private val projects = listOf(
        Project(
            id = "micelio",
            name = "Micelio",
            handle = "micelio",
            organization = "micelio",
            description = "Agent-first git forge for session-driven collaboration.",
            starCount = 1240,
            visibility = ProjectVisibility.PUBLIC
        ),
        Project(
            id = "sprout",
            name = "Sprout",
            handle = "sprout",
            organization = "pep",
            description = "Personal knowledge base with daily synthesis and tagging.",
            starCount = 438,
            visibility = ProjectVisibility.PUBLIC
        ),
        Project(
            id = "hif",
            name = "hif",
            handle = "hif",
            organization = "micelio",
            description = "High-performance gRPC transport for forge automation.",
            starCount = 312,
            visibility = ProjectVisibility.PUBLIC
        ),
        Project(
            id = "dune",
            name = "Dune",
            handle = "dune",
            organization = "forge-labs",
            description = "Minimal CI runner focused on agent-validated landings.",
            starCount = 208,
            visibility = ProjectVisibility.PRIVATE
        )
    )

    override fun listProjects(): List<Project> = projects

    override fun getProject(id: String): Project? = projects.firstOrNull { it.id == id }
}
