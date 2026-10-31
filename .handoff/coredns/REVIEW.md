# CoreDNS sysext review

Reviewed fork PR https://github.com/golebiewsky/sysext-bakery/pull/1 at `be78dd5a257fee5f89e4da48d86f3263ea7e585c` on 2026-10-31. Compared with `flatcar/sysext-bakery` main at `b00022e`, including the extension skeleton, Consul, Nomad, Chrony, HAProxy, shared generation code, and release workflow.

The packaging is sound and follows bakery conventions. Fix the example listener and user lifecycle before submitting upstream. A Flatcar VM run is still required. At the time of the review, no changes were pushed, no GitHub comments were posted, and no VM was provisioned. The later handoff commit stores these findings in the fork PR. It does not fix the reviewed implementation.

## Findings

1. **P1: The example DNS listener conflicts with an active resolver stub.** `docs/coredns.md:76` and `coredns.sysext/files/usr/share/doc/coredns/Corefile.example:6` use `.:53` without `bind`, while the extension explicitly leaves systemd-resolved running. A wildcard DNS socket conflicts with the resolved stub on `127.0.0.53:53`. The runtime test reproduced this with the same address relationship at port 10539. Use a specific service address. `suggested-listener-fix.patch` supplies a loopback example and also binds health/readiness to loopback. It passes `git apply --check` against the reviewed checkout. This patch is a proposal and has not been applied.

2. **P1 for live first install: shipping sysusers configuration does not create the account on merge.** `coredns.sysext/files/usr/lib/systemd/system/coredns.service:8` only orders the service after systemd-sysusers. If sysusers already ran, merging the extension and starting CoreDNS does not run it again. `User=coredns` then fails if the account does not exist. The image metadata asks for a manager reload, which does not execute sysusers. Document the explicit live-install sysusers step, or add a dedicated account-creation unit required by CoreDNS. `DynamicUser=yes` is another design option if persistent identity is unnecessary. At first boot, the PR also supplies no explicit merge-before-sysusers ordering; whether it succeeds on the target Flatcar release remains a VM test, not an observed failure here.

3. **Submission blocker: commit sign-offs are missing.** Neither PR commit has a `Signed-off-by` trailer. Flatcar's current contribution guide requires sign-off and clean history. Prepare a clean commit based on current upstream with the author's DCO sign-off and the required GPG signature. A GPG signature and a DCO sign-off are separate requirements. The contributor must make their own DCO attestation.

4. **P2: The test does not cover service integration.** `coredns.sysext/test.sh` checks image contents and a native version command. It does not check account creation, capabilities, port 53, reboot, service reload, or sysupdate. It skips execution for arm64 here. The shared `lib/test.sh` is empty, most peer tests are empty, and the release workflow does not invoke this test. Run it directly and attach VM evidence rather than assuming it is a CI gate.

5. **Documentation corrections:** The claim that shipping `/opt` hides existing lower-layer files is too broad. Overlay mounts normally retain the lower files; making the hierarchy read-only affects writes. Also, the service orders after sysusers as well as network-online, so the prose saying it orders after network-online “and nothing else” is inaccurate. The comment calling sysusers a generator should call it a service or tool.

## Comparison with other extensions

| Area | CoreDNS result |
| --- | --- |
| Build interface | Uses the same `list_available_versions` and `populate_sysext_root` functions as the skeleton and peers. |
| Architectures | Uses the shared `arch_transform` mapping. Both advertised architectures build. |
| Download integrity | Verifies the upstream archive checksum. Several peers do not perform this check. The checksum and binary share the same release source; this is not an independent signature. |
| Filesystem layout | Ships only `/usr`; avoids the Flatcar `/usr/sbin` symlink trap. |
| Service discovery | Sets `RELOAD_SERVICES_ON_MERGE=true`, matching service extensions. |
| Service enablement | Site-controlled startup is reasonable for a service requiring site configuration. Verify Butane enablement on first boot. Other modules often use explicit wants links. |
| User lifecycle | Introduces a sysusers-based account without a live-merge creation step. Peer service patterns do not validate this new assumption. |
| Release automation | Adds a pinned version and `latest` using the existing release list. Latest lookup currently returns v1.15.0. |
| Documentation | Adds the module to the index and supplies a sysupdate example. Published upstream CoreDNS image URLs will only work after the extension is released. |

