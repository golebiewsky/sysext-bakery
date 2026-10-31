# Disposable Flatcar VM test

Use a disposable Flatcar stable amd64 VM with 2 vCPUs, 2 GiB RAM, and 10 GiB disk. These are test sizing suggestions. Use a host with KVM and a running Docker daemon for the bakery's VM helper. This workspace has neither, so no Flatcar VM test has run here.

The test config uses a loopback DNS listener and a local hosts record. It does not depend on public recursive DNS or unreleased bakery URLs. It keeps systemd-resolved running. It intentionally retains the PR's sysusers setup so the first boot test can expose user creation failures.

## Start with the bakery helper

Check out the PR branch on a Linux host with QEMU, KVM, Docker, curl, jq, squashfs-tools, and xz-utils. Run `bash .handoff/coredns/prepare-local.sh` from the repo root to rebuild artifacts. Start the VM from the repo root:

```bash
./bakery.sh boot .handoff/coredns/artifacts/coredns-v1.14.7-x86-64.raw --butane "$PWD/.handoff/coredns/vm-test.bu" --ports 2222:22
```

The helper transpiles Butane through Docker and serves the raw image at `http://10.0.2.2:12345/`. It downloads the current Flatcar alpha image by default. For upstream evidence, repeat on stable by supplying the four stable Flatcar QEMU UEFI files described in `lib/boot.sh` before starting the helper. Use the serial console or add your SSH public key under `passwd.users` for SSH. Never add a private key.

For a cloud VM, replace the HTTP source in `vm-test.bu` with a temporary HTTPS URL for the built image, add your SSH public key, transpile the config, and pass `vm-test.ign` as Ignition user data. The generated `artifacts/vm-test.ign` uses QEMU's host IP and therefore cannot download the image on a cloud VM without that source change.

## First boot

Copy `.handoff/coredns/check-vm.sh` and `.handoff/coredns/artifacts/dns-probe-x86-64` to the guest with SCP or your VM file transfer method. Run these before repairing anything:

```bash
cat /etc/os-release
sudo systemd-sysext status
getent passwd coredns
sudo systemctl status coredns.service systemd-sysusers.service --no-pager
sudo journalctl -b -u systemd-sysext -u systemd-sysusers -u coredns --no-pager
bash ./check-vm.sh ./dns-probe-x86-64
```

A missing user or `217/USER` failure is evidence of the sysusers lifecycle problem. Capture it before running this workaround:

```bash
sudo systemd-sysusers /usr/lib/sysusers.d/coredns.conf
sudo systemctl restart coredns.service
bash ./check-vm.sh ./dns-probe-x86-64
```

The workaround must not be counted as a passing first boot. `After=systemd-sysusers.service` orders units but does not cause sysusers to run again after a live merge. The PR also supplies no ordering from sysext merge to the boot sysusers service. Record the actual first boot result before deciding the permanent fix.

## Reload and reboot

```bash
sudo sed -i 's/192.0.2.10/192.0.2.20/' /etc/coredns/Corefile
sudo systemctl reload coredns.service
sleep 1
./dns-probe-x86-64 127.0.0.1:53 192.0.2.20
sudo sed -i 's/192.0.2.20/192.0.2.10/' /etc/coredns/Corefile
sudo systemctl reload coredns.service
sudo reboot
```

After reboot, run `check-vm.sh` again. Confirm that the user remains unprivileged and that effective capabilities include `CAP_NET_BIND_SERVICE` (bit 10). The test probe checks UDP and TCP answers independently.

## Live image upgrade

Copy `.handoff/coredns/artifacts/coredns-v1.15.0-x86-64.raw` to the guest. Run:

```bash
sudo install -m 0644 coredns-v1.15.0-x86-64.raw /opt/extensions/coredns/
sudo ln -sfn /opt/extensions/coredns/coredns-v1.15.0-x86-64.raw /etc/extensions/coredns.raw
sudo systemctl restart systemd-sysext.service
sudo systemctl restart coredns.service
/usr/bin/coredns -version
bash ./check-vm.sh ./dns-probe-x86-64
```

Repeat with the symlink pointing to v1.14.7 to test rollback. This checks live image replacement and restart. It does not validate the complete systemd-sysupdate transfer path. To test the PR's exact update drop-in before upstream publishes CoreDNS, host both images and a checksum index in a temporary test location and use a local sysupdate transfer file. Confirm that unchanged versions do not restart the service and that a changed version does.

## Listener conflict

The PR's original config uses `.:53` with no `bind` restriction. If systemd-resolved owns `127.0.0.53:53`, that wildcard listener cannot start. The local runtime test reproduces this with a stub socket on the same address at a high port. The proposed patch binds DNS, health, and readiness to loopback. Sites that need remote clients should select a specific service address and access policy.

## Remaining acceptance checks

- First boot creates the account and starts the service without the workaround.
- A live first install creates the account before starting the service.
- The service stays off when no site config or enablement is supplied.
- Delayed appearance of a configured bind address recovers through the restart policy.
- Merge and unmerge leave unrelated `/opt` content visible and writable as expected.
- Actual systemd-sysupdate runs the documented update path.
- A native arm64 VM runs the same checks before claiming arm64 runtime support was tested.

For a cloud VM, transpile the edited config with `docker run --rm -i quay.io/coreos/butane:v0.29.0 --strict --pretty < .handoff/coredns/vm-test.bu > .handoff/coredns/artifacts/vm-test.ign`. Preserve the original config for repeatable QEMU runs.
