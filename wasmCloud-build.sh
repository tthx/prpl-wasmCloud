#!/bin/bash
set -euo pipefail;

build_wasmCloud() {
  local recipe_dir="${1:-"/sdkworkdir/workspace/recipes"}";
  local wasmCloud_release="${2:-"v0.82.0"}";
  # local docker_ip="${3:-"192.168.0.3"}";
  # local docker_port="${4:-"5000"}";
  # local arch="${5:-"x68_64"}";
  # local user="${6:-"$(id -nu)"}";
  # local passwd="${7:-"${user}"}";
  # local salt="${8:-"20240626090431"}";
  devtool add wasmcloud \
    -B "release/${wasmCloud_release}" \
    "https://github.com/wasmCloud/wasmCloud.git";
  echo "\
inherit cargo_bin
SUMMARY = \"wasmCloud host runtime\"
HOMEPAGE = \"https://github.com/wasmCloud/wasmCloud\"
LICENSE = \"Apache-2.0\"
LIC_FILES_CHKSUM = \"file://LICENSE;md5=398c810c4f475ff8ab49ba8d2ba614c1\"
SRC_URI = \"git://github.com/wasmCloud/wasmCloud.git;protocol=https;branch=release/v0.82.0\"
PV = \"1.0+git\${SRCPV}\"
SRCREV = \"9efb52976b4224aaece5fd430cd7e45ff4aa567c\"
S = \"\${WORKDIR}/git\"
# Enable network for the compile task allowing cargo to download dependencies
do_compile[network] = \"1\"" > "${recipe_dir}/wasmcloud/wasmcloud_git.bb";
  devtool build wasmcloud;
  devtool build-image;
  # skopeo copy \
  #   "oci:/sdkworkdir/tmp/deploy/images/container-${arch}/image-lcm-amx-ubus-usp-lcmsampleapp-container-${arch}-${salt}.rootfs-oci" \
  #   "docker://${docker_ip}:${docker_port}/wasmcloud-${arch}:${wasmCloud_release}" \
  #   --dest-creds="${user}":"${passwd}" \
  #   --dest-tls-verify=false;
  reuturn $?;
}

build_wasmCloud "${@}";
