#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# osquery system extension.
#

RELOAD_SERVICES_ON_MERGE="true"

function list_available_versions() {
  list_github_releases "osquery" "osquery" \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$'
}
# --

function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  local rel_arch
  rel_arch="$(arch_transform "x86-64" "x86_64" "$arch")"
  rel_arch="$(arch_transform "arm64" "aarch64" "$rel_arch")"

  local tarball="osquery-${version}_1.linux_${rel_arch}.tar.gz"
  local baseurl="https://github.com/osquery/osquery/releases/download/${version}"

  # osquery publishes no checksum file. Use the sha256 digest GitHub records
  # for each release asset; releases from before mid-2025 have none.
  announce "Fetching release asset digest for ${tarball}"
  local digest
  digest="$(curl_api_wrapper \
              "https://api.github.com/repos/osquery/osquery/releases/tags/${version}" \
            | jq -r --arg name "${tarball}" \
                '.assets[] | select(.name == $name) | .digest // empty')"
  if [[ ! ${digest} =~ ^sha256:[0-9a-f]{64}$ ]] ; then
    echo "ERROR: no sha256 digest for '${tarball}' in release '${version}'."
    return 1
  fi

  announce "Fetching osquery ${version} for ${arch}"
  curl -fsSL --retry-delay 1 --retry 60 \
    --retry-connrefused --retry-max-time 60 --connect-timeout 20 \
    -O "${baseurl}/${tarball}"

  announce "Verifying ${tarball}"
  echo "${digest#sha256:}  ${tarball}" | sha256sum --check --strict

  local share="opt/osquery/share/osquery"
  tar --force-local -xf "${tarball}" \
    opt/osquery/bin/osqueryd "${share}/certs/certs.pem" "${share}/lenses"

  # The tarball installs to /opt/osquery and links /usr/bin to it.
  # Ship real files under /usr only; osqueryd runs as the shell when called as osqueryi.
  install -D -m 0755 opt/osquery/bin/osqueryd "${sysextroot}/usr/bin/osqueryd"
  ln -s osqueryd "${sysextroot}/usr/bin/osqueryi"

  install -D -m 0644 "${share}/certs/certs.pem" \
    "${sysextroot}/usr/share/osquery/certs/certs.pem"
  mkdir -p "${sysextroot}/usr/share/osquery/lenses"
  install -m 0644 -t "${sysextroot}/usr/share/osquery/lenses" "${share}"/lenses/*
}
# --
