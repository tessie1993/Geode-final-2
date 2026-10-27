#!/bin/bash
# SessionStart hook for Claude Code cloud sessions: installs the Android SDK,
# NDK and CMake, the pre-commit hook environments and warms the Gradle
# wrapper, so builds, ktlint/detekt, unit tests and staged checks work.
# Idempotent; every step is a near no-op once the container is cached.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT"
SDK_DIR="${ANDROID_SDK_DIR:-/home/user/android-sdk}"
say() { printf '[session-start] %s\n' "$*" >&2; }

# ---- Android SDK, NDK, CMake (+ local.properties) -------------------------
bash tools/setup-android-sdk.sh "$SDK_DIR" >&2

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export ANDROID_HOME=\"$SDK_DIR\""
    echo "export ANDROID_SDK_ROOT=\"$SDK_DIR\""
    echo "export PATH=\"$SDK_DIR/platform-tools:$SDK_DIR/cmdline-tools/latest/bin:\$PATH\""
  } >> "$CLAUDE_ENV_FILE"
fi

# ---- Native submodules ------------------------------------------------------
# third_party/* are declared in .gitmodules; only pinned gitlinks can be
# checked out. Unpinned ones are reported, not guessed at.
if git ls-files -s | grep -q '^160000'; then
  git submodule update --init --recursive --depth 1 >&2 || say "submodule update failed"
else
  say "WARNING: .gitmodules declares third_party/* but no submodule revisions are committed;"
  say "         the native core (libgeode.so) cannot be built until they are pinned."
fi

# ---- pre-commit (docs/GIT_HOOKS.md) ----------------------------------------
if [ ! -x .venv-hooks/bin/python ]; then
  python3 -m venv .venv-hooks
fi
.venv-hooks/bin/python -m pip install -q -r tools/hooks/requirements.txt >&2
.venv-hooks/bin/python -m pre_commit install --install-hooks --allow-missing-config >&2

# ---- Gradle wrapper ---------------------------------------------------------
chmod +x gradlew
./gradlew --version -q >/dev/null 2>&1 || ./gradlew --version >&2

# ---- glslcheck needs Playwright, which the cloud image ships globally --------
say "ready: ./gradlew ktlintCheck | :app:detekt | :app:testDebugUnitTest; node tools/glslcheck/check.mjs --all"
