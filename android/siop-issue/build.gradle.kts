plugins {
    kotlin("jvm")
    application
}

kotlin {
    jvmToolchain(17)
}

repositories {
    mavenCentral()
}

dependencies {
    implementation(project(":siopkit"))
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
}

application {
    mainClass.set("jp.co.pendako.siop.tools.MainKt")
}
