#!/data/data/com.termux/files/usr/bin/env bash

# ==============================================================================
# Installer script for Termux Build Tools Repository
# Sets executable permissions and installs scripts to system usr/bin path.
# ==============================================================================

set -e

echo "=== Installing Termux Build Tools ==="

# Get directory where install.sh resides
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# 1. Grant executable permission to local scripts
echo "Setting local executable permissions..."
chmod +x expo_aab expo_debug expo_release flutter_aab flutter_debug flutter_release kotlin

# 2. Copy scripts to Termux system binary path
GLOBAL_BIN="/data/data/com.termux/files/usr/bin"
echo "Installing to global bin path: $GLOBAL_BIN..."

cp expo_debug "$GLOBAL_BIN/expo_debug"
cp expo_release "$GLOBAL_BIN/expo_release"

cp expo_aab "$GLOBAL_BIN/expo_aab"
cp expo_aab "$GLOBAL_BIN/expo_AAB"

cp flutter_debug "$GLOBAL_BIN/flutter_debug"
cp flutter_release "$GLOBAL_BIN/flutter_release"

cp flutter_aab "$GLOBAL_BIN/flutter_aab"
cp flutter_aab "$GLOBAL_BIN/flutter_AAB"

cp kotlin "$GLOBAL_BIN/kotlin"

# 3. Grant executable permission to global binaries
echo "Setting global executable permissions..."
cd "$GLOBAL_BIN"
chmod +x expo_debug expo_release expo_aab expo_AAB flutter_debug flutter_release flutter_aab flutter_AAB kotlin

echo "=== Installation Successful! ==="
echo "You can now run any of these commands from anywhere:"
echo "  - expo_debug"
echo "  - expo_release"
echo "  - expo_aab / expo_AAB"
echo "  - flutter_debug"
echo "  - flutter_release"
echo "  - flutter_aab / flutter_AAB"
echo "  - kotlin"
