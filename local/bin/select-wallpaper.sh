#!/bin/bash

# This script provides a stable, performant, and feature-rich wallpaper
# selector using Rofi. It now saves the last selected wallpaper to make it
# persistent across reboots.

# --- USER CONFIGURATION ---
WALLPAPER_DIR="$HOME/Pictures/wallpapers"
MONITOR="HDMI-A-1"
ROFI_THEME_FILE="$HOME/.config/rofi/wallpaper.rasi"
HYPRPAPER_CONF="$HOME/.config/hypr/hyprpaper.conf"
HYPRWALL_CONF="$HOME/.config/hyprwall/config"

# --- CACHE CONFIGURATION ---
CACHE_DIR="$HOME/.cache/wallpaper_selector"
GIF_PREVIEW_DIR="$CACHE_DIR/gif_previews"
mkdir -p "$GIF_PREVIEW_DIR"

# --- SCRIPT CHECKS ---
for cmd in rofi magick; do
    if ! command -v "$cmd" &> /dev/null; then
        notify-send "Error: Dependency Missing" "Command '$cmd' not found. Please install it." >&2
        if [ "$cmd" == "rofi" ]; then exit 1; fi
    fi
done

# --- FUNCTION DEFINITIONS ---
generate_menu() {
    find "$WALLPAPER_DIR" -type f \( -iname \*.jpg -o -iname \*.jpeg -o -iname \*.png -o -iname \*.gif \) | sort | while read -r F_PATH; do
        F_NAME=$(basename "$F_PATH")
        PREVIEW_PATH="$F_PATH"

        if [[ "$F_NAME" == *.gif ]] && command -v magick &> /dev/null; then
            PREVIEW_PATH="$GIF_PREVIEW_DIR/$F_NAME.png"
            [ -f "$PREVIEW_PATH" ] || magick "$F_PATH[0]" -resize 256x256 "$PREVIEW_PATH" &> /dev/null
        fi
        
        echo -en "$F_PATH\0icon\x1f$PREVIEW_PATH\n"
    done
}

# --- MAIN SCRIPT ---
if pidof rofi >/dev/null; then
    pkill rofi
    exit 0
fi

rm -f ~/.cache/rofi*.cache

SELECTED_WALLPAPER_PATH=$(generate_menu | rofi -dmenu -i -p "Select Wallpaper" -theme "$ROFI_THEME_FILE" -show-icons)

if [ -n "$SELECTED_WALLPAPER_PATH" ]; then
    if [ -f "$SELECTED_WALLPAPER_PATH" ]; then
        # Ensure hyprpaper is running
        pkill hyprpaper
        sleep 0.1
        hyprpaper &
        sleep 0.5

        # Set the new wallpaper
        hyprctl hyprpaper preload "$SELECTED_WALLPAPER_PATH"
        hyprctl hyprpaper wallpaper "$MONITOR,$SELECTED_WALLPAPER_PATH"
        
        # --- SAVE THE SELECTION (THE FIX) ---
        # Overwrite hyprpaper.conf with the new wallpaper
        echo "preload = $SELECTED_WALLPAPER_PATH" > "$HYPRPAPER_CONF"
        echo "wallpaper = $MONITOR,$SELECTED_WALLPAPER_PATH" >> "$HYPRPAPER_CONF"
        echo "ipc = on" >> "$HYPRPAPER_CONF"

        # Update the last_wallpaper line in hyprwall config
        # The weird separator | in sed is used because the path contains /
        sed -i "s|last_wallpaper = .*|last_wallpaper = $SELECTED_WALLPAPER_PATH|" "$HYPRWALL_CONF"

        notify-send "Wallpaper Set" "$(basename "$SELECTED_WALLPAPER_PATH")"
    else
        notify-send "Error" "Could not find or set the selected wallpaper."
    fi
fi
