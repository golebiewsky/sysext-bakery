# Flatcar validation

Test date: 2026-10-31. Source revision: `1635d4642f48a4ea0a0bdccb0b36af47f7590559`. The rebuilt images contain the production module files in this commit. The commit also includes documentation and test-script corrections. The evidence directory is temporary fork material and must be removed before upstream submission.

## Environment and commands

Flatcar stable 4757.2.3, kernel 6.12.114-flatcar, amd64. QEMU runs with KVM in a Docker container, 2 vCPUs, 2 GiB RAM, and `-snapshot`. The test uses the versioned Flatcar QEMU UEFI download. Guest provisioning uses `vm-test.bu` plus a temporary SSH public key. No account-creation workaround is used for the first boot checks.

Run `bash .handoff/coredns/prepare-local.sh` to rebuild the original test matrix: v1.14.7 for x86-64 and arm64, plus v1.15.0 for x86-64. Run the VM checks in `VM-TEST.md` with the fresh images. The actual sysupdate check uses the documented service drop-in and the generated transfer definition with its source URL pointed at a local HTTP server. A SHA256SUMS index lists the freshly built images.

## Results

| Check | Result |
| --- | --- |
| Builds and image tests | Pass for both advertised architectures; arm64 execution skipped |
| First boot with supplied config and enablement | Pass without account workaround |
| Service identity and effective capabilities | UID/GID 999; only CAP_NET_BIND_SERVICE (`0x400`) |
| UDP/TCP DNS on port 53, health, readiness | Pass |
| Service unit verification | Pass |
| Reload without process exit | Pass |
| Invalid reload preserves working answers | Pass |
| Invalid startup config repaired during automatic restarts | Pass |
| Shipped example beside active systemd-resolved | Pass |
| Bind address appears after failed starts | Pass without another start command |
| Live reinstall after account removal and completed boot sysusers | Pass; dedicated account service creates the user |
| `/opt` visible and writable with extension merged | Pass |
| Actual sysupdate v1.14.7 to v1.15.0 | Pass; download, symlink, host merge, restart, and DNS checked |
| Unchanged sysupdate | Pass; CoreDNS PID stays unchanged |
| Manual rollback to v1.14.7 | Pass; version and DNS checked |
| Enabled service after reboot | Pass; boot ID changes and DNS recovers |
| Fresh merge without config or enablement | Pass; disabled, inactive, no invocation or restarts |
| Full usage example transpilation | Pass with Butane v0.29.0 in strict mode |
| Bash syntax, ShellCheck, diff whitespace | Pass |

ShellCheck excludes SC2034 because the shared bakery code consumes `RELOAD_SERVICES_ON_MERGE`. The shared sysupdate template emits warnings about `.conf` naming and an implicit target MatchPattern. The update succeeds with those warnings.

## Evidence

Captured results and image hashes are in [evidence/flatcar-2026-10-31/](evidence/flatcar-2026-10-31/). Baseline failure logs reproduce the wildcard listener conflict, missing live-install account (`217/USER`), and direct sysext execution failing inside the sysupdate sandbox. Corrected results are in `fixed-checks.log` and `sysupdate-fixed-checks.log`.

## Coverage limits

Arm64 has build and image-content coverage only. No arm64 binary or native arm64 VM is executed. DNS checks use a deterministic local record; public recursive resolution and remote-client policy are not tested. `/opt` is checked while merged; a separate sentinel test spanning a full unmerge/merge cycle is not run. Rollback uses a manual image symlink change rather than a sysupdate downgrade.

The upstream contribution still needs a clean branch without handoff material, contributor review, signed commits, and the contributor's DCO attestation. No upstream PR is opened. No Linear ticket is supplied.
