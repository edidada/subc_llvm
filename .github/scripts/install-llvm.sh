#!/usr/bin/env bash
# Install a specific LLVM major version from GitHub prebuilt binaries and
# export LLVM_DIR for CMake. Usage: install-llvm.sh <major>
set -euo pipefail

MAJOR="${1:?usage: install-llvm.sh <llvm-major-version>}"

OS="$(uname -s)"
ARCH="$(uname -m)"

echo "::group::Resolve LLVM ${MAJOR} latest patch release"
TAG="$(gh api repos/llvm/llvm-project/releases --paginate --jq '.[] | .tag_name' \
      | grep -E "^llvmorg-${MAJOR}\." | sort -V | tail -1)"
[ -n "$TAG" ] || { echo "::error::No LLVM ${MAJOR} release found"; exit 1; }
VER="${TAG#llvmorg-}"
echo "Using ${TAG} (version ${VER})"
echo "::endgroup::"

if [ "$OS" = "Linux" ]; then
  if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    ASSET="clang+llvm-${VER}-aarch64-linux-gnu.tar.xz"
  else
    ASSET="$(gh api "repos/llvm/llvm-project/releases/tags/${TAG}" --jq '.assets[].name' \
           | grep -E "clang\+llvm-${VER}-x86_64-linux-gnu-ubuntu" | sort -V | tail -1)"
  fi
else
  if [ "$ARCH" = "arm64" ]; then A="arm64"; else A="x86_64"; fi
  ASSET="clang+llvm-${VER}-${A}-apple-darwin.tar.xz"
fi

[ -n "$ASSET" ] || { echo "::error::Could not determine asset for LLVM ${MAJOR} on ${OS}/${ARCH}"; exit 1; }
echo "Selected asset: ${ASSET}"

URL="$(gh api "repos/llvm/llvm-project/releases/tags/${TAG}" --jq ".assets[] | select(.name==\"${ASSET}\") | .browser_download_url")"
[ -n "$URL" ] || { echo "::error::Asset ${ASSET} download url not found"; exit 1; }

echo "::group::Download & extract LLVM ${MAJOR}"
curl -fSL --retry 3 --retry-delay 5 "$URL" -o /tmp/llvm.tar.xz
DEST="$HOME/llvm-${MAJOR}"
rm -rf "$DEST"
mkdir -p "$DEST"
tar -xJf /tmp/llvm.tar.xz -C "$DEST" --strip-components=1
echo "::endgroup::"

# The Linux prebuilt links against libtinfo.so.5; provide a compat symlink to
# the system libtinfo.so.6 when the .5 variant is missing.
if [ "$OS" = "Linux" ]; then
  for d in /usr/lib/x86_64-linux-gnu /usr/lib/aarch64-linux-gnu; do
    if [ -e "$d/libtinfo.so.6" ] && [ ! -e "$d/libtinfo.so.5" ]; then
      sudo ln -sf "$d/libtinfo.so.6" "$d/libtinfo.so.5"
    fi
  done
fi

LLVM_DIR="$DEST/lib/cmake/llvm"
LLVM_BIN="$DEST/bin"
echo "LLVM_DIR=${LLVM_DIR}" >> "$GITHUB_ENV"
echo "LLVM_BIN=${LLVM_BIN}" >> "$GITHUB_ENV"
echo "${LLVM_BIN}" >> "$GITHUB_PATH"
echo "::notice::Using LLVM_DIR=${LLVM_DIR}"
