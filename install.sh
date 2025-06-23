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

# Function to build and install Rust projects from source, with a more direct Cargo.toml discovery
# This function is used for swww, mpvpaper, and swaync, which are Rust-based.
build_and_install_rust_project() {
    local repo_url="$1"
    local temp_path="$2"
    local bin_name="$3"

    echo "Building and installing $bin_name from source..."
    cleanup_temp_dir "$temp_path" # Ensure clean slate before cloning

    git clone "$repo_url" "$temp_path"
    if [ ! -d "$temp_path" ]; then
        echo "Error: Failed to clone $bin_name repository from $repo_url."
        exit 1
    fi

    local current_dir="$PWD"
    cd "$temp_path"

    local build_dir="." # Default to the root of the cloned repo

    # Check for Cargo.toml in common locations
    if [ -f "./Cargo.toml" ]; then
        build_dir="."
    elif [ -f "$bin_name/Cargo.toml" ]; then # E.g., repo/hyprpaper/Cargo.toml
        build_dir="$bin_name"
    elif [ -f "src/Cargo.toml" ]; then # E.g., repo/src/Cargo.toml (less common for main project)
        build_dir="src"
    else
        echo "Warning: Cargo.toml not found in common locations (root or '$bin_name/' or 'src/')."
        echo "Attempting to find it, but this might indicate an unusual repository structure for $bin_name."
        # Fallback to a broader find if the above direct checks fail.
        # Use -maxdepth to avoid issues with dirname if nothing is found.
        # This will return the path relative to the current directory (temp_path).
        local found_path=$(find . -maxdepth 3 -type f -name "Cargo.toml" -print -quit 2>/dev/null | xargs dirname || echo "")
        if [ -n "$found_path" ]; then
            build_dir="$found_path"
            echo "Found Cargo.toml at: $build_dir"
        else
            echo "Error: Cargo.toml not found in any discoverable subdirectory of $temp_path for $bin_name."
            echo "Cannot build. Please manually check the repository '$repo_url' for the correct Cargo.toml location."
            cd "$current_dir" > /dev/null # Return to original directory before exiting
            exit 1
        fi
    fi

    echo "Changing directory to $temp_path/$build_dir for building..."
    cd "$build_dir"

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

# Enable Hyprland specific COPRs for key packages first, as hyprland-devel might be here
echo "--- Ensuring Hyprland COPR repository is enabled ---"
# This COPR often contains hyprland and its development packages.
if ! sudo dnf copr enable -y "agustinesteso/Hyprland"; then
    echo "Warning: Failed to enable COPR repository 'agustinesteso/Hyprland'. Hyprland and related devel packages might not be found."
fi


# Essential build tools and libraries
sudo dnf install -y \
    git cargo pkgconfig \
    cmake make gcc-c++ \
    wayland-devel lz4-devel wayland-protocols-devel \
    libpng-devel cairo-devel gdk-pixbuf2-devel \
    hyprland-devel || { echo "Warning: hyprland-devel package could not be installed. This might affect hyprpaper compilation."; } \
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
    # No specific custom_cd_path; dynamic discovery will handle.
    build_and_install_rust_project "https://github.com/LGFae/swww.git" "/tmp/swww" "swww"
else
    echo "swww already installed, skipping source build."
fi

# 8. Install Hyprpaper
echo "[8/14] Installing Hyprpaper wallpaper tool (using cmake/make)---"
if ! command_exists hyprpaper; then
    echo "Attempting to install hyprpaper via DNF first..."
    if sudo dnf install -y hyprpaper; then
        echo "Hyprpaper installed successfully via DNF."
    else
        echo "Hyprpaper not found in DNF, building from source using cmake/make..."
        cleanup_temp_dir "/tmp/hyprpaper_repo" # Ensure clean slate before cloning
        git clone https://github.com/hyprwm/hyprpaper.git "/tmp/hyprpaper_repo"
        if [ ! -d "/tmp/hyprpaper_repo" ]; then
            echo "Error: Failed to clone Hyprpaper repository."
            exit 1
        fi
        # 'current_dir' is already declared in the main script scope.
        current_dir="$PWD"
        cd "/tmp/hyprpaper_repo"
        cmake -Bbuild
        cmake --build build
        sudo cmake --install build
        cd "$current_dir" > /dev/null # Return to original directory
        echo "Hyprpaper installed from source using cmake/make."
    fi
else
    echo "Hyprpaper already installed, skipping installation."
fi

# 9. Install Mpvpaper
echo "[9/14] Installing mpvpaper wallpaper sequencer..."
if ! command_exists mpvpaper; then
    # No specific custom_cd_path; dynamic discovery will handle.
    build_and_install_rust_project "https://github.com/LGFae/mpvpaper.git" "/tmp/mpvpaper" "mpvpaper"
else
    echo "mpvpaper already installed, skipping source build."
fi

# 10. Install SwayNC
echo "[10/14] Installing SwayNC notification daemon..."
if ! command_exists swync; then
    # No specific custom_cd_path; dynamic discovery will handle.
    build_and_install_rust_project "https://github.com/Twnmt/SwayNC.git" "/tmp/swaync" "swaync"
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
