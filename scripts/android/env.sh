#!/bin/bash
KAT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export JAVA_HOME="${JAVA_HOME:-$KAT_ROOT/.build/android-tools/java-home}"
export ANDROID_HOME="${ANDROID_HOME:-$KAT_ROOT/.build/android-tools/sdk}"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-$KAT_ROOT/.build/android-tools/user-home}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$KAT_ROOT/.build/android-tools/gradle-home}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmake/3.22.1/bin:$PATH"
