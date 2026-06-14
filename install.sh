#!/data/data/com.termux/files/usr/bin/env bash

# ==============================================================================
# Self-Contained Installer for Termux Android Build Tools
# Installs: expo_debug, expo_release, expo_aab, flutter_debug, flutter_release, flutter_aab, kotlin
# ==============================================================================

set -e

echo "=== Installing Termux Build Tools ==="

GLOBAL_BIN="/data/data/com.termux/files/usr/bin"
mkdir -p "$GLOBAL_BIN"

# 1. Install critical system dependencies first
echo "Installing common system dependencies (aapt2, qemu-user-x86-64)..."
pkg update -y
pkg install -y aapt2 qemu-user-x86-64

# ==============================================================================
# 2. Write expo_debug
# ==============================================================================
echo "Installing expo_debug..."
cat << 'EOF' > "$GLOBAL_BIN/expo_debug"
#!/data/data/com.termux/files/usr/bin/env bash

# ==============================================================================
# Expo/React Native Debug Build & Installer Automation for Termux (expo_debug)
# Automatically configures the entire development environment (Node, QEMU, SDK, JDK)
# on first run. If run outside a project, it automatically creates a 'myexpo'
# project, configures Hermes, and builds its Debug APK.
# ==============================================================================

set -e

echo "=== Expo/React Native Debug Build Automation ==="

# 1. Install Node, QEMU, JDK & Android SDK if missing
echo "Checking dependencies..."
DEPS_MISSING=false

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is missing."
  DEPS_MISSING=true
fi
if ! command -v qemu-x86_64 >/dev/null 2>&1; then
  echo "QEMU user-mode x86_64 is missing."
  DEPS_MISSING=true
fi
if [ ! -d "/data/data/com.termux/files/usr/lib/jvm" ] && [ -z "$JAVA_HOME" ]; then
  echo "JDK is missing."
  DEPS_MISSING=true
fi
if [ ! -d "/data/data/com.termux/files/usr/opt/android-sdk" ]; then
  echo "Android SDK is missing."
  DEPS_MISSING=true
fi
if ! command -v aapt2 >/dev/null 2>&1; then
  echo "Native aapt2 is missing."
  DEPS_MISSING=true
fi

if [ "$DEPS_MISSING" = true ]; then
  echo "Installing required dependencies (nodejs, qemu-user-x86-64, openjdk-17, android-sdk, aapt2)..."
  if ! command -v curl >/dev/null 2>&1; then
    pkg install -y curl
  fi
  if [ ! -f "/data/data/com.termux/files/usr/etc/apt/sources.list.d/termuxvoid.list" ]; then
    echo "Adding TermuxVoid repository..."
    curl -sL https://github.com/termuxvoid/repo/raw/main/install.sh | bash
  fi
  pkg update -y
  pkg install -y nodejs qemu-user-x86-64 openjdk-17 android-sdk aapt2
  echo "Dependencies installed successfully!"
fi

# 2. Detect and set JAVA_HOME
echo "Detecting JDK installation..."
JAVA_FOUND=false
if [ -d "/data/data/com.termux/files/usr/lib/jvm/java-17-openjdk" ]; then
  export JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/java-17-openjdk"
  JAVA_FOUND=true
elif [ -d "/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk" ]; then
  export JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk"
  JAVA_FOUND=true
else
  # Search for any installed OpenJDK
  JVM_DIR=$(find /data/data/com.termux/files/usr/lib/jvm -maxdepth 1 -name "*openjdk*" 2>/dev/null | head -n 1 || true)
  if [ -n "$JVM_DIR" ]; then
    export JAVA_HOME="$JVM_DIR"
    JAVA_FOUND=true
  fi
fi
if [ "$JAVA_FOUND" = false ]; then
  echo "Warning: JAVA_HOME could not be set automatically. Defaulting to system java path."
else
  echo "Using JAVA_HOME: $JAVA_HOME"
fi

# 3. Configure Android SDK layout for Termux
USER_SDK="$HOME/.android-sdk-flutter"
SYSTEM_SDK="/data/data/com.termux/files/usr/opt/android-sdk"

if [ -d "$SYSTEM_SDK" ]; then
  if [ ! -d "$USER_SDK/cmdline-tools/latest" ]; then
    echo "Configuring custom Android SDK layout at $USER_SDK..."
    mkdir -p "$USER_SDK/cmdline-tools/latest"
    for d in build-tools cmake licenses ndk platform-tools platforms; do
      if [ -d "$SYSTEM_SDK/$d" ]; then
        ln -sf "$SYSTEM_SDK/$d" "$USER_SDK/$d"
      fi
    done
    if [ -d "$SYSTEM_SDK/cmdline-tools/bin" ]; then
      cp -r "$SYSTEM_SDK/cmdline-tools/bin" "$USER_SDK/cmdline-tools/latest/bin"
      if command -v termux-fix-shebang >/dev/null 2>&1; then
        termux-fix-shebang "$USER_SDK/cmdline-tools/latest/bin/"*
      fi
    fi
    if [ -d "$SYSTEM_SDK/cmdline-tools/lib" ]; then
      ln -sf "$SYSTEM_SDK/cmdline-tools/lib" "$USER_SDK/cmdline-tools/latest/lib"
    fi
    if [ -f "$SYSTEM_SDK/cmdline-tools/source.properties" ]; then
      ln -sf "$SYSTEM_SDK/cmdline-tools/source.properties" "$USER_SDK/cmdline-tools/latest/source.properties"
    fi
  fi
  export ANDROID_HOME="$USER_SDK"
  export ANDROID_SDK_ROOT="$USER_SDK"
else
  echo "Error: Android SDK not found at $SYSTEM_SDK."
  exit 1
fi

# 4. Check if we are inside a React Native/Expo project, if not create 'myexpo'
if [ ! -d "android" ]; then
  if [ -d "../android" ]; then
    cd ..
  else
    echo "You are not inside a React Native/Expo project."
    if [ -d "myexpo" ] && [ -d "myexpo/android" ]; then
      echo "Found existing 'myexpo' directory. Moving into it..."
      cd myexpo
    else
      echo "Creating a new default Expo project 'myexpo'..."
      npx -y create-expo-app@latest myexpo --template blank --no-install
      cd myexpo
      echo "Installing npm dependencies..."
      npm install --legacy-peer-deps
      echo "Generating Android native folder using Expo prebuild..."
      npx expo prebuild --platform android --no-install
    fi
  fi
fi

