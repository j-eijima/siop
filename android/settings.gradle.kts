// Resolves the Java 17 toolchain the modules ask for, downloading it when the
// machine does not have one. Android requires Java 17 bytecode, and the
// developer's JDK is not necessarily that version.
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

rootProject.name = "siop-android"

include(":siopkit")
include(":siop-issue")
