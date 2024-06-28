#!/bin/bash
set -euo pipefail;

get_ipaddr() {
  local errmsg="ERROR: ${FUNCNAME[0]}:";
  local network_device="${1:?"${errmsg} Missing network device (e.g.: enp0s31f6, enx381428d84cb8)"}";
  ip address show dev "${network_device}" | \
    awk '/inet /{split($2,x,"/"); printf("%s",x[1]);}';
}

local_docker_registry() {
  local network_device="${1:-"${DEFAULT_NETWORK_DEVICE}"}";
  local etc_path="${2:-"${HOME}/etc"}";
  local certs_name="${3:-"docker-registry"}";
  local htpasswd_name="${4:-"htpasswd"}";
  local certs_size="${5:-"4096"}";
  local certs_days="${6:-"365"}";
  local registry_port="${7:-"5000"}";
  local login="${8:-"$(id -un)"}";
  local passwd="${9:-"${login}"}";
  local auth_path="${etc_path}/auth";
  local certs_path="${etc_path}/certs";
  local data_path="${etc_path}/data";

  if [ -n "$(docker container ls|awk '$2~/registry/')" ];
  then
    docker rm --force registry;
  fi
  sudo rm -rf "${etc_path}" && \
  mkdir -p "${etc_path}" && \
  mkdir -p "${auth_path}" "${certs_path}" "${data_path}" && \
  htpasswd -Bbc "${auth_path}/${htpasswd_name}" "${login}" "${passwd}" && \
  openssl req \
    -newkey rsa:"${certs_size}" \
    -nodes -keyout "${certs_path}/${certs_name}.key" \
    -out "${certs_path}/${certs_name}.csr" \
    -subj "/C=FR/ST=Paris/L=Paris/O=My Compagny/CN=$(get_ipaddr "${network_device}")" && \
  openssl x509 \
    -signkey "${certs_path}/${certs_name}.key" \
    -in "${certs_path}/${certs_name}.csr" \
    -req -days "${certs_days}" \
    -out "${certs_path}/${certs_name}.crt" \
    -extfile <(printf "subjectAltName=IP:$(get_ipaddr "${network_device}")") && \
  rm -f "${certs_path}/${certs_name}.csr" && \
  docker run -d --restart=always --name registry \
  -v "${auth_path}":"/auth" \
  -v "${certs_path}":"/certs" \
  -v "${data_path}":"/var/lib/registry" \
  -e REGISTRY_AUTH="htpasswd" \
  -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
  -e REGISTRY_AUTH_HTPASSWD_PATH="/auth/${htpasswd_name}" \
  -e REGISTRY_HTTP_ADDR="0.0.0.0:${registry_port}" \
  -e REGISTRY_HTTP_TLS_CERTIFICATE="/certs/${certs_name}.crt" \
  -e REGISTRY_HTTP_TLS_KEY="/certs/${certs_name}.key" \
  -p "${registry_port}":"${registry_port}" \
  registry:latest && \
  curl -u "${login}":"${passwd}" -k https://$(get_ipaddr "${network_device}"):${registry_port}/v2/_catalog;
  return $?;
}

local_docker_registry "${@}";
