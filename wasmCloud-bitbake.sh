#!/bin/bash
set -euo pipefail;

wasmCloud_dir="${2:-${HOME}/src/wasmCloud}";
patch_dir="${3:-${HOME}/src/prpl-wasmCloud/wasmCloud}";

get() {
  cd "${wasmCloud_dir}";
  local x="$(find . -type f -iname '*.orig')";
  local dest="${patch_dir}";
  local i;
  local dir;
  for i in ${x};
  do
    dir="$(dirname "${i}")";
    mkdir -p "${dest}/${dir}";
    diff -U 3 "${i}" "${i/%\.orig/}" > "${dest}/${i/%\.orig/\.patch}";
  done
}

apply() {
  cd "${patch_dir}";
  local x="$(find . -type f -iname '*.patch')";
  local dest="${wasmCloud_dir}";
  local i;
  for i in ${x};
  do
    patch -b "${dest}/${i/%\.patch/}" "${i}";
  done
}

restore() {
  cd "${wasmCloud_dir}";
  local x="$(find . -type f -iname '*.orig')";
  local i;
  for i in ${x};
  do
    mv -f "${i}" "${i/%\.orig/}";
  done
}

case "${1:-""}" in
  "get")
    get;
    ;;
  "apply")
    apply;
    ;;
  "restore")
    restore;
    ;;
  *)
    echo "Usage: ${BASH_SOURCE} <get|apply|restore> [wasmCloud source dir] [patches dir]";
    ;;
esac
