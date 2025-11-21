# OpenSurv Raspberry Pi Setup Guide

This guide walks through installing OpenSurv on a Raspberry Pi from a fresh SD card using Raspberry Pi OS (Raspbian).
It includes flashing the OS, updating the system, installing OpenSurv, and configuring a single RTSP camera.

## 📦 Requirements

Raspberry Pi 4/5 (recommended)

- SD card (16GB+)
- A monitor connected to the Pi
- Network connection (wired recommended)
- An RTSP-capable camera

### 📝 1. Flash Raspberry Pi OS

- Download Raspberry Pi Imager
- Select Raspberry Pi OS (64-bit)
- Flash it onto the SD card
- Insert SD card into the Pi and boot up

### 🔧 2. Update the System

After first boot, open a terminal and run:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y
sudo apt autoclean
```

### ⬇️ 3. Clone the OpenSurv Repository
```bash
git clone https://github.com/OpenSurv/OpenSurv.git
cd OpenSurv
```

### ⚙️ 4. Install OpenSurv

Run the installer:
```bash
sudo ./install.sh
```

This will:

- Install dependencies
- Create the opensurv system user
- Create /home/opensurv/etc/ configuration directory
- Enable autostart services

### 📝 5. Configure OpenSurv (Single Camera)

Edit the main monitor configuration:
```bash
sudo nano /home/opensurv/etc/monitor1.yml
```

Replace the contents with:

```yaml
essentials:
  screens:
    - streams:
        - url: "rtsp://<IP>>:8553/rtsp-high"
```

This will show the single camera full-screen.

Check the service status:
```bash
systemctl status systemctl restart lightdm.service
```

###🔁 6. Reboot to Confirm
```bash
sudo reboot
```
OpenSurv should auto-start and display the RTSP stream from your camera.

🎉 Done!

Your Raspberry Pi is now configured as a dedicated OpenSurv RTSP viewer that automatically starts on boot.

## How to update OpenSurv to new version <a name="how-to-update"></a>
- `cd OpenSurv; git pull`
- OPTIONAL: checkout a specific branch, for example `git checkout v1_latest`, if you want to override the default version
- Run `sudo ./install.sh` (The installer will ask if you want to preserve your current config file)
- `systemctl restart lightdm.service`

## Troubleshooting <a name = "troubleshooting"></a>

- If you used the install.sh script, logs are created at /home/opensurv/logs/. You can use them for troubleshooting. Enable DEBUG logging for very detailed output of what is going on. Switch INFO to DEBUG in /etc/opensurv/logging.yml and restart opensurv.

- If you are connected via keyboard/keypad, you can stop OpenSurv by pressing and holding q (or backspace or keypad "/") (this can take some seconds).

- To manage the screen without rebooting, use systemctl:
  - `sudo systemctl stop lightdm.service` to stop the screen.
  - `sudo systemctl start lightdm.service` to start the screen.
  - `tail -F /home/opensurv/logs/main.log` to see last logs.

- If you want to stream RTSP over TCP, please add `freeform_advanced_mpv_options: "--rtsp-transport=tcp"` to the stream configured in the config files in /etc/opensurv.
  See in /etc/opensurv for examples.
  If you have a "smearing" effect, this option may resolve it. 

- Significantly reduce latency on a stream by adding `freeform_advanced_mpv_options:"--profile=low-latency --untimed"` to the stream configured in the config files in /etc/opensurv.
