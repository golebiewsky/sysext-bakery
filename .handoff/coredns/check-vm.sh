#!/usr/bin/env bash
set -euo pipefail
probe="${1:-./dns-probe-x86-64}"
systemd-sysext status
getent passwd coredns
sudo systemctl is-active coredns.service
sudo systemctl is-enabled coredns.service
[[ "$(systemctl show coredns.service --property=User --value)" == coredns ]]
pid="$(systemctl show coredns.service --property=MainPID --value)"
[[ "$pid" -gt 0 ]]
sudo cat "/proc/$pid/status" | awk '/^(Uid|Gid|CapEff):/'
"$probe"
curl --fail --silent http://127.0.0.1:8080/health
curl --fail --silent http://127.0.0.1:8181/ready
printf '\nPASS: merged image, user, enablement, service, DNS, health and readiness\n'
