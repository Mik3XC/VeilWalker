pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "VeilWalker"
include(
    ":app",
    ":core:data",
    ":core:steps",
    ":core:achievements",
    ":core:anticheat",
    ":core:ledger",
    ":core:identity",
    ":core:net",
    ":core:route",
    ":core:snowflake",
)
