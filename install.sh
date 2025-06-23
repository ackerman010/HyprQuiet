#!/usr/bin/env bash
# install.sh — Automated HyprQuiet installer for Fedora 42
set -euo pipefail

# Timestamp for backups
TS=$(date +"%Y%m%d-%H%M%S")

# --- Helper Functions ---
# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to clean up a temporary directory
cleanup_temp_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        echo "Cleaning up temporary directory: $dir"
        sudo rm -rf "$dir"
    fi
}

# Function to build and install Rust projects from source
build_and_install_rust_project() {
    local repo_url="$1"
    local temp_path="$2"
    local bin_name="$3"
    local custom_cd_path="$4" # Optional: subdirectory to cd into for cargo build

    echo "Building and installing $bin_name from source..."
    cleanup_temp_dir "$temp_path" # Ensure clean slate before cloning

    git clone "$repo_url" "$temp_path"
    if [ ! -d "$temp_path" ]; then
        echo "Error: Failed to clone $bin_name repository from $repo_url."
        exit 1
    fi

    local current_dir="$PWD"
    cd "$temp_path"

    if [ -n "$custom_cd_path" ]; then
        if [ -d "$custom_cd_path" ]; then
            echo "Changing to subdirectory: $custom_cd_path"
            cd "$custom_cd_path"
        else
            echo "Warning: Custom subdirectory '$custom_cd_path' not found in $temp_path. Attempting build from $temp_path."
            # If custom_cd_path is not found, we fallback to the cloned root.
            # This might still lead to Cargo.toml not found if it's deeply nested.
        fi
    fi

    # Check for Cargo.toml after changing directory
    if [ ! -f "Cargo.toml" ]; then
        echo "Error: Cargo.toml not found in $(pwd). Cannot build $bin_name. Please check the repository structure or specify custom_cd_path correctly."
        cd "$current_dir" > /dev/null # Return to original directory before exiting
        exit 1
    fi

    cargo build --release
    sudo install -Dm755 "target/release/$bin_name" "/usr/local/bin/$bin_name"

    # Handle additional binaries if they exist, like swww-daemon
    if [ "$bin_name" == "swww" ] && [ -f "target/release/swww-daemon" ]; then
        sudo install -Dm755 "target/release/swww-daemon" "/usr/local/bin/swww-daemon"
    fi

    cd "$current_dir" > /dev/null # Return to original directory
    echo "$bin_name installed from source."
}


# --- Main Script Execution ---

# 1. Backup existing Hyprland configs
echo "[1/14] Backing up existing Hyprland configs..."
if [ -d "$HOME/.config/hypr" ]; then
    mkdir -p "$HOME/.config/hypr/backup-$TS"
    mv "$HOME/.config/hypr/"* "$HOME/.config/hypr/backup-$TS/" || true
    echo "Existing ~/.config/hypr backed up to ~/.config/hypr/backup-$TS/"
else
    echo "No existing ~/.config/hypr found, skipping backup."
fi

# 2. Deploy new HyprQuiet configs
echo "[2/14] Deploying HyprQuiet configs..."
mkdir -p "$HOME/.config/hypr"
cp -r "$PWD/config/"* "$HOME/.config/hypr/"
echo "HyprQuiet configs deployed to ~/.config/hypr/"

# 3. Deploy local scripts
echo "[3/14] Installing local scripts..."
mkdir -p "$HOME/.local/bin"
cp -r "$PWD/local/bin/"* "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/"*
echo "Local scripts deployed and made executable in ~/.local/bin/"

# 4. System update and package installation
echo "[4/14] Updating system and installing core packages..."
sudo dnf upgrade -y
# Essential build tools and libraries first
sudo dnf install -y \
    git cargo pkgconfig \
    gcc-c++ \
    wayland-devel lz4-devel wayland-protocols-devel \
    gtk3 gtk2 libnotify gsettings-desktop-schemas \
    fontconfig \
    dnf-plugins-core \
    hyprland \
    waybar cava rofi mpv \
    thunar thunar-archive-plugin mate-polkit \
    sddm swayidle swaylock dmenu
echo "Core packages and development tools installed."

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
echo "Google Noto fonts installed."

# 6. Enable and start SDDM
echo "[6/14] Enabling and starting SDDM display manager..."
# Ensure sddm is installed. It's listed in step 4, but this is a safeguard.
if ! command_exists sddm; then
    sudo dnf install -y sddm
fi
sudo systemctl daemon-reload
sudo systemctl enable --now sddm
echo "SDDM enabled and started."

# 7. Install swww wallpaper daemon
echo "[7/14] Installing swww from source..."
if ! command_exists swww; then
    # Based on LGFae/swww repo structure, Cargo.toml is in the root.
    build_and_install_rust_project "https://github.com/LGFae/swww.git" "/tmp/swww" "swww" ""
else
    echo "swww already installed, skipping source build."
fi

