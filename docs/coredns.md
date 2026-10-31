# CoreDNS sysext

This sysext ships [CoreDNS](https://coredns.io/), the pluggable DNS server, as the static release binary published by the CoreDNS project.

The image contains:

- the `coredns` binary at `/usr/bin/coredns`
- a `coredns.service` unit that runs CoreDNS as an unprivileged `coredns` user with `CAP_NET_BIND_SERVICE`, so it can bind port 53 without root
- a `sysusers.d` entry that creates that `coredns` system user
- a commented example configuration at `/usr/share/doc/coredns/Corefile.example`

Everything the image ships lives under `/usr`. Shipping paths under `/opt` would make that hierarchy a read-only overlay. Existing lower-layer files would remain visible, but writes through the overlay would fail. This extension leaves `/opt` writable.

## Configuration

The extension ships no `Corefile`, and it cannot: a sysext merges `/usr` and `/opt`, never `/etc`. The unit reads `/etc/coredns/Corefile`, which is the common convention. Write that file with Ignition, with config management, or by hand. Start from `/usr/share/doc/coredns/Corefile.example`. CoreDNS never reads the example itself.

CoreDNS exits when an address named in a `bind` directive is not up yet. That happens on a node that binds a link-local address on an interface `systemd-networkd` brings up during boot. The unit therefore sets `Restart=on-failure` with `RestartSec=2s`, and disables start rate limiting with `StartLimitIntervalSec=0`, so the service recovers on its own once the address appears.

`systemctl reload coredns` sends `SIGUSR1`, which makes CoreDNS re-read the `Corefile` without dropping queries.

## Service ordering

The shipped unit orders itself after `network-online.target` and requires `coredns-sysusers.service`. That service runs `systemd-sysusers` with the shipped account definition before CoreDNS starts. It works at boot and on a live first install, even when the boot sysusers service has already finished.

What CoreDNS must start before is a site decision. Add your own ordering with a drop-in rather than replacing the unit:

```yaml
systemd:
  units:
    - name: coredns.service
      enabled: true
      dropins:
        - name: 10-local-ordering.conf
          contents: |
            [Unit]
            Wants=sys-devices-virtual-net-nodelocal0.device
            After=sys-devices-virtual-net-nodelocal0.device
            Before=consul.service
```

The extension does not start CoreDNS by itself. It ships no `multi-user.target.upholds` drop-in, so a node that merges the image before its `Corefile` exists does not get a failing service. Enable the unit when the config is in place, as the snippet below does.

The extension also does not touch `systemd-resolved`. The example binds DNS, health, and readiness to `127.0.0.1`. This avoids a wildcard DNS listener that conflicts with the resolved stub at `127.0.0.53:53`. For remote clients, choose a specific service address and an access policy.

## Host resolver integration

Starting CoreDNS does not make it the host resolver. The usage example leaves `systemd-resolved` and `/etc/resolv.conf` unchanged. Applications can query CoreDNS directly at `127.0.0.1:53`.

To make CoreDNS the host resolver, configure the cutover in site provisioning. Supply the required internal zones and explicit upstream DNS servers. Stop competing listeners such as dnsmasq, verify that CoreDNS answers, and direct host lookups to it. If replacing `systemd-resolved`, disable that service and replace its resolver symlink with a managed `/etc/resolv.conf`. Coordinate any DHCP or Tailscale settings that manage host DNS.

Do not forward CoreDNS queries to `/etc/resolv.conf` when that file points back to CoreDNS. For containers or remote clients, add explicit service addresses to every DNS server block and configure the required interface ordering and access policy.

## Usage

Download and merge the sysext at provisioning time using the below Butane snippet.

The snippet includes automated updates via systemd-sysupdate.
Sysupdate will stage updates, refresh the merged sysext, and restart `coredns.service` — no reboot is required.
The update hook restarts the host's `systemd-sysext.service` so the merge runs outside the sysupdate sandbox.
You can deactivate updates by changing `enabled: true` to `enabled: false` in `systemd-sysupdate.timer`.

Note that the snippet is for the x86-64 version of CoreDNS v1.14.7.

Check out the metadata release at https://github.com/flatcar/sysext-bakery/releases/tag/coredns for a list of all versions available in the bakery.

```yaml
variant: flatcar
version: 1.0.0

storage:
  files:
    - path: /opt/extensions/coredns/coredns-v1.14.7-x86-64.raw
      mode: 0644
      contents:
        source: https://extensions.flatcar.org/extensions/coredns-v1.14.7-x86-64.raw
    - path: /etc/sysupdate.coredns.d/coredns.conf
      contents:
        source: https://extensions.flatcar.org/extensions/coredns.conf
    - path: /etc/sysupdate.d/noop.conf
      contents:
        source: https://extensions.flatcar.org/extensions/noop.conf
    - path: /etc/coredns/Corefile
      mode: 0644
      contents:
        inline: |
          .:53 {
              bind 127.0.0.1
              errors
              health 127.0.0.1:8080
              ready 127.0.0.1:8181
              forward . 9.9.9.9 1.1.1.1
              cache 30
              loop
              reload
          }
  links:
    - target: /opt/extensions/coredns/coredns-v1.14.7-x86-64.raw
      path: /etc/extensions/coredns.raw
      hard: false
systemd:
  units:
    - name: coredns.service
      enabled: true
    - name: systemd-sysupdate.timer
      enabled: true
    - name: systemd-sysupdate.service
      dropins:
        - name: coredns.conf
          contents: |
            [Service]
            ExecStartPre=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/coredns.raw > /run/coredns-sysext"
            ExecStartPre=/usr/lib/systemd/systemd-sysupdate -C coredns update
            ExecStartPost=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/coredns.raw > /run/coredns-sysext-new"
            ExecStartPost=/usr/bin/sh -c "if ! cmp --silent /run/coredns-sysext /run/coredns-sysext-new; then systemctl restart systemd-sysext.service && systemctl restart coredns.service; fi"
```

## Testing a built image

`coredns.sysext/test.sh` checks a locally built image:

```bash
./bakery.sh create coredns v1.14.7
./coredns.sysext/test.sh coredns.raw
```

It asserts the binary is present and executable, that `coredns -version` runs when the image architecture matches the host, and that the image contains no path outside `/usr`.
