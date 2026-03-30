# Java allowlist — Maven Central, Gradle plugin portal, Gradle wrapper, and JDK toolchains.
#
# Covers mvn, ./gradlew, and Gradle JDK toolchain provisioning.
#
# GitHub-hosted Gradle wrapper binaries and Eclipse Temurin releases are
# covered by the github service.
#
# jcenter.bintray.com is intentionally excluded (shut down May 2021).
# oss.sonatype.org is included for projects using SNAPSHOT dependencies.
{
  hosts = [
    "repo1.maven.org"          # Maven Central primary artifact repository
    "repo.maven.apache.org"    # Maven Central mirror
    "oss.sonatype.org"         # Sonatype OSS — SNAPSHOT staging repository
    "plugins.gradle.org"       # Gradle plugin portal
    "downloads.gradle.org"     # Gradle wrapper binary distributions
    "services.gradle.org"      # Gradle build scans / Develocity
    "api.adoptopenjdk.net"     # AdoptOpenJDK toolchain provisioning (legacy projects)
    "api.azul.com"             # Azul / Zulu JDK toolchain provisioning
    "repository.jboss.org"
  ];

  cidrs = [];
}
