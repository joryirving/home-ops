# NUT

## Hardware notes

Raspberry Pi 5 w/ 8GB RAM
PoE Hat
NVMe Hat

## Setup Raspberry Pi

Assuming you have already installed Raspbian (or other), ssh into the Pi, update it, and install nut.

```sh
sudo apt update; sudo apt upgrade -y; sudo apt full-upgrade -y; sudo apt autoclean; sudo apt autoremove -y; sudo apt install nut -y
```

Then set the file permissions so they can be overwritten.

```sh
sudo chmod 777 -R /etc/nut
```

Then, copy the proper config to the Raspberry Pi locally

```sh
scp -r ./docs/src/assets/utility-nut/* vetrius@sayu:/etc/nut/
```

or

```sh
scp -r ./docs/src/assets/server-nut/* vetrius@venti:/etc/nut/
```

Replace `<password>` in `upsd.users` and `upsmon.conf` with the same real
password (keep it out of Git).

Change the permissions back

```sh
sudo chmod 755 -R /etc/nut
sudo chmod 640 /etc/nut/*
sudo chmod 750 /etc/nut/ups_shutdown.sh # venti only
```

Restart the NUT service

```sh
sudo systemctl restart nut-server
sudo systemctl restart nut-monitor
```

On low battery, venti runs `ups_shutdown.sh`, which shuts down the main cluster
and voyager, then the Pi. Sayu shuts down the utility cluster. upsmon runs
`SHUTDOWNCMD` as root, so each Pi needs `talosctl` and a talosconfig with the
`main`/`utility` context for root; venti also needs root SSH access to
`root@voyager`.

## Rebuilding NUT from source

The Debian package on Raspberry Pi OS is too old for EcoFlow CDC support, so
Venti runs a source build. The current build only includes `usbhid-ups`, which
both UPSes use; EcoFlow is not configured yet. Sayu is temporarily running the
already-built binaries copied from Venti; rebuild both Pis from the same pinned NUT source revision before
that install needs maintenance.

The current Venti build identifies as NUT `2.8.5.1168` from source commit
`2caa3c875`; treat that as the baseline for the next rebuild.

### Rebuild checklist

1. Record the NUT source tag or commit used on Venti. Do not build from an
   unpinned checkout.
2. Back up `/etc/nut`, the installed NUT binaries, the systemd driver unit,
   and `/usr/lib/tmpfiles.d/nut-common-tmpfiles.conf`.
3. Stop `nut-monitor`, `nut-server`, and the relevant `nut-driver@*.service`.
4. Build on the Pi (aarch64):

   ```sh
   ./configure \
       --prefix=/usr \
       --sysconfdir=/etc/nut \
       --with-systemdsystemunitdir=/etc/systemd/system \
       --with-udev-dir=/etc/udev \
       --with-openssl \
       --with-usb \
       --with-serial \
       --with-user=nut \
       --with-group=nut \
       --sbindir=/usr/sbin \
       --bindir=/usr/bin \
       --with-drvpath=/usr/bin \
       --datadir=/usr/share/nut \
       --libdir=/lib \
       --with-libsystemd \
       --disable-inplace-runtime \
       --with-drivers=usbhid-ups
   make -j"$(nproc)"
   sudo make install
   ```

5. Recreate `/var/state/ups`, reload systemd, and start the services.
6. Verify the driver, server, and monitor versions, then check `upsc` output,
   service health, and the journal before changing the UPS configuration.
7. Keep the old binaries and configuration until the new install has survived
   a full restart. If it fails, stop the services, restore the backup, reload
   systemd, and start the packaged install.

Do not preconfigure the future EcoFlow UPS. Once the River 3 Plus is connected,
discover its USB identity and CDC serial path first, then add its driver to the
build and update together: `ups.conf`, the `MONITOR` line in `upsmon.conf`, and
the `server`/`ups` params in
`kubernetes/apps/base/observability/exporters/nut-exporter/servicemonitor.yaml`.

## Docker Compose for node_exporter/smartctl_exporter

```yaml
services:
    node_exporter:
        image: quay.io/prometheus/node-exporter:latest
        container_name: node_exporter
        command:
            - "--path.rootfs=/host"
        network_mode: host
        pid: host
        restart: unless-stopped
        volumes:
            - "/:/host:ro,rslave"
    smartctl-exporter:
        image: ghcr.io/joryirving/smartctl_exporter:rolling
        container_name: smartctl-exporter
        ports:
            - "9633:9633"
        privileged: true
        restart: unless-stopped
```
