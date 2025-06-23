#!/usr/bin/env bash
# install.sh — Automated HyprQuiet installer for Fedora 42
set -euo pipefail

# Timestamp for backups
TS=$(date +"%Y%m%d-%H%M%S")

# 1. Backup existing Hyprland configs
echo "[1/14] Backing up existing Hyprland configs..."
if [ -d "$HOME/.config/hypr" ]; then
    mkdir -p "$HOME/.config/hypr/backup-$TS"
    mv "$HOME/.config/hypr/"* "$HOME/.config/hypr/backup-$TS/" || true
fi

# 2. Deploy new HyprQuiet configs
echo "[2/14] Deploying HyprQuiet configs..."
mkdir -p "$HOME/.config/hypr"
cp -r "$PWD/config/"* "$HOME/.config/hypr/"

# 3. Deploy local scripts
echo "[3/14] Installing local scripts..."
mkdir -p "$HOME/.local/bin"
cp -r "$PWD/local/bin/"* "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/"*

# 4. System update and package installation
echo "[4/14] Updating system and installing core packages..."
sudo dnf upgrade -y
# Corrected package: 'lz4-devel' is the equivalent on Fedora for 'liblz4-devel'
# Switched 'polkit-gnome' to 'mate-polkit' as requested.
sudo dnf install -y \
    dnf-plugins-core \
    hyprland \
    waybar cava rofi mpv \
    thunar thunar-archive-plugin mate-polkit \
    sddm swayidle swaylock dmenu \
    git cargo pkgconfig wayland-devel lz4-devel \
    gtk3 gtk2 libnotify gsettings-desktop-schemas \
    fontconfig

# 5. Install Google Noto fonts
echo "[5/14] Installing Google Noto fonts..."
sudo dnf install -y \
    google-noto-sans-fonts \
    google-noto-emoji-fonts \
    google-noto-cjk-fonts \
    google-noto-fonts-all.noarch \
    google-noto-fonts-all-static.noarch \
    google-noto-fonts-all-vf.noarch \
    google-noto-fonts-common.noarch

# 6. Enable and start SDDM
echo "[6/14] Enabling and starting SDDM display manager..."
sudo dnf install sddm # This might be redundant if already installed in step 4, but ensures it's there.
sudo systemctl daemon-reload
sudo systemctl enable --now sddm

# 7. Install swww wallpaper daemon
echo "[7/14] Installing swww from source..."
if ! command -v swww &>/dev/null; then
    git clone https://github.com/LGFae/swww.git /tmp/swww
    cd /tmp/swww
    cargo build --release
    sudo install -Dm755 target/release/swww /usr/local/bin/swww
    sudo install -Dm755 target/release/swww-daemon /usr/local/bin/swww-daemon
    cd - # Return to previous directory
fi

# 8. Install Hyprpaper
echo "[8/14] Installing Hyprpaper wallpaper tool..."
if ! command -v hyprpaper &>/dev/null; then
    git clone https://github.com/hyprwm/Hyprpaper.git /tmp/hyprpaper
    cd /tmp/hyprpaper
    cargo build --release
    sudo install -Dm755 target/release/hyprpaper /usr/local/bin/hyprpaper
    cd - # Return to previous directory
fi

# 9. Install Mpvpaper
echo "[9/14] Installing mpvpaper wallpaper sequencer..."
if ! command -v mpvpaper &>/dev/null; then
    git clone https://github.com/LGFae/mpvpaper.git /tmp/mpvpaper
    cd /tmp/mpvpaper
    cargo build --release
    sudo install -Dm755 target/release/mpvpaper /usr/local/bin/mpvpaper
    cd - # Return to previous directory
fi

# 10. Install SwayNC
echo "[10/14] Installing SwayNC notification daemon..."
if ! command -v swync &>/dev/null; then
    git clone https://github.com/Twnmt/SwayNC.git /tmp/swaync
    cd /tmp/swaync
    cargo build --release
    sudo install -Dm755 target/release/swaync /usr/local/bin/swaync
    cd - # Return to previous directory
fi

# 11. Install Nerd Fonts fallback (This section might be problematic due to COPR availability or package names)
echo "[11/14] Installing Nerd Fonts..."
# The COPR rmihaylov/nerd-fonts might not always be available or stable.
# It's generally safer to install specific Nerd Fonts manually or from reliable repos.
# Keeping it as per your provided script, but with a warning.
if ! sudo dnf copr enable -y rmihaylov/nerd-fonts; then
    echo "⚠️ COPR enable failed for rmihaylov/nerd-fonts, skipping Nerd Fonts installation from this COPR."
else
    sudo dnf install -y nerd-fonts-complete || echo "⚠️ nerd-fonts-complete install failed. You may need to install fonts manually."
fi
# As a fallback or alternative, installing FiraCode Nerd Font directly (as in previous version)
# You can uncomment the following lines if the COPR method fails frequently:
# FONT_DIR="$HOME/.local/share/fonts"
# mkdir -p "$FONT_DIR"
# FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/FiraCode.zip"
# FONT_ZIP="/tmp/FiraCode.zip"
# wget -q --show-progress "$FONT_URL" -O "$FONT_ZIP" && \
# unzip -o "$FONT_ZIP" -d "$FONT_DIR" && \
# fc-cache -fv || echo "Warning: FiraCode Nerd Font installation failed."


# 12. Icon & GTK themes
echo "[12/14] Installing Tela Circle Dracula and Catppuccin themes..."
# Ensure the temporary directories for themes are unique or cleaned up properly
if [ -d "/tmp/tela" ]; then rm -rf /tmp/tela; fi
git clone https://github.com/vinceliuice/Tela-circle-icon-theme.git /tmp/tela
cd /tmp/tela && ./install.sh -a
cd - # Return to previous directory

if [ -d "/tmp/catppuccin" ]; then rm -rf /tmp/catppuccin; fi
git clone https://github.com/catppuccin/gtk.git /tmp/catppuccin
cd /tmp/catppuccin && ./install.sh mocha
cd - # Return to previous directory

# Apply themes
gsettings set org.gnome.desktop.interface icon-theme "Tela-circle-dracula"
gsettings set org.gnome.desktop.interface gtk-theme "Catppuccin-Mocha"

# 13. File manager cleanup and default
echo "[13/14] Removing other file managers and setting Thunar as default..."
sudo dnf remove -y dolphin nautilus nemo pantheon-files || true
xdg-mime default Thunar.desktop inode/directory application/x-zerosize

# 14. Cleanup temporary folders
echo "[14/14] Cleaning up temporary build directories..."
sudo rm -rf /tmp/swww /tmp/hyprpaper /tmp/mpvpaper /tmp/swaync /tmp/tela /tmp/catppuccin

echo -e "\n✅ HyprQuiet installed successfully!\nRestart or reload your Hyprland session to apply changes."
