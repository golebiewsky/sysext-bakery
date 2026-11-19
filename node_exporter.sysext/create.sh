#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# Prometheus node_exporter system extension.
#

RELOAD_SERVICES_ON_MERGE="true"

function list_available_versions() {
  list_github_releases "prometheus" "node_exporter" \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'
}
# --

function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  # Release tags are "vX.Y.Z"; the release archives drop the leading "v".
  local relver="${version#v}"

  local rel_arch
  rel_arch="$(arch_transform "x86-64" "amd64" "$arch")"

  local dirname="node_exporter-${relver}.linux-${rel_arch}"
  local tarball="${dirname}.tar.gz"
  local baseurl="https://github.com/prometheus/node_exporter/releases/download/v${relver}"

  announce "Fetching node_exporter ${version} for ${arch}"
  curl -fsSLZ --retry-delay 1 --retry 60 \
    --retry-connrefused --retry-max-time 60 --connect-timeout 20 \
    -O "${baseurl}/${tarball}" \
    -O "${baseurl}/sha256sums.txt"

  # Check only the entry for this tarball, and fail if it is missing.
  announce "Verifying ${tarball}"
  grep -E "^[0-9a-f]{64}  ${tarball}\$" sha256sums.txt > "${tarball}.sha256" \
    || { echo "ERROR: no checksum for '${tarball}' in sha256sums.txt"; return 1; }
  sha256sum --check --strict "${tarball}.sha256"

  tar --force-local -xf "${tarball}" --strip-components=1 "${dirname}/node_exporter"
  mkdir -p "${sysextroot}/usr/bin"
  install -m 0755 node_exporter "${sysextroot}/usr/bin/"
}
# --
