#!/bin/bash

# Shut down the main cluster (skirk, ayaka, eula, ganyu)
talosctl shutdown --context main --nodes 10.69.1.24,10.69.1.21,10.69.1.22,10.69.1.23

# Wait a few seconds to allow the Talos shutdown to initiate
sleep 5

# Remotely shut down the NAS
ssh root@voyager "sudo shutdown -h now"

# Shut down this Pi
/sbin/shutdown -h +0

exit 0