# 8. Install Hyprpaper
echo "[8/14] Installing Hyprpaper wallpaper tool..."
if ! command_exists hyprpaper; then
    echo "Attempting to install hyprpaper via DNF first..."
    if sudo dnf install -y hyprpaper; then
        echo "Hyprpaper installed successfully via DNF."
    else
        echo "Hyprpaper not found in DNF, attempting to build from source..."
        # This is the crucial fix: specifying the subdirectory 'hyprpaper' within the cloned repo.
        build_and_install_rust_project "https://github.com/hyprwm/Hyprpaper.git" "/tmp/hyprpaper_repo" "hyprpaper" "hyprpaper"
    fi
else
    echo "Hyprpaper already installed, skipping installation."
fi

# 9. Install Mpvpaper
echo "[9/14] Installing mpvpaper wallpaper sequencer..."
if ! command_exists mpvpaper; then
    # Based on LGFae/mpvpaper repo structure, Cargo.toml is in the root.
    build_and_install_rust_project "https://github.com/LGFae/mpvpaper.git" "/tmp/mpvpaper" "mpvpaper" ""
else
    echo "mpvpaper already installed, skipping source build."
fi

# 10. Install SwayNC
echo "[10/14] Installing SwayNC notification daemon..."
if ! command_exists swync; then
    # Based on Twnmt/SwayNC repo structure, Cargo.toml is in the root.
    build_and_install_rust_project "https://github.com/Twnmt/SwayNC.git" "/tmp/swaync" "swaync" ""
else
    echo "SwayNC already installed, skipping source build."
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
# This is a more reliable method if the COPR fails. Uncomment to use.
# FONT_DIR="$HOME/.local/share/fonts"
# mkdir -p "$FONT_DIR"
# FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/FiraCode.zip"
# FONT_ZIP="/tmp/FiraCode.zip"
# echo "Downloading FiraCode Nerd Font..."
# wget -q --show-progress "$FONT_URL" -O "$FONT_ZIP" && \
# echo "Unzipping FiraCode Nerd Font..." && \
# unzip -o "$FONT_ZIP" -d "$FONT_DIR" && \
# echo "Updating font cache..." && \
# fc-cache -fv || echo "Warning: FiraCode Nerd Font installation failed."


# 12. Icon & GTK themes
echo "[12/14] Installing Tela Circle Dracula and Catppuccin themes..."
cleanup_temp_dir "/tmp/tela" # Ensure clean slate before cloning
git clone https://github.com/vinceliuice/Tela-circle-icon-theme.git /tmp/tela
if [ ! -d "/tmp/tela" ]; then
    echo "Error: Failed to clone Tela Circle Icon Theme repository."
    exit 1
fi
cd /tmp/tela && ./install.sh -a
cd - > /dev/null # Return to previous directory silently
echo "Tela Circle Dracula Icons installed."

cleanup_temp_dir "/tmp/catppuccin" # Ensure clean slate before cloning
git clone https://github.com/catppuccin/gtk.git /tmp/catppuccin
if [ ! -d "/tmp/catppuccin" ]; then
    echo "Error: Failed to clone Catppuccin GTK Theme repository."
    exit 1
fi
cd /tmp/catppuccin && ./install.sh mocha
cd - > /dev/null # Return to previous directory silently
echo "Catppuccin GTK theme installed."

# Apply themes
echo "Applying themes..."
gsettings set org.gnome.desktop.interface icon-theme "Tela-circle-dracula"
gsettings set org.gnome.desktop.interface gtk-theme "Catppuccin-Mocha"
echo "Themes applied."

# 13. File manager cleanup and default
echo "[13/14] Removing other file managers and setting Thunar as default..."
sudo dnf remove -y dolphin nautilus nemo pantheon-files || true
xdg-mime default Thunar.desktop inode/directory application/x-zerosize
echo "Thunar set as default file manager."

# 14. Cleanup temporary folders
echo "[14/14] Cleaning up temporary build directories..."
# Consolidated cleanup for all temporary directories used during source builds and theme installations
cleanup_temp_dir "/tmp/swww"
cleanup_temp_dir "/tmp/hyprpaper_repo" # Changed name to match clone path
cleanup_temp_dir "/tmp/mpvpaper"
cleanup_temp_dir "/tmp/swaync"
cleanup_temp_dir "/tmp/tela"
cleanup_temp_dir "/tmp/catppuccin"
echo "Temporary directories cleaned up."

echo -e "\n✅ HyprQuiet installed successfully!\nRestart or reload your Hyprland session to apply changes."
echo "------------------------------------------------------------"
echo "IMPORTANT NEXT STEPS:"
echo "1. Reboot your system: 'sudo reboot'"
echo "2. After reboot, select 'Hyprland' session from SDDM."
echo "3. Review your ~/.config/hypr/hyprland.conf and related files to ensure everything is sourced correctly."
echo "4. You might need to adjust GTK theme variants via 'gsettings set org.gnome.desktop.interface gtk-theme <variant>' or a GUI tool if you prefer a different Catppuccin flavor."
echo "Enjoy your new Hyprland setup!"
