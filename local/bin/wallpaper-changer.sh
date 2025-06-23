#!/bin/bash

# This script selects a random wallpaper from a specified directory
# and applies it using hyprpaper.

# The directory where your wallpapers are stored.
WALLPAPER_DIR="/home/ackerman/Pictures/wallpapers"

# Check if the directory exists
if [ ! -d "$WALLPAPER_DIR" ]; then
  echo "Error: Wallpaper directory not found at $WALLPAPER_DIR"
  exit 1
fi

# Find all image files in the directory (jpg, jpeg, png)
# and select one at random.
RANDOM_WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname \*.jpg -o -iname \*.jpeg -o -iname \*.png \) | shuf -n 1)

# Check if a wallpaper was found
if [ -z "$RANDOM_WALLPAPER" ]; then
  echo "Error: No wallpapers found in $WALLPAPER_DIR"
  exit 1
fi

# Use hyprctl to set the new wallpaper.
# This command will preload the wallpaper and then set it on all monitors.
# Replace 'eDP-1' with your actual monitor identifier if it's different.
# You can find your monitor identifier by running `hyprctl monitors`.
hyprctl hyprpaper preload "$RANDOM_WALLPAPER"
hyprctl hyprpaper wallpaper "HDMI-A-1,$RANDOM_WALLPAPER"

# Optional: Send a notification that the wallpaper has changed.
notify-send "Wallpaper Changed" "Now displaying: ${RANDOM_WALLPAPER##*/}"
