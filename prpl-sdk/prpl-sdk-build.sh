#!/bin/bash

prpl_sdk_build() {
  local script_dir="$(dirname "$(readlink -f "${BASH_SOURCE}")")";
  local yocto_dir="${1:-"/src/yocto"}";
  local machine="${2:-"container-x86-64"}"; # Supported values:
                                            # `container-cortexa53` and
                                            # `container-x86-64`
  local sstate_ip="${3:-"172.17.0.1"}";
  local lcm_dir="${4:-"${yocto_dir}/meta-lcm"}";
  local build_dir="${yocto_dir}/build";
  local lcm_user="lcmuser";
  local lcm_sdk_dir="/src/sdkworkdir";
  userdel -rf "${lcm_user}";
  rm -rf "${build_dir}" && \
  useradd -ms /bin/bash "${lcm_user}" && \
  mkdir -p "${build_dir}" && \
  chown -R "${lcm_user}":"${lcm_user}" "${build_dir}" && \
  runuser -l "${lcm_user}" -c "\
    source "${yocto_dir}/poky/oe-init-build-env" "${build_dir}" && \
    cp \
      "${script_dir}/yocto/build/conf/local.conf" \
      "${script_dir}/yocto/build/conf/rust.inc" \
      "${build_dir}/conf/." && \
    sed -i \
      -e "s/LCM_TARGET_MACHINE/${machine}/g" \
      -e "s/SERVER_SSTATE_IP/${sstate_ip}/g" \
      "${build_dir}/conf/local.conf" && \
    source "${yocto_dir}/poky/oe-init-build-env" "${build_dir}" && \
    bitbake-layers add-layer "${lcm_dir}/meta-openembedded/meta-oe" && \
    bitbake-layers add-layer "${lcm_dir}/meta-openembedded/meta-python" && \
    bitbake-layers add-layer "${lcm_dir}/meta-openembedded/meta-networking" && \
    bitbake-layers add-layer "${lcm_dir}/meta-openembedded/meta-filesystems" && \
    bitbake-layers add-layer "${lcm_dir}/meta-openembedded/meta-webserver" && \
    bitbake-layers add-layer "${lcm_dir}/meta-virtualization" && \
    bitbake-layers add-layer "${lcm_dir}/meta-amx" && \
    bitbake-layers add-layer "${lcm_dir}/meta-usp" && \
    bitbake-layers add-layer "${lcm_dir}/meta-containers" && \
    bitbake-layers add-layer "${lcm_dir}/meta-rust-bin" && \
    source "${yocto_dir}/poky/oe-init-build-env" "${build_dir}" && \
    bitbake image-lcm-container-minimal && \
    rsync -ruq --no-links --progress \
      -e \"sshpass -p 'mycacheserverpassword' ssh -p 5555 -o StrictHostKeyChecking=no\" \
      "${build_dir}/sstate-cache/*" \
      "root@${sstate_ip}:/srv/sstate-cache" && \
    bitbake image-lcm-container-minimal -c populate_sdk_ext && \
    cp \
      "${build_dir}/tmp-glibc/deploy/sdk/meta-containers*.sh" \
      "/tmp/esdk_installer.sh"" && \
  mkdir -p "${lcm_sdk_dir}" && \
  chown -R "${lcm_user}":"${lcm_user}" "${lcm_sdk_dir}" && \
  runuser -l "${lcm_user}" -c "\
    /tmp/esdk_installer.sh -y -n -d "${lcm_sdk_dir}" && \
    rm -rf "${lcm_sdk_dir}/cache/*" "${lcm_sdk_dir}/sstate-cache/*" && \
    echo \
      "source \"${lcm_sdk_dir}/layers/poky/oe-init-build-env\" \"${lcm_sdk_dir}\"" > \
      "/home/${lcm_user}/.bash_aliases"";
  return ${?};
}

prpl_sdk_build "${@}";
