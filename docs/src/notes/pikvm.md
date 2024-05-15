# PiKVM

## Load TESmart KVM

1. Add or replace the file `/etc/kvmd/override.yaml`

    ```yaml
    ---

    nginx:
      https:
        enabled: false

    kvmd:
      auth:
        enabled: false
      prometheus:
        auth:
          enabled: false
      atx:
        type: disabled
      streamer:
        desired_fps:
          default: 20
        h264_bitrate:
          default: 2500
        h264_gop:
          default: 30
        quality: 75
      gpio:
        drivers:
          tes:
            type: tesmart
            host: 192.168.1.10
            port: 5000
          wol_server0:
            type: wol
            mac: 00:e0:4c:68:06:69
          wol_server1:
            type: wol
            mac: 1c:fd:08:75:15:63
          wol_server2:
            type: wol
            mac: 1c:fd:08:75:15:6f
          wol_server3:
            type: wol
            mac: 00:e0:4c:68:06:dd
          wol_server4:
            type: wol
            mac: 00:e0:4c:68:05:e6
          wol_server5:
            type: wol
            mac: 00:e0:4c:68:06:3a
          wol_server6:
            type: wol
            mac: 2c:cf:67:09:03:1f
          reboot:
            type: cmd
            cmd: ["/usr/bin/sudo", "reboot"]
          restart_service:
            type: cmd
            cmd: ["/usr/bin/sudo", "systemctl", "restart", "kvmd"]
        scheme:
          server0_led:
            driver: tes
            pin: 0
            mode: input
          server0_btn:
            driver: tes
            pin: 0
            mode: output
            switch: false
          server0_wol:
            driver: wol_server0
            pin: 0
            mode: output
            switch: false
          server1_led:
            driver: tes
            pin: 1
            mode: input
          server1_btn:
            driver: tes
            pin: 1
            mode: output
            switch: false
          server1_wol:
            driver: wol_server1
            pin: 0
            mode: output
            switch: false
          server2_led:
            driver: tes
            pin: 2
            mode: input
          server2_btn:
            driver: tes
            pin: 2
            mode: output
            switch: false
          server2_wol:
            driver: wol_server2
            pin: 0
            mode: output
            switch: false
          server3_led:
            driver: tes
            pin: 3
            mode: input
          server3_btn:
            driver: tes
            pin: 3
            mode: output
            switch: false
          server3_wol:
            driver: wol_server3
            pin: 0
            mode: output
            switch: false
          server4_led:
            driver: tes
            pin: 4
            mode: input
          server4_btn:
            driver: tes
            pin: 4
            mode: output
            switch: false
          server4_wol:
            driver: wol_server4
            pin: 0
            mode: output
            switch: false
          server5_led:
            driver: tes
            pin: 5
            mode: input
          server5_btn:
            driver: tes
            pin: 5
            mode: output
            switch: false
          server5_wol:
            driver: wol_server5
            pin: 0
            mode: output
            switch: false
          server6_led:
            driver: tes
            pin: 6
            mode: input
          server6_btn:
            driver: tes
            pin: 6
            mode: output
            switch: false
          server6_wol:
            driver: wol_server6
            pin: 0
            mode: output
            switch: false
          server7_led:
            driver: tes
            pin: 7
            mode: input
          server7_btn:
            driver: tes
            pin: 7
            mode: output
            switch: false
          reboot_button:
            driver: reboot
            pin: 0
            mode: output
            switch: false
          restart_service_button:
            driver: restart_service
            pin: 0
            mode: output
            switch: false
        view:
          header:
            title: Devices
          table:
            - ["#pikvm", "pikvm_led|green", "restart_service_button|confirm|Service", "reboot_button|confirm|Reboot"]
            - ["#0", "server0_led", "server0_btn | KVM", "server0_wol | WOL"]
            - ["#1", "server1_led", "server1_btn | KVM", "server1_wol | WOL"]
            - ["#2", "server2_led", "server2_btn | KVM", "server2_wol | WOL"]
            - ["#3", "server3_led", "server3_btn | KVM", "server3_wol | WOL"]
            - ["#4", "server4_led", "server4_btn | KVM", "server4_wol | WOL"]
            - ["#5", "server5_led", "server5_btn | KVM", "server5_wol | WOL"]
            - ["#6", "server6_led", "server6_btn | KVM", "server6_wol | WOL"]
            - ["#7", "server7_led", "server7_btn | KVM"]
    ```

2. Restart kvmd

    ```sh
    systemctl restart kvmd.service
    ```

## Monitoring

### Install node-exporter

```sh
pikvm-update
pacman -S prometheus-node-exporter
systemctl enable --now prometheus-node-exporter
```
