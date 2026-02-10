package dev.micelio.android

enum class ProjectVisibility(val label: String) {
    PUBLIC("Public"),
    PRIVATE("Private")
}

data class Project(
    val id: String,
    val name: String,
    val handle: String,
    val organization: String,
    val description: String,
    val starCount: Int,
    val visibility: ProjectVisibility
) {
    val fullHandle: String
        get() = "$organization/$handle"
}
