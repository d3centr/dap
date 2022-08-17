name := "SparkUBI"
version := "0.1.0"

sbtVersion := "1.5.5"
scalaVersion := "2.12.15"

javaOptions ++= Seq("-Xms512M", "-Xmx2048M", "-XX:+CMSClassUnloadingEnabled")

libraryDependencies += "org.scalatest" %% "scalatest" % "3.0.5" % Test
Test / fork := true
Test / parallelExecution := false
Test / javaOptions ++= Seq("-Xms6G", "-Xmx6G", "-XX:+CMSClassUnloadingEnabled")
Test / envVars := Map("SPARKUBI_PROFILING" -> "false")

