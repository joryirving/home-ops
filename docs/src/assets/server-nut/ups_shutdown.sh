#!/bin/bash

# Issue local Talos shutdown command
talosctl shutdown --context main

# Wait a few seconds to allow local shutdown to initiate (optional but recommended)
sleep 5

# Remotely shutdown the Linux server
ssh root@voyager "sudo shutdown -h now"

exit 0