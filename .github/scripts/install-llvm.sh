#!/usr/bin/env bash
# Install a specific LLVM major version and export LLVM_DIR for CMake.
# - Linux x86_64/arm64 & macOS arm64: GitHub prebuilt binaries (exact version)
# - macOS x86_64 (Intel): Homebrew (no Intel prebuilt exists for LLVM 20+)
# Usage: install-llvm.sh <major>
set -euo pipefail

MAJOR="${1:?usage: install-llvm.sh <llvm-major-version>}"

OS="$(uname -s)"
ARCH="$(uname -m)"

# ---------------------------------------------------------------------------
# macOS x86_64 (Intel) has no upstream prebuilt for LLVM 20+, use Homebrew.
# ---------------------------------------------------------------------------
if [ "$OS" = "Darwin" ] && [ "$ARCH" != "arm64" ]; then
  echo "::group::Install LLVM ${MAJOR} via Homebrew (macOS x86_64)"
  if brew install "llvm@${MAJOR}"; then
    PREFIX="$(brew --prefix "llvm@${MAJOR}")"
  else
    echo "::warning::llvm@${MAJOR} not available via Homebrew; using latest 'llvm'"
    brew install llvm
    PREFIX="$(brew --prefix llvm)"
  fi
  LLVM_DIR="$PREFIX/lib/cmake/llvm"
  LLVM_BIN="$PREFIX/bin"
  echo "::endgroup::"
  echo "LLVM_DIR=${LLVM_DIR}" >> "$GITHUB_ENV"
  echo "LLVM_BIN=${LLVM_BIN}" >> "$GITHUB_ENV"
  echo "${LLVM_BIN}" >> "$GITHUB_PATH"
  echo "DYLD_LIBRARY_PATH=$PREFIX/lib:${DYLD_LIBRARY_PATH:-}" >> "$GITHUB_ENV"
  echo "::notice::Using LLVM_DIR=${LLVM_DIR}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Platform suffix for the prebuilt asset name.
# ---------------------------------------------------------------------------
if [ "$OS" = "Linux" ]; then
  if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    SUF="Linux-ARM64"
  else
    SUF="Linux-X64"
  fi
else
  SUF="macOS-ARM64"
fi

# ---------------------------------------------------------------------------
# Resolve the highest patch release of this major that ships the prebuilt.
# ---------------------------------------------------------------------------
echo "Resolving LLVM ${MAJOR} prebuilt for ${SUF}"
ALLTAGS="$(gh api repos/llvm/llvm-project/releases --paginate --jq '.[] | .tag_name' \
          | grep -E "^llvmorg-${MAJOR}\." | sort -Vr)"
TAG=""
ASSET=""
PAT='^LLVM-'"${MAJOR}"'\..*-'"${SUF}"'\.tar\.xz$'
for t in $ALLTAGS; do
  names="$(gh api "repos/llvm/llvm-project/releases/tags/$t" --jq '.assets[].name' 2>/dev/null || true)"
  A="$(echo "$names" | grep -E "$PAT" | head -1)"
  if [ -n "$A" ]; then
    ASSET="$A"
    TAG="$t"
    break
  fi
done
[ -n "$TAG" ] || { echo "::error::No LLVM ${MAJOR} release provides ${SUF} prebuilt"; exit 1; }
echo "Using ${TAG} (asset ${ASSET})"

URL="$(gh api "repos/llvm/llvm-project/releases/tags/${TAG}" --jq ".assets[] | select(.name==\"${ASSET}\") | .browser_download_url")"
[ -n "$URL" ] || { echo "::error::Asset ${ASSET} download url not found"; exit 1; }

echo "::group::Download & extract LLVM ${MAJOR}"
curl -fSL --retry 3 --retry-delay 5 "$URL" -o /tmp/llvm.tar.xz
DEST="$HOME/llvm-${MAJOR}"
rm -rf "$DEST"
mkdir -p "$DEST"
tar -xJf /tmp/llvm.tar.xz -C "$DEST" --strip-components=1
echo "::endgroup::"

# Locate the actual LLVM cmake config (robust against layout changes).
LLVM_CONFIG="$(find "$DEST" -name LLVMConfig.cmake 2>/dev/null | head -1)"
[ -n "$LLVM_CONFIG" ] || { echo "::error::LLVMConfig.cmake not found in ${DEST}"; exit 1; }
LLVM_DIR="$(dirname "$LLVM_CONFIG")"
_LC="$(find "$DEST" -name llvm-config -type f 2>/dev/null | head -1)"
LLVM_BIN="$(dirname "$_LC")"
[ -z "$LLVM_BIN" ] && LLVM_BIN="$DEST/bin"

# The Linux prebuilt links against libtinfo.so.5; provide a compat symlink.
if [ "$OS" = "Linux" ]; then
  for d in /usr/lib/x86_64-linux-gnu /usr/lib/aarch64-linux-gnu; do
    if [ -e "$d/libtinfo.so.6" ] && [ ! -e "$d/libtinfo.so.5" ]; then
      sudo ln -sf "$d/libtinfo.so.6" "$d/libtinfo.so.5"
    fi
  done
fi

echo "LLVM_DIR=${LLVM_DIR}" >> "$GITHUB_ENV"
echo "LLVM_BIN=${LLVM_BIN}" >> "$GITHUB_ENV"
echo "${LLVM_BIN}" >> "$GITHUB_PATH"
if [ "$OS" = "Linux" ]; then
  echo "LD_LIBRARY_PATH=$DEST/lib:${LD_LIBRARY_PATH:-}" >> "$GITHUB_ENV"
else
  echo "DYLD_LIBRARY_PATH=$DEST/lib:${DYLD_LIBRARY_PATH:-}" >> "$GITHUB_ENV"
fi
echo "::notice::Using LLVM_DIR=${LLVM_DIR}"
