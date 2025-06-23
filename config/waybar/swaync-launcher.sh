#!/bin/bash
# Wrapper script to start swaync with the correct D-Bus environment.
# This ensures that GUI applications started by systemd can connect to the display server.

# Kill any existing swaync processes to ensure a clean start
killall swaync &> /dev/null

# Wait a moment for the process to die
sleep 0.1

# FIX: Set the correct desktop environment to Hyprland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland

# Execute swaync
exec /usr/bin/swaync