## Executed checks

- Built v1.14.7 squashfs images for x86-64 and arm64 through the unmodified `bakery.sh` path. Both upstream checksums verified. Logs: `evidence/build-x86-64.log`, `evidence/build-arm64.log`.
- Ran the PR's image test against both images. Both passed. The arm64 binary version check was skipped because this host is amd64.
- Checked ELF program headers for the amd64 binary. There is no interpreter segment.
- Resolved `latest` to v1.15.0, built the amd64 image, and ran the image test successfully. Log: `evidence/build-latest.log`.
- Ran the extracted amd64 v1.14.7 binary as the workspace user on loopback port 10539. UDP and TCP DNS queries returned the expected local record. SIGUSR1 changed the answer without process exit. An invalid reload preserved the old answer. SIGTERM exited with status 0. See `runtime-test.py` and `evidence/runtime.log`.
- Reproduced the wildcard/stub listener conflict. See `evidence/stub-conflict.log`.
- Validated the sysusers line with `systemd-sysusers --root=... --dry-run`. It creates the matching user and group when explicitly invoked. No workspace account was created.
- Transpiled both the original PR's full Butane usage example and `vm-test.bu` with Butane v0.29.0 in strict mode. Both passed. This checks configuration syntax, not boot behavior or download availability.
- Ran Bash syntax checks. ShellCheck reports an externally consumed variable in `create.sh` (SC2034) and an eagerly expanded cleanup trap in `test.sh` (SC2064). Neither is a demonstrated functional defect.
- `systemd-analyze verify` found no unknown directives but reported that `/usr/bin/coredns` is absent on the workspace host. Full unit execution and capability checks were not performed.
- Compiled static amd64 and arm64 DNS probes. Executed the amd64 probe against CoreDNS for both UDP and TCP. The arm64 probe was not executed.

The workspace has no `/dev/kvm`, no QEMU binary, no Docker socket, and no systemd PID 1. No Flatcar merge, boot, systemd service, capability, or sysupdate test is claimed. `VM-TEST.md` describes the remaining work and includes a first boot test that does not silently repair account creation.

## Upstream submission

The current PR targets the fork's main branch. To contribute to Flatcar, create a new draft PR targeting `flatcar/sysext-bakery:main` from a corrected branch in the fork. The branch is only four upstream commits behind at review time. Prefer a clean branch from upstream main and one reviewed feature commit over carrying the fork merge commit.

Add a specific title such as `feat(coredns): add CoreDNS system extension`. Include the problem, opt-in service behavior, architecture coverage, executed checks, remaining limitations, and the scope of AI assistance. Flatcar's guide requires the human submitter to personally read, understand, and test the contribution. No Linear ticket was provided.

References: [bakery contribution guide](https://github.com/flatcar/sysext-bakery/blob/main/CONTRIBUTING.md), [Flatcar contribution rules](https://github.com/flatcar/Flatcar/blob/main/CONTRIBUTING.md), [Flatcar sysext lifecycle guidance](https://www.flatcar.org/docs/latest/sys-ext/), [CoreDNS reload behavior](https://coredns.io/plugins/reload/).

## Handoff storage

Start at [README.md](README.md) for the continuation checklist. This directory is temporary fork-only material. Generated images, probes, extracted trees, and Ignition output belong under ignored `artifacts/`. The evidence logs describe the original review run. Rebuild and capture fresh evidence after changes. Historical paths in those logs refer to the reviewing workspace. Remove the whole `.handoff/coredns/` directory before upstream submission.