# 5. Create a temporary directory for Hermes build hook scripts
TEMP_DIR=$(mktemp -d -t expo_build_XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM

# 6. Create the temporary hermesc wrapper
cat << 'EOF2' > "$TEMP_DIR/hermesc"
#!/bin/sh
# Temporary hermesc wrapper for Termux aarch64
DIR="$PWD"
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
    TARGET="$DIR/node_modules/hermes-compiler/hermesc/linux64-bin/hermesc"
    if [ -f "$TARGET" ]; then
        if head -n 1 "$TARGET" | grep -q "ELF"; then
            exec qemu-x86_64 "$TARGET" "$@"
        elif [ -f "${TARGET}.real" ]; then
            exec qemu-x86_64 "${TARGET}.real" "$@"
        fi
    fi
    DIR="$(dirname "$DIR")"
done

DIR="$PWD"
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
    TARGET="$DIR/node_modules/react-native/sdks/hermesc/linux64-bin/hermesc"
    if [ -f "$TARGET" ]; then
        if head -n 1 "$TARGET" | grep -q "ELF"; then
            exec qemu-x86_64 "$TARGET" "$@"
        elif [ -f "${TARGET}.real" ]; then
            exec qemu-x86_64 "${TARGET}.real" "$@"
        fi
    fi
    DIR="$(dirname "$DIR")"
done

echo "Error: hermesc binary not found in node_modules traversal" >&2
exit 1
EOF2
chmod +x "$TEMP_DIR/hermesc"

# 7. Create the temporary Gradle init script pointing to the wrapper
cat << EOF2 > "$TEMP_DIR/init.gradle"
gradle.projectsLoaded {
    rootProject.allprojects { project ->
        project.plugins.withId("com.facebook.react") {
            project.logger.lifecycle("[Termux-Hermes-Fix] Configuring dynamic hermesCommand wrapper for project: \${project.name}")
            project.react {
                hermesCommand = "$TEMP_DIR/hermesc"
            }
            project.afterEvaluate {
                project.react {
                    hermesCommand = "$TEMP_DIR/hermesc"
                }
            }
        }
    }
}
EOF2

# 8. Fix the gradle wrapper shebang if needed (Termux requires local shebang format)
if [ -f "android/gradlew" ]; then
  echo "Checking gradle wrapper shebang..."
  if grep -q "/usr/bin/env" "android/gradlew" 2>/dev/null; then
    echo "Fixing shebang in android/gradlew..."
    if command -v termux-fix-shebang >/dev/null 2>&1; then
      termux-fix-shebang android/gradlew
    fi
  fi
  chmod +x android/gradlew
fi

# 9. Determine build target tasks (Only Debug APK)
BUILD_TASKS="assembleDebug"

# 10. Run Gradle build using the dynamic init script
echo "============================================================"
echo " Starting Expo Android Build (Debug Mode)..."
echo "============================================================"
cd android
./gradlew -I "$TEMP_DIR/init.gradle" $BUILD_TASKS -Pandroid.aapt2FromMavenOverride=/data/data/com.termux/files/usr/bin/aapt2

BUILD_RESULT=$?
cd ..

if [ $BUILD_RESULT -eq 0 ]; then
    echo ""
    echo "============================================================"
    echo " 🎉 BUILD SUCCESSFUL!"
    echo " APK Location: android/app/build/outputs/apk/debug/app-debug.apk"
    echo "============================================================"
    
    # 11. Self-install globally upon successful build
    SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0")
    GLOBAL_PATH="/data/data/com.termux/files/usr/bin/expo_debug"
    
    echo "Making script globally executable..."
    if [ "$SCRIPT_PATH" != "$GLOBAL_PATH" ]; then
        cp "$SCRIPT_PATH" "$GLOBAL_PATH"
        chmod +x "$GLOBAL_PATH"
        echo "Script successfully installed globally at $GLOBAL_PATH!"
        echo "You can now run it from anywhere using the 'expo_debug' command."
    fi
else
    echo ""
    echo "============================================================"
    echo " ❌ BUILD FAILED!"
    echo "============================================================"
fi

exit $BUILD_RESULT
EOF
chmod +x "$GLOBAL_BIN/expo_debug"

# ==============================================================================
# 3. Write expo_release
# ==============================================================================
echo "Installing expo_release..."
cat << 'EOF' > "$GLOBAL_BIN/expo_release"
#!/data/data/com.termux/files/usr/bin/env bash

# ==============================================================================
# Expo/React Native Release Build & Installer Automation for Termux (expo_release)
# Automatically configures the entire development environment (Node, QEMU, SDK, JDK)
# on first run. If run outside a project, it automatically creates a 'myexpo'
# project, configures Hermes, and builds its Release APK.
# ==============================================================================

set -e

echo "=== Expo/React Native Release Build Automation ==="

# 1. Install Node, QEMU, JDK & Android SDK if missing
echo "Checking dependencies..."
DEPS_MISSING=false

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is missing."
  DEPS_MISSING=true
fi
if ! command -v qemu-x86_64 >/dev/null 2>&1; then
  echo "QEMU user-mode x86_64 is missing."
  DEPS_MISSING=true
fi
if [ ! -d "/data/data/com.termux/files/usr/lib/jvm" ] && [ -z "$JAVA_HOME" ]; then
  echo "JDK is missing."
  DEPS_MISSING=true
fi
if [ ! -d "/data/data/com.termux/files/usr/opt/android-sdk" ]; then
  echo "Android SDK is missing."
  DEPS_MISSING=true
fi
if ! command -v aapt2 >/dev/null 2>&1; then
  echo "Native aapt2 is missing."
  DEPS_MISSING=true
fi

if [ "$DEPS_MISSING" = true ]; then
  echo "Installing required dependencies (nodejs, qemu-user-x86-64, openjdk-17, android-sdk, aapt2)..."
  if ! command -v curl >/dev/null 2>&1; then
    pkg install -y curl
  fi
  if [ ! -f "/data/data/com.termux/files/usr/etc/apt/sources.list.d/termuxvoid.list" ]; then
    echo "Adding TermuxVoid repository..."
    curl -sL https://github.com/termuxvoid/repo/raw/main/install.sh | bash
  fi
  pkg update -y
  pkg install -y nodejs qemu-user-x86-64 openjdk-17 android-sdk aapt2
  echo "Dependencies installed successfully!"
fi

# 2. Detect and set JAVA_HOME
echo "Detecting JDK installation..."
JAVA_FOUND=false
if [ -d "/data/data/com.termux/files/usr/lib/jvm/java-17-openjdk" ]; then
  export JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/java-17-openjdk"
  JAVA_FOUND=true
elif [ -d "/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk" ]; then
  export JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk"
  JAVA_FOUND=true
else
  # Search for any installed OpenJDK
  JVM_DIR=$(find /data/data/com.termux/files/usr/lib/jvm -maxdepth 1 -name "*openjdk*" 2>/dev/null | head -n 1 || true)
  if [ -n "$JVM_DIR" ]; then
    export JAVA_HOME="$JVM_DIR"
    JAVA_FOUND=true
  fi
fi
if [ "$JAVA_FOUND" = false ]; then
  echo "Warning: JAVA_HOME could not be set automatically. Defaulting to system java path."
else
  echo "Using JAVA_HOME: $JAVA_HOME"
fi

# 3. Configure Android SDK layout for Termux
USER_SDK="$HOME/.android-sdk-flutter"
SYSTEM_SDK="/data/data/com.termux/files/usr/opt/android-sdk"

if [ -d "$SYSTEM_SDK" ]; then
  if [ ! -d "$USER_SDK/cmdline-tools/latest" ]; then
    echo "Configuring custom Android SDK layout at $USER_SDK..."
    mkdir -p "$USER_SDK/cmdline-tools/latest"
    for d in build-tools cmake licenses ndk platform-tools platforms; do
      if [ -d "$SYSTEM_SDK/$d" ]; then
        ln -sf "$SYSTEM_SDK/$d" "$USER_SDK/$d"
      fi
    done
    if [ -d "$SYSTEM_SDK/cmdline-tools/bin" ]; then
      cp -r "$SYSTEM_SDK/cmdline-tools/bin" "$USER_SDK/cmdline-tools/latest/bin"
      if command -v termux-fix-shebang >/dev/null 2>&1; then
        termux-fix-shebang "$USER_SDK/cmdline-tools/latest/bin/"*
      fi
    fi
    if [ -d "$SYSTEM_SDK/cmdline-tools/lib" ]; then
      ln -sf "$SYSTEM_SDK/cmdline-tools/lib" "$USER_SDK/cmdline-tools/latest/lib"
    fi
    if [ -f "$SYSTEM_SDK/cmdline-tools/source.properties" ]; then
      ln -sf "$SYSTEM_SDK/cmdline-tools/source.properties" "$USER_SDK/cmdline-tools/latest/source.properties"
    fi
  fi
  export ANDROID_HOME="$USER_SDK"
  export ANDROID_SDK_ROOT="$USER_SDK"
else
  echo "Error: Android SDK not found at $SYSTEM_SDK."
  exit 1
fi

# 4. Check if we are inside a React Native/Expo project, if not create 'myexpo'
if [ ! -d "android" ]; then
  if [ -d "../android" ]; then
    cd ..
  else
    echo "You are not inside a React Native/Expo project."
    if [ -d "myexpo" ] && [ -d "myexpo/android" ]; then
      echo "Found existing 'myexpo' directory. Moving into it..."
      cd myexpo
    else
      echo "Creating a new default Expo project 'myexpo'..."
      npx -y create-expo-app@latest myexpo --template blank --no-install
      cd myexpo
      echo "Installing npm dependencies..."
      npm install --legacy-peer-deps
      echo "Generating Android native folder using Expo prebuild..."
      npx expo prebuild --platform android --no-install
    fi
  fi
fi

# 5. Create a temporary directory for Hermes build hook scripts
TEMP_DIR=$(mktemp -d -t expo_build_XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM

# 6. Create the temporary hermesc wrapper
cat << 'EOF2' > "$TEMP_DIR/hermesc"
#!/bin/sh
# Temporary hermesc wrapper for Termux aarch64
DIR="$PWD"
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
    TARGET="$DIR/node_modules/hermes-compiler/hermesc/linux64-bin/hermesc"
    if [ -f "$TARGET" ]; then
        if head -n 1 "$TARGET" | grep -q "ELF"; then
            exec qemu-x86_64 "$TARGET" "$@"
        elif [ -f "${TARGET}.real" ]; then
            exec qemu-x86_64 "${TARGET}.real" "$@"
        fi
    fi
    DIR="$(dirname "$DIR")"
done

DIR="$PWD"
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
    TARGET="$DIR/node_modules/react-native/sdks/hermesc/linux64-bin/hermesc"
    if [ -f "$TARGET" ]; then
        if head -n 1 "$TARGET" | grep -q "ELF"; then
            exec qemu-x86_64 "$TARGET" "$@"
        elif [ -f "${TARGET}.real" ]; then
            exec qemu-x86_64 "${TARGET}.real" "$@"
        fi
    fi
    DIR="$(dirname "$DIR")"
done

echo "Error: hermesc binary not found in node_modules traversal" >&2
exit 1
EOF2
chmod +x "$TEMP_DIR/hermesc"

# 7. Create the temporary Gradle init script pointing to the wrapper
cat << EOF2 > "$TEMP_DIR/init.gradle"
gradle.projectsLoaded {
    rootProject.allprojects { project ->
        project.plugins.withId("com.facebook.react") {
            project.logger.lifecycle("[Termux-Hermes-Fix] Configuring dynamic hermesCommand wrapper for project: \${project.name}")
            project.react {
                hermesCommand = "$TEMP_DIR/hermesc"
            }
            project.afterEvaluate {
                project.react {
                    hermesCommand = "$TEMP_DIR/hermesc"
                }
            }
        }
    }
}
EOF2

# 8. Fix the gradle wrapper shebang if needed (Termux requires local shebang format)
if [ -f "android/gradlew" ]; then
  echo "Checking gradle wrapper shebang..."
  if grep -q "/usr/bin/env" "android/gradlew" 2>/dev/null; then
    echo "Fixing shebang in android/gradlew..."
    if command -v termux-fix-shebang >/dev/null 2>&1; then
      termux-fix-shebang android/gradlew
    fi
  fi
  chmod +x android/gradlew
fi

# 9. Determine build target tasks (Only Release APK)
BUILD_TASKS="assembleRelease"

# 10. Run Gradle build using the dynamic init script
echo "============================================================"
echo " Starting Expo Android Build (Release Mode)..."
echo "============================================================"
cd android
./gradlew -I "$TEMP_DIR/init.gradle" $BUILD_TASKS -Pandroid.aapt2FromMavenOverride=/data/data/com.termux/files/usr/bin/aapt2

BUILD_RESULT=$?
cd ..

if [ $BUILD_RESULT -eq 0 ]; then
    echo ""
    echo "============================================================"
    echo " 🎉 BUILD SUCCESSFUL!"
    echo " APK Location: android/app/build/outputs/apk/release/app-release.apk"
    echo "============================================================"
    
    # 11. Self-install globally upon successful build
    SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0")
    GLOBAL_PATH="/data/data/com.termux/files/usr/bin/expo_release"
    
    echo "Making script globally executable..."
    if [ "$SCRIPT_PATH" != "$GLOBAL_PATH" ]; then
        cp "$SCRIPT_PATH" "$GLOBAL_PATH"
        chmod +x "$GLOBAL_PATH"
        echo "Script successfully installed globally at $GLOBAL_PATH!"
        echo "You can now run it from anywhere using the 'expo_release' command."
    fi
else
    echo ""
    echo "============================================================"
    echo " ❌ BUILD FAILED!"
    echo "============================================================"
fi

exit $BUILD_RESULT
EOF
chmod +x "$GLOBAL_BIN/expo_release"

# ==============================================================================
# 4. Write expo_aab
# ==============================================================================
echo "Installing expo_aab / expo_AAB..."
cat << 'EOF' > "$GLOBAL_BIN/expo_aab"
#!/data/data/com.termux/files/usr/bin/env bash

# ==============================================================================
# Expo/React Native App Bundle Build & Installer Automation for Termux (expo_aab)
# Automatically configures the entire development environment (Node, QEMU, SDK, JDK)
# on first run. If run outside a project, it automatically creates a 'myexpo'
# project, configures Hermes, and builds its Android App Bundle (AAB).
# ==============================================================================

set -e

echo "=== Expo/React Native App Bundle (AAB) Build Automation ==="

# 1. Install Node, QEMU, JDK & Android SDK if missing
echo "Checking dependencies..."
DEPS_MISSING=false

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is missing."
  DEPS_MISSING=true
fi
if ! command -v qemu-x86_64 >/dev/null 2>&1; then
  echo "QEMU user-mode x86_64 is missing."
  DEPS_MISSING=true
fi
if [ ! -d "/data/data/com.termux/files/usr/lib/jvm" ] && [ -z "$JAVA_HOME" ]; then
  echo "JDK is missing."
  DEPS_MISSING=true
fi
if [ ! -d "/data/data/com.termux/files/usr/opt/android-sdk" ]; then
  echo "Android SDK is missing."
  DEPS_MISSING=true
fi
if ! command -v aapt2 >/dev/null 2>&1; then
  echo "Native aapt2 is missing."
  DEPS_MISSING=true
fi

if [ "$DEPS_MISSING" = true ]; then
  echo "Installing required dependencies (nodejs, qemu-user-x86-64, openjdk-17, android-sdk, aapt2)..."
  if ! command -v curl >/dev/null 2>&1; then
    pkg install -y curl
  fi
  if [ ! -f "/data/data/com.termux/files/usr/etc/apt/sources.list.d/termuxvoid.list" ]; then
    echo "Adding TermuxVoid repository..."
    curl -sL https://github.com/termuxvoid/repo/raw/main/install.sh | bash
  fi
  pkg update -y
  pkg install -y nodejs qemu-user-x86-64 openjdk-17 android-sdk aapt2
  echo "Dependencies installed successfully!"
fi

# 2. Detect and set JAVA_HOME
echo "Detecting JDK installation..."
JAVA_FOUND=false
if [ -d "/data/data/com.termux/files/usr/lib/jvm/java-17-openjdk" ]; then
  export JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/java-17-openjdk"
  JAVA_FOUND=true
elif [ -d "/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk" ]; then
  export JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk"
  JAVA_FOUND=true
else
  # Search for any installed OpenJDK
  JVM_DIR=$(find /data/data/com.termux/files/usr/lib/jvm -maxdepth 1 -name "*openjdk*" 2>/dev/null | head -n 1 || true)
  if [ -n "$JVM_DIR" ]; then
    export JAVA_HOME="$JVM_DIR"
    JAVA_FOUND=true
  fi
fi
if [ "$JAVA_FOUND" = false ]; then
  echo "Warning: JAVA_HOME could not be set automatically. Defaulting to system java path."
else
  echo "Using JAVA_HOME: $JAVA_HOME"
fi

# 3. Configure Android SDK layout for Termux
USER_SDK="$HOME/.android-sdk-flutter"
SYSTEM_SDK="/data/data/com.termux/files/usr/opt/android-sdk"

if [ -d "$SYSTEM_SDK" ]; then
  if [ ! -d "$USER_SDK/cmdline-tools/latest" ]; then
    echo "Configuring custom Android SDK layout at $USER_SDK..."
    mkdir -p "$USER_SDK/cmdline-tools/latest"
    for d in build-tools cmake licenses ndk platform-tools platforms; do
      if [ -d "$SYSTEM_SDK/$d" ]; then
        ln -sf "$SYSTEM_SDK/$d" "$USER_SDK/$d"
      fi
    done
    if [ -d "$SYSTEM_SDK/cmdline-tools/bin" ]; then
      cp -r "$SYSTEM_SDK/cmdline-tools/bin" "$USER_SDK/cmdline-tools/latest/bin"
      if command -v termux-fix-shebang >/dev/null 2>&1; then
        termux-fix-shebang "$USER_SDK/cmdline-tools/latest/bin/"*
      fi
    fi
    if [ -d "$SYSTEM_SDK/cmdline-tools/lib" ]; then
      ln -sf "$SYSTEM_SDK/cmdline-tools/lib" "$USER_SDK/cmdline-tools/latest/lib"
    fi
    if [ -f "$SYSTEM_SDK/cmdline-tools/source.properties" ]; then
      ln -sf "$SYSTEM_SDK/cmdline-tools/source.properties" "$USER_SDK/cmdline-tools/latest/source.properties"
    fi
  fi
  export ANDROID_HOME="$USER_SDK"
  export ANDROID_SDK_ROOT="$USER_SDK"
else
  echo "Error: Android SDK not found at $SYSTEM_SDK."
  exit 1
fi

# 4. Check if we are inside a React Native/Expo project, if not create 'myexpo'
if [ ! -d "android" ]; then
  if [ -d "../android" ]; then
    cd ..
  else
    echo "You are not inside a React Native/Expo project."
    if [ -d "myexpo" ] && [ -d "myexpo/android" ]; then
      echo "Found existing 'myexpo' directory. Moving into it..."
      cd myexpo
    else
      echo "Creating a new default Expo project 'myexpo'..."
      npx -y create-expo-app@latest myexpo --template blank --no-install
      cd myexpo
      echo "Installing npm dependencies..."
      npm install --legacy-peer-deps
      echo "Generating Android native folder using Expo prebuild..."
      npx expo prebuild --platform android --no-install
    fi
  fi
fi

# 5. Create a temporary directory for Hermes build hook scripts
TEMP_DIR=$(mktemp -d -t expo_build_XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM

# 6. Create the temporary hermesc wrapper
cat << 'EOF2' > "$TEMP_DIR/hermesc"
#!/bin/sh
# Temporary hermesc wrapper for Termux aarch64
DIR="$PWD"
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
    TARGET="$DIR/node_modules/hermes-compiler/hermesc/linux64-bin/hermesc"
    if [ -f "$TARGET" ]; then
        if head -n 1 "$TARGET" | grep -q "ELF"; then
            exec qemu-x86_64 "$TARGET" "$@"
        elif [ -f "${TARGET}.real" ]; then
            exec qemu-x86_64 "${TARGET}.real" "$@"
        fi
    fi
    DIR="$(dirname "$DIR")"
done

DIR="$PWD"
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
    TARGET="$DIR/node_modules/react-native/sdks/hermesc/linux64-bin/hermesc"
    if [ -f "$TARGET" ]; then
        if head -n 1 "$TARGET" | grep -q "ELF"; then
            exec qemu-x86_64 "$TARGET" "$@"
        elif [ -f "${TARGET}.real" ]; then
            exec qemu-x86_64 "${TARGET}.real" "$@"
        fi
    fi
    DIR="$(dirname "$DIR")"
done

echo "Error: hermesc binary not found in node_modules traversal" >&2
exit 1
EOF2
chmod +x "$TEMP_DIR/hermesc"

# 7. Create the temporary Gradle init script pointing to the wrapper
cat << EOF2 > "$TEMP_DIR/init.gradle"
gradle.projectsLoaded {
    rootProject.allprojects { project ->
        project.plugins.withId("com.facebook.react") {
            project.logger.lifecycle("[Termux-Hermes-Fix] Configuring dynamic hermesCommand wrapper for project: \${project.name}")
            project.react {
                hermesCommand = "$TEMP_DIR/hermesc"
            }
            project.afterEvaluate {
                project.react {
                    hermesCommand = "$TEMP_DIR/hermesc"
                }
            }
        }
    }
}
EOF2

# 8. Fix the gradle wrapper shebang if needed (Termux requires local shebang format)
if [ -f "android/gradlew" ]; then
  echo "Checking gradle wrapper shebang..."
  if grep -q "/usr/bin/env" "android/gradlew" 2>/dev/null; then
    echo "Fixing shebang in android/gradlew..."
    if command -v termux-fix-shebang >/dev/null 2>&1; then
      termux-fix-shebang android/gradlew
    fi
  fi
  chmod +x android/gradlew
fi

# 9. Determine build target tasks (Only App Bundle AAB)
BUILD_TASKS="bundleRelease"

# 10. Run Gradle build using the dynamic init script
echo "============================================================"
echo " Starting Expo Android Build (AAB Mode)..."
echo "============================================================"
cd android
./gradlew -I "$TEMP_DIR/init.gradle" $BUILD_TASKS -Pandroid.aapt2FromMavenOverride=/data/data/com.termux/files/usr/bin/aapt2

BUILD_RESULT=$?
cd ..

if [ $BUILD_RESULT -eq 0 ]; then
    echo ""
    echo "============================================================"
    echo " 🎉 BUILD SUCCESSFUL!"
    echo " AAB Location: android/app/build/outputs/bundle/release/app-release.aab"
    echo "============================================================"
    
    # 11. Self-install globally upon successful build
    SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0")
    
    echo "Making script globally executable..."
    # Install as expo_aab
    cp "$SCRIPT_PATH" "/data/data/com.termux/files/usr/bin/expo_aab"
    chmod +x "/data/data/com.termux/files/usr/bin/expo_aab"
    
    # Install as expo_AAB
    cp "$SCRIPT_PATH" "/data/data/com.termux/files/usr/bin/expo_AAB"
    chmod +x "/data/data/com.termux/files/usr/bin/expo_AAB"
    
    echo "Script successfully installed globally!"
    echo "You can now run it using the 'expo_aab' or 'expo_AAB' command."
fi

exit $BUILD_RESULT
EOF
chmod +x "$GLOBAL_BIN/expo_aab"
cp "$GLOBAL_BIN/expo_aab" "$GLOBAL_BIN/expo_AAB"
chmod +x "$GLOBAL_BIN/expo_AAB"

# ==============================================================================
# 5. Write flutter_debug
# ==============================================================================
echo "Installing flutter_debug..."
cat << 'EOF' > "$GLOBAL_BIN/flutter_debug"
#!/data/data/com.termux/files/usr/bin/env bash

# ==============================================================================
# Flutter Debug Build & Installer Automation for Termux (flutter_debug)
# Automatically configures the entire development environment (TermuxVoid,
# Flutter, Android SDK, JDK) on first run. If run outside a project, it 
# automatically creates a 'myapp' project and builds its APK.
# ONLY supports building Debug APKs for stability.
# ==============================================================================

set -e

echo "=== Flutter Debug Build & Installer Automation for Termux ==="

# 1. Install Flutter & dependencies if missing (for fresh Termux installations)
if ! command -v flutter >/dev/null 2>&1 && [ ! -d "/data/data/com.termux/files/usr/opt/flutter" ]; then
  echo "Flutter is not installed. Setting up TermuxVoid repository..."
  
  # Ensure curl is installed
  if ! command -v curl >/dev/null 2>&1; then
    echo "Installing curl..."
    pkg install -y curl
  fi
  
  # Install TermuxVoid repo
  echo "Configuring TermuxVoid repository..."
  curl -sL https://github.com/termuxvoid/repo/raw/main/install.sh | bash
  
  # Update package lists
  echo "Updating package index..."
  pkg update -y
  
  # Install Flutter, Android SDK, and JDK
  echo "Installing Flutter, Android SDK, and JDK..."
  pkg install -y flutter android-sdk openjdk-17
  
  echo "Core installation complete!"
fi

# 2. Add Flutter binaries to PATH if they exist in the standard Termux location
FLUTTER_BIN_DIR="/data/data/com.termux/files/usr/opt/flutter/bin"
if [ -d "$FLUTTER_BIN_DIR" ]; then
  export PATH="$FLUTTER_BIN_DIR:$PATH"
fi

# 2.5 Auto-apply Termux environment fixes
echo "Auto-applying Termux environment fixes..."

# Fix Flutter SDK shebangs if needed
if command -v termux-fix-shebang >/dev/null 2>&1; then
  termux-fix-shebang "$FLUTTER_BIN_DIR/flutter" "$FLUTTER_BIN_DIR/dart" "$FLUTTER_BIN_DIR/flutter-dev" 2>/dev/null || true
  find "$FLUTTER_BIN_DIR/internal" -type f -exec termux-fix-shebang {} + 2>/dev/null || true
fi

# Symlink native CMake and Ninja to version 3.22.1 in the Android SDK
SDK_CMAKE_DIR="/data/data/com.termux/files/usr/opt/android-sdk/cmake"
if [ -d "$SDK_CMAKE_DIR/4.1.2/bin" ] && [ -d "$SDK_CMAKE_DIR/3.22.1/bin" ]; then
  if [ ! -f "$SDK_CMAKE_DIR/3.22.1/bin/cmake.bak" ] && [ -f "$SDK_CMAKE_DIR/3.22.1/bin/cmake" ]; then
    echo "Symlinking native CMake & Ninja to SDK 3.22.1..."
    mv "$SDK_CMAKE_DIR/3.22.1/bin/cmake" "$SDK_CMAKE_DIR/3.22.1/bin/cmake.bak" 2>/dev/null || true
    mv "$SDK_CMAKE_DIR/3.22.1/bin/ninja" "$SDK_CMAKE_DIR/3.22.1/bin/ninja.bak" 2>/dev/null || true
    ln -sf "$SDK_CMAKE_DIR/4.1.2/bin/cmake" "$SDK_CMAKE_DIR/3.22.1/bin/cmake"
    ln -sf "$SDK_CMAKE_DIR/4.1.2/bin/ninja" "$SDK_CMAKE_DIR/3.22.1/bin/ninja"
  fi
fi

# Patch Flutter SDK FlutterPluginUtils.kt to bypass NDK download checks
UTILS_KT="/data/data/com.termux/files/usr/opt/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterPluginUtils.kt"
if [ -f "$UTILS_KT" ]; then
  if grep -q "internal fun forceNdkDownload(" "$UTILS_KT" && ! grep -q "internal fun forceNdkDownload(.*) {}" "$UTILS_KT"; then
    echo "Patching FlutterPluginUtils.kt to bypass NDK compilation checks..."
    python3 -c '
import pathlib, re
p = pathlib.Path("'"$UTILS_KT"'")
content = p.read_text()
target_block = "internal fun forceNdkDownload"
if target_block in content:
    pattern = r"internal fun forceNdkDownload\([\s\S]*?\}\n\n\s+@JvmStatic\n\s+@JvmName\(\"isFlutterAppProject\"\)"
    replacement = "internal fun forceNdkDownload(\n        gradleProject: Project,\n        flutterSdkRootPath: String\n    ) {}\n\n    @JvmStatic\n    @JvmName(\"isFlutterAppProject\")"
    new_content, count = re.subn(pattern, replacement, content)
    if count > 0:
        p.write_text(new_content)
        print("FlutterPluginUtils.kt successfully patched!")
' 2>/dev/null || true
  fi
fi

# 3. Check if we are in a Flutter project directory. If not, create a default 'myapp' project.
if [ ! -f "pubspec.yaml" ] || [ ! -d "android" ]; then
  echo "You are not inside a Flutter project directory."
  if [ -d "myapp" ] && [ -f "myapp/pubspec.yaml" ] && [ -d "myapp/android" ]; then
    echo "Found existing 'myapp' directory. Moving into it..."
    cd myapp
  else
    echo "Creating a new default Flutter project 'myapp'..."
    flutter create myapp
    cd myapp
  fi
fi

# Auto-configure project SDK versions to 34 (to bypass AAPT2 API 36 issue)
if [ -f "android/app/build.gradle.kts" ]; then
  if grep -q "compileSdk = flutter.compileSdkVersion" android/app/build.gradle.kts; then
    echo "Updating android/app/build.gradle.kts to target API 34..."
    sed -i 's/compileSdk = flutter.compileSdkVersion/compileSdk = 34/g' android/app/build.gradle.kts
    sed -i 's/targetSdk = flutter.targetSdkVersion/targetSdk = 34/g' android/app/build.gradle.kts
  fi
fi
if [ -f "android/app/build.gradle" ]; then
  if grep -q "compileSdkVersion flutter.compileSdkVersion" android/app/build.gradle; then
    echo "Updating android/app/build.gradle to target API 34..."
    sed -i 's/compileSdkVersion flutter.compileSdkVersion/compileSdkVersion 34/g' android/app/build.gradle
    sed -i 's/targetSdkVersion flutter.targetSdkVersion/targetSdkVersion 34/g' android/app/build.gradle
  fi
fi

# 4. Detect and set JAVA_HOME, fix if missing
echo "Detecting JDK installation..."
JAVA_FOUND=false
if [ -d "/data/data/com.termux/files/usr/lib/jvm/java-17-openjdk" ]; then
  export JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/java-17-openjdk"
  JAVA_FOUND=true
elif [ -d "/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk" ]; then
  export JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk"
  JAVA_FOUND=true
else
  # Search for any installed OpenJDK
  JVM_DIR=$(find /data/data/com.termux/files/usr/lib/jvm -maxdepth 1 -name "*openjdk*" 2>/dev/null | head -n 1 || true)
  if [ -n "$JVM_DIR" ]; then
    export JAVA_HOME="$JVM_DIR"
    JAVA_FOUND=true
  fi
fi

if [ "$JAVA_FOUND" = false ]; then
  echo "Warning: No JDK installation found. Attempting to install openjdk-17..."
  pkg install -y openjdk-17
  export JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/java-17-openjdk"
fi

echo "Using JAVA_HOME: $JAVA_HOME"

# 5. Configure / Fix Android SDK and commandline-tools
USER_SDK="$HOME/.android-sdk-flutter"
SYSTEM_SDK="/data/data/com.termux/files/usr/opt/android-sdk"

if [ ! -d "$SYSTEM_SDK" ]; then
  echo "Warning: System Android SDK not found at $SYSTEM_SDK."
  echo "Attempting to install android-sdk..."
  pkg install -y android-sdk || true
fi

if [ -d "$SYSTEM_SDK" ]; then
  if [ ! -d "$USER_SDK/cmdline-tools/latest" ]; then
    echo "Setting up custom Android SDK layout at $USER_SDK..."
    mkdir -p "$USER_SDK/cmdline-tools/latest"
    
    # Symlink major SDK directories
    for d in build-tools cmake licenses ndk platform-tools platforms; do
      if [ -d "$SYSTEM_SDK/$d" ]; then
        ln -sf "$SYSTEM_SDK/$d" "$USER_SDK/$d"
      fi
    done
    
    # Copy cmdline-tools/bin to latest/bin and fix shebangs
    if [ -d "$SYSTEM_SDK/cmdline-tools/bin" ]; then
      cp -r "$SYSTEM_SDK/cmdline-tools/bin" "$USER_SDK/cmdline-tools/latest/bin"
      if command -v termux-fix-shebang >/dev/null 2>&1; then
        termux-fix-shebang "$USER_SDK/cmdline-tools/latest/bin/"*
      fi
    fi
    
    # Symlink remaining cmdline-tools files/dirs
    if [ -d "$SYSTEM_SDK/cmdline-tools/lib" ]; then
      ln -sf "$SYSTEM_SDK/cmdline-tools/lib" "$USER_SDK/cmdline-tools/latest/lib"
    fi
    if [ -f "$SYSTEM_SDK/cmdline-tools/source.properties" ]; then
      ln -sf "$SYSTEM_SDK/cmdline-tools/source.properties" "$USER_SDK/cmdline-tools/latest/source.properties"
    fi
    
    echo "Custom Android SDK layout configured successfully."
  fi

  export ANDROID_HOME="$USER_SDK"
  export ANDROID_SDK_ROOT="$USER_SDK"
  
  # Ensure Flutter is configured to use the custom SDK layout
  CURRENT_FLUTTER_SDK=$(flutter config --list 2>/dev/null | grep "android-sdk:" | awk '{print $2}' | tr -d '"' || true)
  if [ "$CURRENT_FLUTTER_SDK" != "$USER_SDK" ]; then
    echo "Updating flutter config --android-sdk to: $USER_SDK"
    flutter config --android-sdk "$USER_SDK" >/dev/null 2>&1
  fi
else
  echo "Error: Android SDK could not be configured."
  exit 1
fi

# 6. Ensure native aapt2 is installed
if ! command -v aapt2 >/dev/null 2>&1; then
  echo "Installing native aapt2..."
  pkg install -y aapt2
fi

# 7. Fix the gradle wrapper shebang if needed (Termux requires local shebang format)
if [ -f "android/gradlew" ]; then
  echo "Checking gradle wrapper shebang..."
  # If it has standard /usr/bin/env, run termux-fix-shebang
  if grep -q "/usr/bin/env" "android/gradlew" 2>/dev/null; then
    echo "Fixing shebang in android/gradlew..."
    if command -v termux-fix-shebang >/dev/null 2>&1; then
      termux-fix-shebang android/gradlew
    fi
  fi
  chmod +x android/gradlew
fi

# 8. Run Flutter build command (Debug Mode ONLY) with temporary aapt2 override
echo "Starting Flutter Build (Debug Mode)..."

ARGS=()
# If arguments were passed, clean them to ensure only debug config is built
IS_APPBUNDLE=false
for arg in "$@"; do
  if [ "$arg" = "appbundle" ]; then
    IS_APPBUNDLE=true
  fi
done

if [ "$IS_APPBUNDLE" = true ]; then
  ARGS=("appbundle" "--debug" "--target-platform=android-arm64")
else
  ARGS=("apk" "--debug" "--target-platform=android-arm64")
fi

# Apply temporary override
if [ -d "android" ]; then
  touch android/gradle.properties
  cp android/gradle.properties android/gradle.properties.bak
  grep -v "android.aapt2FromMavenOverride" android/gradle.properties.bak > android/gradle.properties || true
  echo "android.aapt2FromMavenOverride=/data/data/com.termux/files/usr/bin/aapt2" >> android/gradle.properties
fi

# Ensure restore happens on exit
trap 'if [ -f "android/gradle.properties.bak" ]; then mv android/gradle.properties.bak android/gradle.properties; fi' EXIT INT TERM

flutter build "${ARGS[@]}"

# Restore immediately if completed normally
if [ -f "android/gradle.properties.bak" ]; then
  mv android/gradle.properties.bak android/gradle.properties
fi

echo "=== Build Finished successfully! ==="

# 9. Self-install globally upon successful build
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0")
GLOBAL_PATH="/data/data/com.termux/files/usr/bin/flutter_debug"

echo "Making script globally executable..."
if [ "$SCRIPT_PATH" != "$GLOBAL_PATH" ]; then
  cp "$SCRIPT_PATH" "$GLOBAL_PATH"
  chmod +x "$GLOBAL_PATH"
  echo "Script successfully installed globally at $GLOBAL_PATH!"
  echo "You can now run it from anywhere using the 'flutter_debug' command."
fi
EOF
chmod +x "$GLOBAL_BIN/flutter_debug"

# ==============================================================================
# 6. Write flutter_release
# ==============================================================================
echo "Installing flutter_release..."
cat << 'EOF' > "$GLOBAL_BIN/flutter_release"
#!/data/data/com.termux/files/usr/bin/env bash

# ==============================================================================
# Flutter Release Build Automation for Termux (flutter_release)
# Configures a full Ubuntu container via proot-distro to compile standard,
# non-crashing Release APKs.
# ==============================================================================

set -e

echo "=== Flutter Release Build Automation (using PRoot Ubuntu) ==="

# 1. Ensure proot-distro is installed on the host
if ! command -v proot-distro >/dev/null 2>&1; then
  echo "Installing proot-distro..."
  pkg install -y proot-distro
fi

# 2. Ensure Ubuntu distro is installed inside proot-distro
if [ ! -d "/data/data/com.termux/files/usr/var/lib/proot-distro/installed-distros/ubuntu" ]; then
  echo "Installing Ubuntu container via proot-distro (this may take a few minutes)..."
  proot-distro install ubuntu
fi

# 3. Check if we are inside a Flutter project. If not, create a default 'myapp' project.
if [ ! -f "pubspec.yaml" ] || [ ! -d "android" ]; then
  echo "You are not inside a Flutter project directory."
  if [ -d "myapp" ] && [ -f "myapp/pubspec.yaml" ] && [ -d "myapp/android" ]; then
    echo "Found existing 'myapp' directory. Moving into it..."
    cd myapp
  else
    echo "Creating a new default Flutter project 'myapp'..."
    # Ensure flutter is installed on the host to run create
    if ! command -v flutter >/dev/null 2>&1 && [ ! -d "/data/data/com.termux/files/usr/opt/flutter" ]; then
      echo "Flutter is not installed on Termux host. Installing via TermuxVoid..."
      if ! command -v curl >/dev/null 2>&1; then pkg install -y curl; fi
      if [ ! -f "/data/data/com.termux/files/usr/etc/apt/sources.list.d/termuxvoid.list" ]; then
        curl -sL https://github.com/termuxvoid/repo/raw/main/install.sh | bash
      fi
      pkg update -y
      pkg install -y flutter android-sdk openjdk-17
    fi
    FLUTTER_BIN_DIR="/data/data/com.termux/files/usr/opt/flutter/bin"
    if [ -d "$FLUTTER_BIN_DIR" ]; then export PATH="$FLUTTER_BIN_DIR:$PATH"; fi
    flutter create myapp
    cd myapp
  fi
fi

# 4. Get the absolute path of the project directory on the host
PROJECT_DIR=$(pwd)
echo "Project path: $PROJECT_DIR"

# 5. Create the build runner script that will run inside the Ubuntu guest container
BUILD_RUNNER_TMP="/data/data/com.termux/files/home/.flutter_proot_build_runner.sh"

cat << 'EOF2' > "$BUILD_RUNNER_TMP"
#!/bin/bash
set -e

echo "=== Inside Ubuntu Container: Setting up build environment ==="

# Install essential dependencies
if ! command -v git >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1 || ! command -v wget >/dev/null 2>&1 || ! command -v file >/dev/null 2>&1 || ! command -v aapt2 >/dev/null 2>&1; then
  echo "Installing required container tools (git, unzip, wget, file, xz-utils, openjdk, aapt2)..."
  apt-get update
  apt-get install -y git unzip wget file xz-utils openjdk-17-jdk-headless aapt2
fi
EOF2
cat << 'EOF2' >> "$BUILD_RUNNER_TMP"

# Set up JDK
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-arm64"
if [ ! -d "\$JAVA_HOME" ]; then
  JVM_DIR=\$(find /usr/lib/jvm -maxdepth 1 -name "*openjdk*" 2>/dev/null | head -n 1 || true)
  if [ -n "\$JVM_DIR" ]; then
    export JAVA_HOME="\$JVM_DIR"
  fi
fi
export PATH="\$JAVA_HOME/bin:\$PATH"

# Set up Flutter SDK inside container
export FLUTTER_ROOT="/opt/flutter"
if [ ! -d "\$FLUTTER_ROOT" ]; then
  echo "Cloning Flutter SDK into /opt/flutter..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "\$FLUTTER_ROOT"
fi
export PATH="\$FLUTTER_ROOT/bin:\$PATH"

# Set up Android SDK inside container
export ANDROID_HOME="/opt/android-sdk"
if [ ! -d "\$ANDROID_HOME" ]; then
  echo "Downloading Android Commandline Tools..."
  mkdir -p "\$ANDROID_HOME/cmdline-tools"
  wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/cmdline-tools.zip
  unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-extracted
  mv /tmp/cmdline-tools-extracted/cmdline-tools "\$ANDROID_HOME/cmdline-tools/latest"
  rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools-extracted
  
  echo "Accepting Android SDK licenses..."
  yes | "\$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses
  
  echo "Installing Android SDK packages..."
  "\$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "platform-tools" "build-tools;34.0.0" "platforms;android-34"
fi
export PATH="\$ANDROID_HOME/platform-tools:\$PATH"

# Configure Flutter SDK
flutter config --android-sdk "\$ANDROID_HOME"

# Check status
flutter doctor

# Fix gradlew shebang inside the container if needed
if [ -f "$PROJECT_DIR/android/gradlew" ]; then
  chmod +x "$PROJECT_DIR/android/gradlew"
fi

# Navigate to project and run release build
cd "$PROJECT_DIR"

# Apply temporary native aapt2 override inside container
if [ -d "android" ]; then
  touch android/gradle.properties
  cp android/gradle.properties android/gradle.properties.bak
  grep -v "android.aapt2FromMavenOverride" android/gradle.properties.bak > android/gradle.properties || true
  echo "android.aapt2FromMavenOverride=/usr/bin/aapt2" >> android/gradle.properties
fi

echo "Starting compilation: flutter build apk --release..."
flutter build apk --release --target-platform=android-arm64

# Restore original gradle.properties
if [ -f "android/gradle.properties.bak" ]; then
  mv android/gradle.properties.bak android/gradle.properties
fi

echo "=== Inside Ubuntu Container: Build successfully completed ==="
EOF2

# Ensure the build runner script is cleaned up on exit
trap 'rm -f "$BUILD_RUNNER_TMP"' EXIT INT TERM

# 6. Execute the build runner inside the Ubuntu container
echo "Entering PRoot container to compile..."
proot-distro login ubuntu -- bash "$BUILD_RUNNER_TMP"

echo "=== Build Finished successfully! ==="
echo "Your non-crashing Release APK is located at:"
echo "👉 $PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"

# 7. Self-install globally upon successful build
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0")
GLOBAL_PATH="/data/data/com.termux/files/usr/bin/flutter_release"

echo "Making script globally executable..."
if [ "$SCRIPT_PATH" != "$GLOBAL_PATH" ]; then
  cp "$SCRIPT_PATH" "$GLOBAL_PATH"
  chmod +x "$GLOBAL_PATH"
  echo "Script successfully installed globally at $GLOBAL_PATH!"
  echo "You can now run it from anywhere using the 'flutter_release' command."
fi
EOF
chmod +x "$GLOBAL_BIN/flutter_release"

# ==============================================================================
# 7. Write flutter_aab
# ==============================================================================
echo "Installing flutter_aab / flutter_AAB..."
cat << 'EOF' > "$GLOBAL_BIN/flutter_aab"
#!/data/data/com.termux/files/usr/bin/env bash

# ==============================================================================
# Flutter App Bundle Build Automation for Termux (flutter_aab)
# Configures a full Ubuntu container via proot-distro to compile standard,
# production-ready Android App Bundles (AAB) for the Play Store.
# ==============================================================================

set -e

echo "=== Flutter App Bundle (AAB) Build Automation (using PRoot Ubuntu) ==="

# 1. Ensure proot-distro is installed on the host
if ! command -v proot-distro >/dev/null 2>&1; then
  echo "Installing proot-distro..."
  pkg install -y proot-distro
fi

# 2. Ensure Ubuntu distro is installed inside proot-distro
if [ ! -d "/data/data/com.termux/files/usr/var/lib/proot-distro/installed-distros/ubuntu" ]; then
  echo "Installing Ubuntu container via proot-distro (this may take a few minutes)..."
  proot-distro install ubuntu
fi

# 3. Check if we are inside a Flutter project. If not, create a default 'myapp' project.
if [ ! -f "pubspec.yaml" ] || [ ! -d "android" ]; then
  echo "You are not inside a Flutter project directory."
  if [ -d "myapp" ] && [ -f "myapp/pubspec.yaml" ] && [ -d "myapp/android" ]; then
    echo "Found existing 'myapp' directory. Moving into it..."
    cd myapp
  else
    echo "Creating a new default Flutter project 'myapp'..."
    if ! command -v flutter >/dev/null 2>&1 && [ ! -d "/data/data/com.termux/files/usr/opt/flutter" ]; then
      echo "Flutter is not installed on Termux host. Installing via TermuxVoid..."
      if ! command -v curl >/dev/null 2>&1; then pkg install -y curl; fi
      if [ ! -f "/data/data/com.termux/files/usr/etc/apt/sources.list.d/termuxvoid.list" ]; then
        curl -sL https://github.com/termuxvoid/repo/raw/main/install.sh | bash
      fi
      pkg update -y
      pkg install -y flutter android-sdk openjdk-17
    fi
    FLUTTER_BIN_DIR="/data/data/com.termux/files/usr/opt/flutter/bin"
    if [ -d "$FLUTTER_BIN_DIR" ]; then export PATH="$FLUTTER_BIN_DIR:$PATH"; fi
    flutter create myapp
    cd myapp
  fi
fi

# 4. Get the absolute path of the project directory on the host
PROJECT_DIR=$(pwd)
echo "Project path: $PROJECT_DIR"

# 5. Create the build runner script that will run inside the Ubuntu guest container
BUILD_RUNNER_TMP="/data/data/com.termux/files/home/.flutter_proot_aab_runner.sh"

cat << 'EOF2' > "$BUILD_RUNNER_TMP"
#!/bin/bash
set -e

echo "=== Inside Ubuntu Container: Setting up build environment ==="

# Install essential dependencies
if ! command -v git >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1 || ! command -v wget >/dev/null 2>&1 || ! command -v file >/dev/null 2>&1 || ! command -v aapt2 >/dev/null 2>&1; then
  echo "Installing required container tools (git, unzip, wget, file, xz-utils, openjdk, aapt2)..."
  apt-get update
  apt-get install -y git unzip wget file xz-utils openjdk-17-jdk-headless aapt2
fi
EOF2
cat << 'EOF2' >> "$BUILD_RUNNER_TMP"

# Set up JDK
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-arm64"
if [ ! -d "\$JAVA_HOME" ]; then
  JVM_DIR=\$(find /usr/lib/jvm -maxdepth 1 -name "*openjdk*" 2>/dev/null | head -n 1 || true)
  if [ -n "\$JVM_DIR" ]; then
    export JAVA_HOME="\$JVM_DIR"
  fi
fi
export PATH="\$JAVA_HOME/bin:\$PATH"

# Set up Flutter SDK inside container
export FLUTTER_ROOT="/opt/flutter"
if [ ! -d "\$FLUTTER_ROOT" ]; then
  echo "Cloning Flutter SDK into /opt/flutter..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "\$FLUTTER_ROOT"
fi
export PATH="\$FLUTTER_ROOT/bin:\$PATH"

# Set up Android SDK inside container
export ANDROID_HOME="/opt/android-sdk"
if [ ! -d "\$ANDROID_HOME" ]; then
  echo "Downloading Android Commandline Tools..."
  mkdir -p "\$ANDROID_HOME/cmdline-tools"
  wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/cmdline-tools.zip
  unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-extracted
  mv /tmp/cmdline-tools-extracted/cmdline-tools "\$ANDROID_HOME/cmdline-tools/latest"
  rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools-extracted
  
  echo "Accepting Android SDK licenses..."
  yes | "\$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses
  
  echo "Installing Android SDK packages..."
  "\$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "platform-tools" "build-tools;34.0.0" "platforms;android-34"
fi
export PATH="\$ANDROID_HOME/platform-tools:\$PATH"

# Configure Flutter SDK
flutter config --android-sdk "\$ANDROID_HOME"

# Check status
flutter doctor

# Fix gradlew shebang inside the container if needed
if [ -f "$PROJECT_DIR/android/gradlew" ]; then
  chmod +x "$PROJECT_DIR/android/gradlew"
fi

# Navigate to project and run appbundle build
cd "$PROJECT_DIR"

# Apply temporary native aapt2 override inside container
if [ -d "android" ]; then
  touch android/gradle.properties
  cp android/gradle.properties android/gradle.properties.bak
  grep -v "android.aapt2FromMavenOverride" android/gradle.properties.bak > android/gradle.properties || true
  echo "android.aapt2FromMavenOverride=/usr/bin/aapt2" >> android/gradle.properties
fi

echo "Starting compilation: flutter build appbundle..."
flutter build appbundle

# Restore original gradle.properties
if [ -f "android/gradle.properties.bak" ]; then
  mv android/gradle.properties.bak android/gradle.properties
fi

echo "=== Inside Ubuntu Container: Build successfully completed ==="
EOF2

# Ensure the build runner script is cleaned up on exit
trap 'rm -f "$BUILD_RUNNER_TMP"' EXIT INT TERM

# 6. Execute the build runner inside the Ubuntu container
echo "Entering PRoot container to compile..."
proot-distro login ubuntu -- bash "$BUILD_RUNNER_TMP"

echo "=== Build Finished successfully! ==="
echo "Your App Bundle (AAB) is located at:"
echo "👉 $PROJECT_DIR/build/app/outputs/bundle/release/app-release.aab"

# 7. Self-install globally upon successful build
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0")

echo "Making script globally executable..."
# Install as flutter_aab
cp "$SCRIPT_PATH" "/data/data/com.termux/files/usr/bin/flutter_aab"
chmod +x "/data/data/com.termux/files/usr/bin/flutter_aab"

# Install as flutter_AAB
cp "$SCRIPT_PATH" "/data/data/com.termux/files/usr/bin/flutter_AAB"
chmod +x "/data/data/com.termux/files/usr/bin/flutter_AAB"

echo "Script successfully installed globally!"
echo "You can now run it from anywhere using the 'flutter_aab' or 'flutter_AAB' command."
EOF
chmod +x "$GLOBAL_BIN/flutter_aab"
cp "$GLOBAL_BIN/flutter_aab" "$GLOBAL_BIN/flutter_AAB"
chmod +x "$GLOBAL_BIN/flutter_AAB"

# ==============================================================================
# 8. Write kotlin
# ==============================================================================
echo "Installing kotlin..."
cat << 'EOF' > "$GLOBAL_BIN/kotlin"
#!/data/data/com.termux/files/usr/bin/env bash

# ==============================================================================
# Kotlin/Android Native Build & Project Generator for Termux (kotlin)
# Setup Kotlin Android projects compatible with Android Studio & AndroidIDE,
# automatically configures JDK, Android SDK, and Gradle.
# Supports Debug/Release APKs and Android App Bundles (AAB).
# ==============================================================================

set -e

# Helper: Print usage instructions
print_usage() {
  echo "Usage:"
  echo "  kotlin create <app_name> [package_name]  - Create a new Android Kotlin project"
  echo "  kotlin                                    - Build debug APK (runs assembleDebug)"
  echo "  kotlin debug                              - Build debug APK (runs assembleDebug)"
  echo "  kotlin release                            - Build release APK (runs assembleRelease)"
  echo "  kotlin aab                                - Build Android App Bundle (runs bundleRelease)"
}

# 1. Install Java, Android SDK, Gradle, native aapt2, and QEMU if missing
echo "Checking dependencies..."
DEPS_MISSING=false

if ! command -v gradle >/dev/null 2>&1; then
  echo "Gradle is missing."
  DEPS_MISSING=true
fi
if [ ! -d "/data/data/com.termux/files/usr/lib/jvm" ] && [ -z "$JAVA_HOME" ]; then
  echo "JDK is missing."
  DEPS_MISSING=true
fi
if [ ! -d "/data/data/com.termux/files/usr/opt/android-sdk" ]; then
  echo "Android SDK is missing."
  DEPS_MISSING=true
fi
if ! command -v aapt2 >/dev/null 2>&1; then
  echo "Native aapt2 is missing."
  DEPS_MISSING=true
fi
if ! command -v qemu-x86_64 >/dev/null 2>&1; then
  echo "QEMU user-mode x86_64 is missing."
  DEPS_MISSING=true
fi

if [ "$DEPS_MISSING" = true ]; then
  echo "Installing required dependencies (gradle, openjdk-17, android-sdk, aapt2, qemu-user-x86-64)..."
  if ! command -v curl >/dev/null 2>&1; then
    pkg install -y curl
  fi
  if [ ! -f "/data/data/com.termux/files/usr/etc/apt/sources.list.d/termuxvoid.list" ]; then
    echo "Adding TermuxVoid repository..."
    curl -sL https://github.com/termuxvoid/repo/raw/main/install.sh | bash
  fi
  pkg update -y
  pkg install -y gradle openjdk-17 android-sdk aapt2 qemu-user-x86-64
  echo "Dependencies installed successfully!"
fi

# 2. Detect and set JAVA_HOME
echo "Detecting JDK installation..."
JAVA_FOUND=false
if [ -d "/data/data/com.termux/files/usr/lib/jvm/java-17-openjdk" ]; then
  export JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/java-17-openjdk"
  JAVA_FOUND=true
elif [ -d "/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk" ]; then
  export JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk"
  JAVA_FOUND=true
else
  JVM_DIR=$(find /data/data/com.termux/files/usr/lib/jvm -maxdepth 1 -name "*openjdk*" 2>/dev/null | head -n 1 || true)
  if [ -n "$JVM_DIR" ]; then
    export JAVA_HOME="$JVM_DIR"
    JAVA_FOUND=true
  fi
fi
if [ "$JAVA_FOUND" = true ]; then
  echo "Using JAVA_HOME: $JAVA_HOME"
fi

# 3. Configure Android SDK layout for Termux
USER_SDK="$HOME/.android-sdk-flutter"
SYSTEM_SDK="/data/data/com.termux/files/usr/opt/android-sdk"

if [ -d "$SYSTEM_SDK" ]; then
  if [ ! -d "$USER_SDK/cmdline-tools/latest" ]; then
    echo "Configuring custom Android SDK layout..."
    mkdir -p "$USER_SDK/cmdline-tools/latest"
    for d in build-tools cmake licenses ndk platform-tools platforms; do
      if [ -d "$SYSTEM_SDK/$d" ]; then
        ln -sf "$SYSTEM_SDK/$d" "$USER_SDK/$d"
      fi
    done
    if [ -d "$SYSTEM_SDK/cmdline-tools/bin" ]; then
      cp -r "$SYSTEM_SDK/cmdline-tools/bin" "$USER_SDK/cmdline-tools/latest/bin"
      if command -v termux-fix-shebang >/dev/null 2>&1; then
        termux-fix-shebang "$USER_SDK/cmdline-tools/latest/bin/"*
      fi
    fi
    if [ -d "$SYSTEM_SDK/cmdline-tools/lib" ]; then
      ln -sf "$SYSTEM_SDK/cmdline-tools/lib" "$USER_SDK/cmdline-tools/latest/lib"
    fi
    if [ -f "$SYSTEM_SDK/cmdline-tools/source.properties" ]; then
      ln -sf "$SYSTEM_SDK/cmdline-tools/source.properties" "$USER_SDK/cmdline-tools/latest/source.properties"
    fi
  fi
  export ANDROID_HOME="$USER_SDK"
  export ANDROID_SDK_ROOT="$USER_SDK"
else
  echo "Error: Android SDK not found."
  exit 1
fi

# 4. Handle project creation vs project compilation
CREATE_MODE=false
if [ "$1" = "create" ]; then
  if [ -z "$2" ]; then
    echo "Error: Please specify the app name."
    print_usage
    exit 1
  fi
  
  APP_NAME="$2"
  PKG_NAME="${3:-com.example.$APP_NAME}"
  PKG_PATH=$(echo "$PKG_NAME" | tr '.' '/')
  
  echo "Creating new Kotlin Android project '$APP_NAME' with package '$PKG_NAME'..."
  
  # Create directory structure
  mkdir -p "$APP_NAME/app/src/main/res/layout"
  mkdir -p "$APP_NAME/app/src/main/res/values"
  mkdir -p "$APP_NAME/app/src/main/res/mipmap-hdpi"
  mkdir -p "$APP_NAME/app/src/main/java/$PKG_PATH"
  
  # Generate settings.gradle.kts
  cat << EOF2 > "$APP_NAME/settings.gradle.kts"
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "$APP_NAME"
include(":app")
EOF2

# Generate root build.gradle.kts
cat << EOF2 > "$APP_NAME/build.gradle.kts"
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.2.2")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.22")
    }
}
EOF2

  # Generate gradle.properties
  cat << EOF2 > "$APP_NAME/gradle.properties"
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.enableJetifier=true
kotlin.code.style=official
EOF2

  # Generate app/build.gradle
  cat << EOF2 > "$APP_NAME/app/build.gradle"
