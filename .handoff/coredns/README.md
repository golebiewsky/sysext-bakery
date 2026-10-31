# CoreDNS PR handoff

See [VALIDATION.md](VALIDATION.md) for the corrected implementation and Flatcar VM results. The review and checklist below preserve the baseline investigation.

Continue work on [golebiewsky/sysext-bakery#1](https://github.com/golebiewsky/sysext-bakery/pull/1), branch `coredns-sysext`. The user wants this fork PR fixed and tested before a clean contribution goes to `flatcar/sysext-bakery`. This directory is temporary handoff material. Remove it before upstream submission.

## Start here

1. Read [REVIEW.md](REVIEW.md) for findings and completed checks. The reviewed implementation is commit `be78dd5a257fee5f89e4da48d86f3263ea7e585c`. The handoff commit changes no production module files.
2. Inspect the current diff and any later PR discussion. Read the repository's `CONTRIBUTING.md` and Flatcar's linked contribution guide.
3. Run `bash .handoff/coredns/prepare-local.sh` from the repo root on a Linux machine with Docker. This rebuilds the artifacts instead of relying on files from the previous workspace. Required tools: Bash, curl, jq, git, squashfs-tools, Go, Python 3, and Docker. The VM helper additionally needs QEMU and preferably KVM.
4. Follow [VM-TEST.md](VM-TEST.md). Capture the first boot state before applying any workaround. A Docker daemon alone does not prove Flatcar boot or sysext behavior.

The original workspace had no Docker daemon, QEMU, KVM, or systemd PID 1. Its amd64 DNS runtime checks ran the extracted binary as the workspace user on a high port. They did not test systemd sandboxing or low-port capabilities. Arm64 was built and inspected but not executed.

## Fix and verify

- Fix the wildcard listener in both documented examples. [suggested-listener-fix.patch](suggested-listener-fix.patch) is an unapplied proposal. From the repo root, inspect it and apply with `git apply .handoff/coredns/suggested-listener-fix.patch`. The sample uses loopback for DNS, health, and readiness; a remote-facing service needs a deliberate service address.
- Resolve account creation for live first install. Ordering after an already completed sysusers service does not create a new account. Consider a dedicated required account-creation unit, or evaluate `DynamicUser=yes` if persistent identity is unnecessary. Check first boot ordering on actual Flatcar before claiming a boot failure or success.
- Correct the `/opt` overlay explanation and the service-ordering prose identified in the review. Keep module comments short.
- Verify first boot, live first install, unprivileged execution, effective bind capability, UDP/TCP DNS, reload, invalid-config recovery, reboot, disabled-service behavior, delayed bind address recovery, update, and rollback. Test the actual sysupdate path separately from manual image replacement.
- Rebuild both architectures after fixes. Run arm64 runtime checks on a native arm64 VM if claiming runtime coverage. Record skips explicitly.
- The included `check-vm.sh` checks the test config, including its local record and health endpoints. It is a temporary handoff tool. Decide which useful regression checks belong in the permanent module test before deleting this directory.
- Update this fork PR with findings, fixes, exact tested revisions, Flatcar version, commands, results, and any remaining gaps. Do not describe workaround-assisted startup as a successful first boot.

## Before upstream submission

- Refresh against `flatcar/sysext-bakery:main` and review the final diff against upstream.
- Remove `.handoff/coredns/` and any generated artifacts or temporary plans. Keep only module code, useful permanent tests, docs, and release registration. The user explicitly wants a clean upstream PR without the plans.
- Prepare clean history without the temporary handoff commit or fork merge commit. A fresh branch from upstream main containing the final module diff is suitable. Do not force-push the current handoff branch without a user request.
- Commits must be GPG-signed. Flatcar also requires DCO `Signed-off-by` trailers. The original feature and merge commits lack those trailers. Have the contributor make their own DCO attestation; do not invent one for another author.
- Write a factual PR description with actual test evidence and the scope of AI assistance. Flatcar requires the submitter to personally read, understand, and test the contribution. No Linear ticket was provided.
- Open any upstream PR as a draft. Do not merge the fork PR or publish upstream until the fixes and integration checks are complete.

## Files

- `REVIEW.md`: findings, peer comparison, evidence limits, and upstream preparation.
- `VM-TEST.md` and `vm-test.bu`: disposable Flatcar VM procedure and deterministic test configuration.
- `prepare-local.sh`: rebuilds images, probes, and Ignition config under ignored `artifacts/`.
- `runtime-test.py`: direct amd64 binary tests for DNS, reload, and the resolver listener conflict.
- `dns-probe.go` and `check-vm.sh`: portable DNS probe source and guest checks.
- `suggested-listener-fix.patch`: proposed example listener fix; not applied.
- `evidence/`: original build/runtime logs and image hashes. Historical paths refer to the previous workspace. These logs are context, not evidence for later code revisions.
