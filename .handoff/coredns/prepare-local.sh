#!/usr/bin/env bash
set -euo pipefail

handoff_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$handoff_dir/../.." && pwd)"
mkdir -p "$handoff_dir/artifacts"
cd "$handoff_dir/artifacts"

for arch in x86-64 arm64; do
  "$repo_dir/bakery.sh" create coredns v1.14.7 --arch "$arch" \
    --output-file "coredns-v1.14.7-$arch.raw" --sysupdate true \
    > "build-$arch.log" 2>&1
  bash "$repo_dir/coredns.sysext/test.sh" "coredns-v1.14.7-$arch.raw"
done

"$repo_dir/bakery.sh" create coredns v1.15.0 \
  --output-file coredns-v1.15.0-x86-64.raw > build-latest.log 2>&1
bash "$repo_dir/coredns.sysext/test.sh" coredns-v1.15.0-x86-64.raw
sha256sum coredns-v*.raw > SHA256SUMS.review

CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o dns-probe-x86-64 "$handoff_dir/dns-probe.go"
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o dns-probe-arm64 "$handoff_dir/dns-probe.go"

docker run --rm -i quay.io/coreos/butane:v0.29.0 --strict --pretty \
  < "$handoff_dir/vm-test.bu" > vm-test.ign

if [[ "$(uname -m)" == x86_64 ]]; then
  unsquashfs -no-progress -force -dest root-x86 coredns-v1.14.7-x86-64.raw > extract.log
  python3 "$handoff_dir/runtime-test.py" | tee runtime-results.log
else
  echo 'SKIP: amd64 runtime test requires an x86_64 Linux host.'
fi

echo "Artifacts are ready in $handoff_dir/artifacts. Continue with VM-TEST.md."