plugins {
    id 'com.android.application'
    id 'kotlin-android'
}

android {
    namespace '$PKG_NAME'
    compileSdk 34

    defaultConfig {
        applicationId '$PKG_NAME'
        minSdk 21
        targetSdk 34
        versionCode 1
        versionName '1.0'
        testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = '17'
    }
}

dependencies {
    implementation 'androidx.core:core-ktx:1.12.0'
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.11.0'
    implementation 'androidx.constraintlayout:constraintlayout:2.1.4'
}
EOF2

  # Generate AndroidManifest.xml
  cat << EOF2 > "$APP_NAME/app/src/main/AndroidManifest.xml"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="true"
        android:icon="@android:drawable/sym_def_app_icon"
        android:label="@string/app_name"
        android:supportsRtl="true"
        android:theme="@style/Theme.App">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF2

  # Generate colors.xml
  cat << EOF2 > "$APP_NAME/app/src/main/res/values/colors.xml"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="purple_200">#FFBB86FC</color>
    <color name="purple_500">#FF6200EE</color>
    <color name="purple_700">#FF3700B3</color>
    <color name="teal_200">#FF03DAC5</color>
    <color name="teal_700">#FF018786</color>
    <color name="black">#FF000000</color>
    <color name="white">#FFFFFFFF</color>
