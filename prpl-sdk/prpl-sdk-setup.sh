#!/bin/bash
set -euo pipefail;

prpl_sdk_apt() {
  local yocto_pkg="gawk wget git diffstat unzip texinfo gcc build-essential chrpath socat cpio python3 python3-pip python3-pexpect xz-utils debianutils iputils-ping python3-git python3-jinja2 python3-subunit zstd liblz4-tool file locales libacl1";
  local lcm_pkg="python3 chrpath cpio cpp diffstat g++ gawk gcc git locales make patch texinfo git-lfs tree zlib1g zstd liblz4-tool python3-distutils python3-pip screen quilt wget vim git-all fakeroot rsync skopeo sshpass sudo";
  export DEBIAN_FRONTEND="noninteractive";
  apt update;
  apt -y dist-upgrade;
  apt -y install ${lcm_pkg};
  echo "en_US.UTF-8 UTF-8" > "/etc/locale.gen";
  locale-gen;
  update-locale "LANG=en_US.UTF-8";
  return ${?};
}

prpl_sdk_setup() {
  local script_dir="$(dirname "$(readlink -f "${BASH_SOURCE}")")";
  local yocto_dir="${1:-"/src/yocto"}";
  local yocto_version="${2:-"honister"}"; #scarthgap
  local containers_version="${3:-"${yocto_version}_v1.2.2"}";
  local usp_version="${4:-"${yocto_version}_v3.11.0"}";
  local amx_version="${5:-"${yocto_version}_v11.23.3"}";
  local machine="${6:-"container-x86-64"}"; # Supported values:
                                            # `container-cortexa53` and
                                            # `container-x86-64`
  local sstate_ip="${7:-"172.17.0.1"}";
  local lcm_dir="${8:-"${yocto_dir}/meta-lcm"}";

  prpl_sdk_apt;

  mkdir -p "${yocto_dir}";
  echo "Checking poky...";
  if [ ! -d "${yocto_dir}/poky" ];
  then
    cd "${yocto_dir}";
    git clone --recursive --depth=1 -b "${yocto_version}" \
      git://git.yoctoproject.org/poky;
  else
    cd "${yocto_dir}/poky";
    git pull;
  fi

  mkdir -p "${lcm_dir}";
  echo "Checking meta-openembedded...";
  if [ ! -d "${lcm_dir}/meta-openembedded" ];
  then
    cd "${lcm_dir}";
    git clone --recursive --depth=1 -b ${yocto_version} \
      https://github.com/openembedded/meta-openembedded.git;
  else
    cd "${lcm_dir}/meta-openembedded";
    git pull;
  fi
  echo "Checking meta-virtualization...";
  if [ ! -d "${lcm_dir}/meta-virtualization" ];
  then
    cd "${lcm_dir}";
    git clone --recursive --depth=1 -b ${yocto_version} \
      https://github.com/lgirdk/meta-virtualization.git;
  else
    cd "${lcm_dir}/meta-virtualization";
    git pull;
  fi
  echo "Checking meta-containers...";
  if [ ! -d "${lcm_dir}/meta-containers" ];
  then
    cd "${lcm_dir}";
    git clone --recursive --depth=1 -b ${containers_version} \
      https://gitlab.com/soft.at.home/buildsystems/yocto/meta-containers.git;
  else
    cd "${lcm_dir}/meta-containers";
    git pull;
  fi
  echo "Checking meta-usp...";
  if [ ! -d "${lcm_dir}/meta-usp" ];
  then
    cd "${lcm_dir}";
    git clone --recursive --depth=1 -b ${usp_version} \
      https://gitlab.com/soft.at.home/buildsystems/yocto/meta-usp.git;
  else
    cd "${lcm_dir}/meta-usp";
    git pull;
  fi
  echo "Checking meta-amx...";
  if [ ! -d "${lcm_dir}/meta-amx" ];
  then
    cd "${lcm_dir}";
    git clone --recursive --depth=1 -b ${amx_version} \
      https://gitlab.com/soft.at.home/buildsystems/yocto/meta-amx.git;
  else
    cd "${lcm_dir}/meta-amx";
    git pull;
  fi
  echo "Checking meta-rust-bin...";
  if [ ! -d "${lcm_dir}/meta-rust-bin" ];
  then
    cd "${lcm_dir}";
    git clone --recursive --depth=1 \
      https://github.com/rust-embedded/meta-rust-bin.git;
  else
    cd "${lcm_dir}/meta-rust-bin";
    git pull;
  fi

  "${script_dir}/prpl-sdk-build.sh" \
    "${yocto_dir}" \
    "${machine}" \
    "${sstate_ip}" \
    "${lcm_dir}";

  return ${?};
}

prpl_sdk_setup "${@}";
