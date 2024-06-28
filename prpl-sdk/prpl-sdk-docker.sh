#!/bin/bash
set -euo pipefail;

prpl_sdk_docker() {
  local ubuntu_version="${1:-22.04}";
  local container_name="${2:-"prpl SDK"}";
  local with_net="${3:+--publish 25000:25000 --publish 25010:25010 --publish 25020:25020}";
  local with_x11="${4:+--env \"DISPLAY\" --volume \"\${HOME}/.Xauthority:/root/.Xauthority:rw\" --net host}";
  local core_patern="$(cat /proc/sys/kernel/core_pattern)";
  echo '/tmp/core.%e.%p' | \
    sudo tee /proc/sys/kernel/core_pattern 2>/dev/null 1>&2;
  if [ -z "$(docker container ls -a|grep "${container_name}-${ubuntu_version}")" ];
  then
    docker run \
      --cap-add CAP_SYS_PTRACE --shm-size="$(("$(cat /proc/meminfo|grep "^MemTotal"|sed -e "s/\(^MemTotal:[[:space:]]*\)\(.*\)\([[:space:]]*kB\$\)/\2/g")"/2))k" \
      --runtime=nvidia --gpus all \
      --init \
      --ulimit core=-1 \
      --interactive --tty \
      --name "${container_name}-${ubuntu_version}" \
      --volume "${HOME}/src:/src" \
      --env TZ="Europe/Paris" \
      --env DISPLAY="${DISPLAY}" \
      --volume "/tmp/.X11-unix:/tmp/.X11-unix:ro" \
      "ubuntu:${ubuntu_version}" \
      bash;
  else
    docker start \
      --interactive \
      "${container_name}-${ubuntu_version}";
  fi
  echo "${core_patern}" | \
    sudo tee /proc/sys/kernel/core_pattern 2>/dev/null 1>&2;
  return ${?};
}

prpl_sdk_docker "${@}";