</resources>
EOF2

  # Generate strings.xml
  cat << EOF2 > "$APP_NAME/app/src/main/res/values/strings.xml"
<resources>
    <string name="app_name">$APP_NAME</string>
</resources>
EOF2

  # Generate themes.xml
  cat << EOF2 > "$APP_NAME/app/src/main/res/values/themes.xml"
<resources>
    <style name="Theme.App" parent="Theme.MaterialComponents.DayNight.DarkActionBar">
        <item name="colorPrimary">@color/purple_500</item>
        <item name="colorPrimaryVariant">@color/purple_700</item>
        <item name="colorOnPrimary">@android:color/white</item>
        <item name="colorSecondary">@color/teal_200</item>
        <item name="colorSecondaryVariant">@color/teal_700</item>
        <item name="colorOnSecondary">@android:color/black</item>
    </style>
</resources>
EOF2

  # Generate activity_main.xml layout
  cat << EOF2 > "$APP_NAME/app/src/main/res/layout/activity_main.xml"
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout 
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://tools.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Hello Kotlin Native in Termux!"
        android:textSize="22sp"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF2

  # Generate MainActivity.kt
  cat << EOF2 > "$APP_NAME/app/src/main/java/$PKG_PATH/MainActivity.kt"
package $PKG_NAME

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF2

  # Initialize gradle wrapper inside the new project
  echo "Bootstrapping Gradle wrapper..."
  cd "$APP_NAME"
  gradle wrapper
  
  if [ -f "gradlew" ]; then
    if grep -q "/usr/bin/env" "gradlew" 2>/dev/null; then
      if command -v termux-fix-shebang >/dev/null 2>&1; then
        termux-fix-shebang gradlew
      fi
    fi
    chmod +x gradlew
  fi
  
  echo "Project successfully created!"
  CREATE_MODE=true
