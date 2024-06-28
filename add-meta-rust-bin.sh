#!/bin/bash
set -euo pipefail;

add_meta_rust_bin() {
  local script_dir="$(dirname "$(readlink -f "${BASH_SOURCE}")")";
  local prpl_sdk_branch="${1:-"main"}";
  local prpl_sdk_dir="${2:-"${HOME}/src/prpl-sdk/${prpl_sdk_branch}/x86/workspace"}";
  local rust_version="${3:-"1.79.0"}";
  local prpl_sdk_conf_dir="${prpl_sdk_dir}/conf";
  local prpl_sdk_layers_dir="${prpl_sdk_dir}/layers";
  local patches_dir="${script_dir}/prpl-sdk/${prpl_sdk_branch}/conf";
  local i;
  echo "Checking meta-rust-bin...";
  if [ ! -d "${prpl_sdk_layers_dir}/meta-rust-bin" ];
  then
    cd "${prpl_sdk_layers_dir}";
    git clone --recursive --depth=1 \
      https://github.com/rust-embedded/meta-rust-bin.git;
  else
    cd "${prpl_sdk_layers_dir}/meta-rust-bin";
    git pull;
  fi
  for i in "bblayers.conf" "local.conf";
  do
    patch -b "${prpl_sdk_conf_dir}/${i}" "${patches_dir}/${i}.patch";
  done
  echo "\
RUST_VERSION ?= \"${rust_version}\"
RUSTVERSION ?= \"\${RUST_VERSION}\"

PREFERRED_VERSION_cargo ?= \"\${RUST_VERSION}\"
PREFERRED_VERSION_cargo-native ?= \"\${RUST_VERSION}\"
PREFERRED_VERSION_libstd-rs ?= \"\${RUST_VERSION}\"
PREFERRED_VERSION_rust ?= \"\${RUST_VERSION}\"
PREFERRED_VERSION_rust-cross-\${TARGET_ARCH} ?= \"\${RUST_VERSION}\"
PREFERRED_VERSION_rust-llvm ?= \"\${RUST_VERSION}\"
PREFERRED_VERSION_rust-llvm-native ?= \"\${RUST_VERSION}\"
PREFERRED_VERSION_rust-native ?= \"\${RUST_VERSION}\"" > "${prpl_sdk_conf_dir}/rust.inc";
  return $?;
}

add_meta_rust_bin "${@}";
