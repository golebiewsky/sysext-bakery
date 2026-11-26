# Prometheus node_exporter sysext

This sysext ships the [Prometheus node exporter](https://github.com/prometheus/node_exporter), which exposes host hardware and kernel metrics for Prometheus.
It uses the static release binary published by the Prometheus project.

The image contains:

- the `node_exporter` binary at `/usr/bin/node_exporter`
- a `node_exporter.service` unit that runs the exporter as an unprivileged `node_exporter` user with a read-only view of the file system
- a `sysusers.d` entry that creates that `node_exporter` system user, and a `node_exporter-sysusers.service` unit that applies it before the exporter starts, also on a live merge after boot
- a `multi-user.target` drop-in with `Upholds=node_exporter.service`, so the exporter starts at boot and on merge
- a `tmpfiles.d` entry that creates `/var/lib/node_exporter` for the textfile collector

## Configuration

By default the exporter listens on port 9100 on all addresses and reads `*.prom` files from `/var/lib/node_exporter`:

```
--web.listen-address=:9100 --collector.textfile.directory=/var/lib/node_exporter
```

To change the flags, set `NODE_EXPORTER_ARGS` in `/etc/default/node_exporter`.
The value replaces the defaults, so repeat any default flag you want to keep.
See `node_exporter --help` for all flags.

```
NODE_EXPORTER_ARGS="--web.listen-address=127.0.0.1:9100 --collector.textfile.directory=/var/lib/node_exporter --collector.systemd"
```

Run `systemctl restart node_exporter` after you change the file.

The exporter runs as a static user, not a systemd `DynamicUser=`.
On hosts with `dbus-daemon`, as on Flatcar, the bus cannot resolve dynamic UIDs and closes their connections, so `--collector.systemd` would fail.

The textfile directory is owned by root with mode 0755.
Jobs that write metrics there should write to a temporary file and rename it into place, so the exporter never reads a partial file.

To stop the exporter from starting, mask the unit: `systemctl mask --now node_exporter.service`.

## Usage

Download and merge the sysext at provisioning time using the below Butane snippet.

The snippet includes automated updates via systemd-sysupdate.
Sysupdate will stage updates, refresh the merged sysext, and restart `node_exporter.service` — no reboot is required.
The update hook restarts the host's `systemd-sysext.service` so the merge runs outside the sysupdate sandbox.
You can deactivate updates by changing `enabled: true` to `enabled: false` in `systemd-sysupdate.timer`.

Note that the snippet is for the x86-64 version of node_exporter v1.13.0.

Check out the metadata release at https://github.com/flatcar/sysext-bakery/releases/tag/node_exporter for a list of all versions available in the bakery.

```yaml
variant: flatcar
version: 1.0.0

storage:
  files:
    - path: /opt/extensions/node_exporter/node_exporter-v1.13.0-x86-64.raw
      mode: 0644
      contents:
        source: https://extensions.flatcar.org/extensions/node_exporter-v1.13.0-x86-64.raw
    - path: /etc/sysupdate.node_exporter.d/node_exporter.conf
      contents:
        source: https://extensions.flatcar.org/extensions/node_exporter.conf
    - path: /etc/sysupdate.d/noop.conf
      contents:
        source: https://extensions.flatcar.org/extensions/noop.conf
    - path: /etc/default/node_exporter
      mode: 0644
      contents:
        inline: |
          NODE_EXPORTER_ARGS="--web.listen-address=:9100 --collector.textfile.directory=/var/lib/node_exporter"
  links:
    - target: /opt/extensions/node_exporter/node_exporter-v1.13.0-x86-64.raw
      path: /etc/extensions/node_exporter.raw
      hard: false
systemd:
  units:
    - name: systemd-sysupdate.timer
      enabled: true
    - name: systemd-sysupdate.service
      dropins:
        - name: node_exporter.conf
          contents: |
            [Service]
            ExecStartPre=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/node_exporter.raw > /run/node_exporter-sysext"
            ExecStartPre=/usr/lib/systemd/systemd-sysupdate -C node_exporter update
            ExecStartPost=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/node_exporter.raw > /run/node_exporter-sysext-new"
            ExecStartPost=/usr/bin/sh -c "if ! cmp --silent /run/node_exporter-sysext /run/node_exporter-sysext-new; then systemctl restart systemd-sysext.service && systemctl restart node_exporter.service; fi"
```