else
  # Compile existing project
  echo "Checking if we are inside a Gradle Android project..."
  if [ ! -f "settings.gradle" ] && [ ! -f "settings.gradle.kts" ]; then
    echo "Error: You are not inside an Android Gradle project."
    print_usage
    exit 1
  fi
  
  # Ensure gradlew has correct shebang and is executable
  if [ -f "gradlew" ]; then
    if grep -q "/usr/bin/env" "gradlew" 2>/dev/null; then
      if command -v termux-fix-shebang >/dev/null 2>&1; then
        termux-fix-shebang gradlew
      fi
    fi
    chmod +x gradlew
  fi
fi

# Determine building task
BUILD_TASK="assembleDebug"
OUTPUT_DESC="Debug APK"
OUTPUT_PATH="app/build/outputs/apk/debug/app-debug.apk"

if [ "$CREATE_MODE" = false ]; then
  if [ "$1" = "release" ]; then
    BUILD_TASK="assembleRelease"
    OUTPUT_DESC="Release APK"
    OUTPUT_PATH="app/build/outputs/apk/release"
  elif [ "$1" = "aab" ] || [ "$1" = "bundle" ]; then
    BUILD_TASK="bundleRelease"
    OUTPUT_DESC="Android App Bundle (AAB)"
    OUTPUT_PATH="app/build/outputs/bundle/release"
  elif [ "$1" = "debug" ]; then
    BUILD_TASK="assembleDebug"
    OUTPUT_DESC="Debug APK"
    OUTPUT_PATH="app/build/outputs/apk/debug"
  fi
