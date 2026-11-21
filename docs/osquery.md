# osquery sysext

This sysext ships [osquery](https://osquery.io/), which exposes the operating system as a set of SQL tables.
It uses the Linux release tarball published by the osquery project.

The image contains:

- the `osqueryd` binary at `/usr/bin/osqueryd`, and `/usr/bin/osqueryi` as a symlink to it (osqueryd runs the interactive shell when called as `osqueryi`)
- the CA bundle from the release at `/usr/share/osquery/certs/certs.pem`
- the Augeas lenses from the release at `/usr/share/osquery/lenses`
- an `osqueryd.service` unit that runs the daemon as root with `--flagfile=/etc/osquery/osquery.flags`
- a `multi-user.target` drop-in with `Upholds=osqueryd.service`, so the daemon starts at boot and on merge
- a `tmpfiles.d` entry that creates `/var/osquery` (database, pidfile, extensions socket) and `/var/log/osquery` (filesystem logger)

The image is about 80 MB because `osqueryd` is a single large binary that bundles all tables.

Everything the image ships lives under `/usr`.
The release tarball installs to `/opt/osquery`; the extension moves the files to `/usr` instead, so `/opt` stays writable.
It does not ship `osqueryctl`: that script calls the SysV `service` command and hardcodes `/opt/osquery`, and neither exists on Flatcar.
It also does not ship the example config or the query packs from the tarball.

## Configuration

A sysext cannot ship files in `/etc`, so the extension ships no flags file and no config.
The unit has `ConditionPathExists=/etc/osquery/osquery.flags`.
Until that file exists, systemd skips the unit and nothing fails.
If you write the file after boot, start the daemon with `systemctl start osqueryd`.

Paths that differ from the upstream packages:

- `--tls_server_certs=/usr/share/osquery/certs/certs.pem` uses the bundle from the release. `/etc/ssl/certs/ca-certificates.crt` uses the Flatcar system bundle instead.
- `--augeas_lenses=/usr/share/osquery/lenses` is required for the `augeas` table. The built-in default points to `/opt/osquery`.

For a host without a management server, a flags file can be as small as:

```
--config_path=/etc/osquery/osquery.conf
--augeas_lenses=/usr/share/osquery/lenses
```

Results then go to the default filesystem logger in `/var/log/osquery`.
See the [osquery CLI flags](https://osquery.readthedocs.io/en/stable/installation/cli-flags/) for all flags.
Event tables (audit, BPF) need extra flags; see the [process auditing](https://osquery.readthedocs.io/en/stable/deployment/process-auditing/) docs.

## Service unit

The daemon runs as root because most tables read files and kernel interfaces that only root can read.
The unit sets `KillMode=control-group` and `TimeoutStopSec=15`, as the upstream packages do.
Stop and restart then end the watcher, the worker and any extension processes together.
A worker left over from an earlier start would hold the database lock and stop the new daemon from starting.

The unit only uses hardening options that do not hide host paths from tables:

| Option | Effect |
| ------ | ------ |
| `NoNewPrivileges=yes` | child processes cannot gain privileges through setuid binaries |
| `ProtectSystem=full` | `/usr`, `/boot` and `/etc` are read-only for osqueryd; they stay readable |
| `RestrictRealtime=yes` | no realtime scheduling |
| `RestrictSUIDSGID=yes` | osqueryd cannot create setuid or setgid files |
| `LockPersonality=yes` | the execution domain cannot change |

Options left out on purpose:

- `PrivateTmp=` gives the daemon its own `/tmp`, so file and hash tables would not see the host `/tmp`.
- `ProtectHome=` hides or locks `/home`, `/root` and `/run/user`, which tables such as `authorized_keys` and `shell_history` read.
- `PrivateDevices=` hides block devices from tables such as `block_devices`.
- `ProtectKernelModules=`, `ProtectKernelTunables=` and `ProtectControlGroups=` hide `/usr/lib/modules` or make `/proc/sys`, `/sys` and the cgroup tree read-only. The BPF and audit event publishers need to write there.
- `ProtectHostname=` gives the daemon its own UTS namespace, so it would miss host name changes made after it starts.
- `RestrictAddressFamilies=` and `SystemCallFilter=` would block the netlink and BPF interfaces the event publishers use.

The upstream packages also set `CPUQuota=20%`. This unit does not; osquery's own watchdog limits the worker.
To add a cap, use a drop-in:

```yaml
systemd:
  units:
    - name: osqueryd.service
      dropins:
        - name: 10-cpu-quota.conf
          contents: |
            [Service]
            CPUQuota=20%
```

To stop the daemon from starting, mask the unit: `systemctl mask --now osqueryd.service`.

## Usage

Download and merge the sysext at provisioning time using the below Butane snippet.
The snippet enrolls the host with a TLS management server.
Replace the host name, the endpoint paths and the enroll secret with the values of your server.
The enroll secret file is readable by root only.

The snippet includes automated updates via systemd-sysupdate.
Sysupdate will stage updates, refresh the merged sysext, and restart `osqueryd.service` — no reboot is required.
The update hook restarts the host's `systemd-sysext.service` so the merge runs outside the sysupdate sandbox.
You can deactivate updates by changing `enabled: true` to `enabled: false` in `systemd-sysupdate.timer`.

Note that the snippet is for the x86-64 version of osquery 5.24.1.
The build verifies the release tarball against the sha256 digest GitHub records for the release asset, because osquery publishes no checksum file.
GitHub has digests for osquery 5.18.1 and later, so older releases cannot be built.

Check out the metadata release at https://github.com/flatcar/sysext-bakery/releases/tag/osquery for a list of all versions available in the bakery.

```yaml
variant: flatcar
version: 1.0.0

storage:
  files:
    - path: /opt/extensions/osquery/osquery-5.24.1-x86-64.raw
      mode: 0644
      contents:
        source: https://extensions.flatcar.org/extensions/osquery-5.24.1-x86-64.raw
    - path: /etc/sysupdate.osquery.d/osquery.conf
      contents:
        source: https://extensions.flatcar.org/extensions/osquery.conf
    - path: /etc/sysupdate.d/noop.conf
      contents:
        source: https://extensions.flatcar.org/extensions/noop.conf
    - path: /etc/osquery/enroll.secret
      mode: 0600
      contents:
        inline: REPLACE_WITH_ENROLL_SECRET
    - path: /etc/osquery/osquery.flags
      mode: 0644
      contents:
        inline: |
          --host_identifier=uuid
          --tls_hostname=osquery.example.com:443
          --tls_server_certs=/usr/share/osquery/certs/certs.pem
          --enroll_secret_path=/etc/osquery/enroll.secret
          --enroll_tls_endpoint=/enroll
          --config_plugin=tls
          --config_tls_endpoint=/config
          --logger_plugin=tls
          --logger_tls_endpoint=/log
          --disable_distributed=false
          --distributed_plugin=tls
          --distributed_tls_read_endpoint=/distributed_read
          --distributed_tls_write_endpoint=/distributed_write
          --augeas_lenses=/usr/share/osquery/lenses
  links:
    - target: /opt/extensions/osquery/osquery-5.24.1-x86-64.raw
      path: /etc/extensions/osquery.raw
      hard: false
systemd:
  units:
    - name: systemd-sysupdate.timer
      enabled: true
    - name: systemd-sysupdate.service
      dropins:
        - name: osquery.conf
          contents: |
            [Service]
            ExecStartPre=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/osquery.raw > /run/osquery-sysext"
            ExecStartPre=/usr/lib/systemd/systemd-sysupdate -C osquery update
            ExecStartPost=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/osquery.raw > /run/osquery-sysext-new"
            ExecStartPost=/usr/bin/sh -c "if ! cmp --silent /run/osquery-sysext /run/osquery-sysext-new; then systemctl restart systemd-sysext.service && systemctl restart osqueryd.service; fi"
```
