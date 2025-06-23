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

# 4. Update system and install DNF packages
echo "[4/14] Installing core packages via DNF..."
sudo dnf upgrade -y
sudo dnf install -y \
    dnf-plugins-core \
    hyprland \
    waybar cava rofi mpv \
    thunar thunar-archive-plugin polkit-gnome \
    sddm swayidle swaylock dmenu \
    git cargo pkgconfig wayland-devel liblz4-devel \
    gtk3 gtk2 libnotify gsettings-desktop-schemas \
    fontconfig && \
# 5. Install Google Noto fonts
sudo dnf install -y \
    google-noto-sans-fonts \
    google-noto-emoji-fonts \
    google-noto-cjk-fonts \
    google-noto-fonts-all.noarch \
    google-noto-fonts-all-static.noarch \
    google-noto-fonts-all-vf.noarch \
    google-noto-fonts-common.noarch

# 6. Enable and start SDDM Enable and start SDDM Enable and start SDDM
echo "[5/14] Enabling SDDM display manager..."
sudo systemctl enable sddm --now

# 6. Install swww wallpaper daemon
echo "[6/14] Installing swww from source..."
if ! command -v swww &>/dev/null; then
  git clone https://github.com/LGFae/swww.git /tmp/swww && \
  cd /tmp/swww && cargo build --release && \
  sudo install -Dm755 target/release/swww /usr/local/bin/swww && \
  sudo install -Dm755 target/release/swww-daemon /usr/local/bin/swww-daemon
fi

# 7. Install Hyprpaper wallpaper tool
echo "[7/14] Installing Hyprpaper..."
if ! command -v hyprpaper &>/dev/null; then
  git clone https://github.com/hyprwm/Hyprpaper.git /tmp/hyprpaper && \
  cd /tmp/hyprpaper && cargo build --release && \
  sudo install -Dm755 target/release/hyprpaper /usr/local/bin/hyprpaper
fi

# 8. Install mpvpaper seque wallpaper
echo "[8/14] Installing Mpvpaper..."
if ! command -v mpvpaper &>/dev/null; then
  git clone https://github.com/LGFae/mpvpaper.git /tmp/mpvpaper && \
  cd /tmp/mpvpaper && cargo build --release && \
  sudo install -Dm755 target/release/mpvpaper /usr/local/bin/mpvpaper
fi

# 9. Install SwayNC notification daemon
echo "[9/14] Installing SwayNC..."
if ! command -v swync &>/dev/null; then
  git clone https://github.com/Twnmt/SwayNC.git /tmp/swaync && \
  cd /tmp/swaync && cargo build --release && \
  sudo install -Dm755 target/release/swaync /usr/local/bin/swaync
fi

# 10. Nerd Fonts via COPR
echo "[10/14] Installing Nerd Fonts..."
if ! sudo dnf copr list | grep -q rmihaylov/nerd-fonts; then
  sudo dnf copr enable -y rmihaylov/nerd-fonts || \
    echo "⚠️ COPR repository failed to enable. Installing fonts manually..."
fi
if [[ $(sudo dnf repoquery --repoid="rmihaylov-nerd-fonts" --quiet) ]]; then
  sudo dnf install -y nerd-fonts-complete
else
  # Fallback: download from GitHub and install
  echo "Downloading Nerd Fonts zip from GitHub releases..."
  mkdir -p "$HOME/.local/share/fonts"
  curl -sL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/NerdFonts.zip" -o /tmp/NerdFonts.zip && \
  unzip -qq /tmp/NerdFonts.zip -d "$HOME/.local/share/fonts" && \
  fc-cache -fv
fi

# 11. Icon & GTK themes
echo "[11/14] Installing Tela Circle Dracula and Catppuccin themes..."
# Tela Circle Dracula
git clone https://github.com/vinceliuice/Tela-circle-icon-theme.git /tmp/tela && \
cd /tmp/tela && ./install.sh -a
# Catppuccin GTK
git clone https://github.com/catppuccin/gtk.git /tmp/catppuccin && \
cd /tmp/catppuccin && ./install.sh mocha
# Apply themes
gsettings set org.gnome.desktop.interface icon-theme "Tela-circle-dracula"
gsettings set org.gnome.desktop.interface gtk-theme "Catppuccin-Mocha"

# 12. Remove other file managers & set Thunar default
echo "[12/14] Configuring Thunar as default file manager..."
sudo dnf remove -y dolphin nautilus nemo pantheon-files || true
xdg-mime default org.thunar.desktop inode/directory application/octet-stream

# 13. Cleanup
echo "[13/14] Cleaning up temporary build folders..."
sudo rm -rf /tmp/swww /tmp/hyprpaper /tmp/mpvpaper /tmp/swaync /tmp/tela /tmp/catppuccin

# 14. Final message
echo -e "\n✅ HyprQuiet installed successfully!\nRestart or reload your Hyprland session to apply changes."