fi

# Run build
# Automatically configure local.properties for standard/direct ./gradlew builds
if [ -n "$ANDROID_HOME" ]; then
  if [ ! -f "local.properties" ]; then
    echo "Creating local.properties with SDK location..."
    echo "sdk.dir=$ANDROID_HOME" > local.properties
    echo "android.aapt2FromMavenOverride=/data/data/com.termux/files/usr/bin/aapt2" >> local.properties
  else
    if ! grep -q "sdk.dir" local.properties 2>/dev/null; then
      echo "sdk.dir=$ANDROID_HOME" >> local.properties
    fi
    if ! grep -q "android.aapt2FromMavenOverride" local.properties 2>/dev/null; then
      echo "android.aapt2FromMavenOverride=/data/data/com.termux/files/usr/bin/aapt2" >> local.properties
    fi
  fi
fi

# Automatically handle Gradle 9+ incompatibility
if [ -f "gradle/wrapper/gradle-wrapper.properties" ]; then
  GRADLE_VERSION=$(grep "distributionUrl" gradle/wrapper/gradle-wrapper.properties | sed -n 's/.*gradle-\([0-9.]*\)-.*/\1/p' || true)
  if [ -n "$GRADLE_VERSION" ]; then
    MAJOR_VERSION=$(echo "$GRADLE_VERSION" | cut -d. -f1)
    if [ "$MAJOR_VERSION" -ge 9 ]; then
      echo "Incompatible Gradle version $GRADLE_VERSION detected (Gradle 9+ is incompatible with Android Gradle Plugin 8.x)."
      echo "Automatically adjusting Gradle wrapper to v8.4..."
      sed -i 's/gradle-9\.[0-9.]*/gradle-8.4/g' gradle/wrapper/gradle-wrapper.properties
    fi
  fi
