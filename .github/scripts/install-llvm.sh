#!/usr/bin/env bash
# Install a specific LLVM major version and export LLVM_DIR for CMake.
# Usage: install-llvm.sh <major>
set -euo pipefail

MAJOR="${1:?usage: install-llvm.sh <llvm-major-version>}"

uname_s="$(uname -s)"
uname_m="$(uname -m)"

if [ "$uname_s" = "Linux" ]; then
  echo "::group::Install LLVM ${MAJOR} via apt.llvm.org (Linux)"
  sudo apt-get update -y
  sudo apt-get install -y wget lsb-release gnupg software-properties-common
  wget -O /tmp/llvm.sh https://apt.llvm.org/llvm.sh
  chmod +x /tmp/llvm.sh
  sudo /tmp/llvm.sh "${MAJOR}" all
  LLVM_DIR="/usr/lib/llvm-${MAJOR}/lib/cmake/llvm"
  LLVM_BIN="/usr/lib/llvm-${MAJOR}/bin"
  echo "::endgroup::"
else
  echo "::group::Install LLVM ${MAJOR} via prebuilt binaries (macOS)"
  if [ "$uname_m" = "arm64" ]; then ASSET_ARCH="arm64"; else ASSET_ARCH="x86_64"; fi
  # Resolve the latest patch release for this major.
  TAG="$(gh api repos/llvm/llvm-project/releases --paginate --jq '.[] | .tag_name' \
        | grep -E "^llvmorg-${MAJOR}\." | sort -V | tail -1)"
  echo "Resolved release tag: ${TAG}"
  [ -n "$TAG" ] || { echo "::error::No LLVM ${MAJOR} release found"; exit 1; }
  VER="${TAG#llvmorg-}"
  PATTERN="clang\+llvm-${VER}-${ASSET_ARCH}-apple-darwin\.tar\.xz"
  URL="$(gh api "repos/llvm/llvm-project/releases/tags/${TAG}" --jq '.assets[].browser_download_url' \
        | grep -E "${PATTERN}" | head -1)"
  echo "Downloading ${URL}"
  [ -n "$URL" ] || { echo "::error::No macOS prebuilt asset for LLVM ${MAJOR} (${ASSET_ARCH})"; exit 1; }
  curl -fSL "$URL" -o /tmp/llvm.tar.xz
  DEST="$HOME/llvm-${MAJOR}"
  rm -rf "$DEST"
  mkdir -p "$DEST"
  tar -xJf /tmp/llvm.tar.xz -C "$DEST" --strip-components=1
  LLVM_DIR="$DEST/lib/cmake/llvm"
  LLVM_BIN="$DEST/bin"
  echo "::endgroup::"
fi

echo "LLVM_DIR=${LLVM_DIR}" >> "$GITHUB_ENV"
echo "LLVM_BIN=${LLVM_BIN}" >> "$GITHUB_ENV"
echo "${LLVM_BIN}" >> "$GITHUB_PATH"
echo "::notice::Using LLVM_DIR=${LLVM_DIR}"
