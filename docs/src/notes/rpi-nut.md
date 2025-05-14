# NUT

## Hardware notes
Raspberry Pi 5 w/ 8GM RAM
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

Change the permissions back
```sh
sudo chmod 755 -R /etc/nut
sudo chmod 640 /etc/nut/*
```

Restart the NUT service
```sh
sudo systemctl restart nut-server
sudo systemctl restart nut-monitor
```

You should now have a working PiNUT config that will also shutdown talos/the NAS when on battery power.