fi

# Ensure we have a compatible gradle wrapper to avoid Gradle 9+ incompatibility
if [ ! -f "gradlew" ] && [ -n "$(command -v gradle)" ]; then
  echo "No Gradle wrapper found. Bootstrapping Gradle wrapper v8.5..."
  gradle wrapper --gradle-version 8.5
  if [ -f "gradlew" ]; then
    if grep -q "/usr/bin/env" "gradlew" 2>/dev/null; then
      if command -v termux-fix-shebang >/dev/null 2>&1; then
        termux-fix-shebang gradlew
      fi
    fi
    chmod +x gradlew
  fi
fi

echo "Running compilation..."
if [ -f "gradlew" ]; then
  ./gradlew $BUILD_TASK -Pandroid.aapt2FromMavenOverride=/data/data/com.termux/files/usr/bin/aapt2
else
  gradle $BUILD_TASK -Pandroid.aapt2FromMavenOverride=/data/data/com.termux/files/usr/bin/aapt2
fi

echo "=== Build Finished successfully! ==="
echo "Your $OUTPUT_DESC is located at:"
echo "👉 $OUTPUT_PATH"

# 5. Self-install globally upon successful build
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0")
GLOBAL_PATH="/data/data/com.termux/files/usr/bin/kotlin"

echo "Making script globally executable..."
if [ "$SCRIPT_PATH" != "$GLOBAL_PATH" ]; then
  cp "$SCRIPT_PATH" "$GLOBAL_PATH"
  chmod +x "$GLOBAL_PATH"
  echo "Script successfully installed globally at $GLOBAL_PATH!"
  echo "You can now run it from anywhere using the 'kotlin' command."
fi
EOF
chmod +x "$GLOBAL_BIN/kotlin"

# ==============================================================================
# 9. Clean up and finalize
# ==============================================================================
echo "=== Installation Successful! ==="
echo "You can now run any of these commands from anywhere:"
echo "  - expo_debug"
echo "  - expo_release"
echo "  - expo_aab / expo_AAB"
echo "  - flutter_debug"
echo "  - flutter_release"
echo "  - flutter_aab / flutter_AAB"
echo "  - kotlin"
