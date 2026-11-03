#!/usr/bin/env bash
# Install a specific LLVM major version via conda-forge (micromamba) and export
# LLVM_DIR for CMake. Works on Linux (x86_64/arm64) and macOS (x86_64/arm64).
# Usage: install-llvm.sh <major>
set -euo pipefail

MAJOR="${1:?usage: install-llvm.sh <llvm-major-version>}"
OS="$(uname -s)"

PREFIX="$HOME/llvm-${MAJOR}"

# --- bootstrap micromamba (once per runner) ---
if ! command -v micromamba >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/micromamba" ]; then
  echo "::group::Bootstrap micromamba"
  curl -L https://micro.mamba.pm/install.sh -o /tmp/mm.sh
  bash /tmp/mm.sh -b
  echo "::endgroup::"
fi
MM="$HOME/.local/bin/micromamba"
if [ ! -x "$MM" ]; then MM="$(command -v micromamba || true)"; fi
[ -x "$MM" ] || { echo "::error::micromamba not found after bootstrap"; exit 1; }

# --- create/use the LLVM env (skip if a cached env already exists) ---
if [ -f "$PREFIX/lib/cmake/llvm/LLVMConfig.cmake" ]; then
  echo "Using cached LLVM ${MAJOR} at $PREFIX"
else
  echo "::group::Install LLVM ${MAJOR} (conda-forge)"
  "$MM" create -y -p "$PREFIX" -c conda-forge "llvmdev=${MAJOR}"
  echo "::endgroup::"
fi

LLVM_DIR="$PREFIX/lib/cmake/llvm"
LLVM_BIN="$PREFIX/bin"
echo "LLVM_DIR=${LLVM_DIR}" >> "$GITHUB_ENV"
echo "LLVM_BIN=${LLVM_BIN}" >> "$GITHUB_ENV"
echo "${LLVM_BIN}" >> "$GITHUB_PATH"
# Do NOT export LD_LIBRARY_PATH/DYLD_LIBRARY_PATH: on macOS that makes the system
# cmake/git load conda's incompatible libiconv and abort. The built `subc` either
# links LLVM statically (macOS) or carries an RPATH (CMAKE_BUILD_RPATH, Linux) to
# find libLLVM, so no extra library-path env is needed at build or run time.
echo "::notice::Using LLVM_DIR=${LLVM_DIR}"
