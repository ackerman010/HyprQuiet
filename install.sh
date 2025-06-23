#!/usr/bin/env bash
# install.sh — Automated HyprQuiet installer for Fedora 42
set -euo pipefail

# Timestamp for backups
TS=$(date +"%Y%m%d-%H%M%S")

# --- GLOBAL PKG_CONFIG_PATH SETUP ---
# Prioritize /usr/local/lib/pkgconfig for source-built libraries
# Use :- to initialize if PKG_CONFIG_PATH is not already set, preventing unbound variable error
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
echo "Global PKG_CONFIG_PATH set to: $PKG_CONFIG_PATH"

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
# This function is now specifically for swww, as others are moving to COPR.
build_and_install_rust_project() {
    local repo_url="$1"
    local temp_path="$2"
    local bin_name="$3"

    echo "Building and installing $bin_name from source..."
    cleanup_temp_dir "$temp_path" # Ensure clean slate before cloning

    # Use --depth 1 for faster and potentially more reliable cloning of public repos
    git clone --depth 1 "$repo_url" "$temp_path"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to clone $bin_name repository from $repo_url. Git clone failed."
        exit 1
    fi
    if [ ! -d "$temp_path" ]; then
        echo "Error: Cloned $bin_name repository directory $temp_path does not exist."
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

# Function to build and install C++ projects using CMake
# This function is now only used if there's a specific need outside of the COPR.
build_and_install_cmake_project() {
    local repo_url="$1"
    local temp_path="$2"
    local bin_name="$3" # Optional: The main binary name if different from repo name

    echo "Building and installing $bin_name from source using cmake/make..."
    cleanup_temp_dir "$temp_path" # Ensure clean slate before cloning

    # Use --depth 1 for faster and potentially more reliable cloning of public repos
    git clone --depth 1 "$repo_url" "$temp_path"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to clone $bin_name repository from $repo_url. Git clone failed."
        exit 1
    fi
    if [ ! -d "$temp_path" ]; then
        echo "Error: Cloned $bin_name repository directory $temp_path does not exist."
        exit 1
    fi

    local current_dir="$PWD"
    cd "$temp_path"

    # For cmake projects that might need to be built in a 'build' subdirectory
    mkdir -p build
    cd build

    cmake .. # Configure from parent directory
    cmake --build .
    sudo cmake --install .
    
    cd "$current_dir" > /dev/null # Return to original directory
    echo "$bin_name installed from source using cmake/make."
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
echo "[2/14] Deploying HyprQuiet configs to ~/.config/ and related paths..."
CONFIG_DIRS=("hypr" "rofi" "waybar" "swaync" "hyprwall" "wlogout" "cava")

for dir in "${CONFIG_DIRS[@]}"; do
    SOURCE_PATH="$PWD/config/$dir"
    DEST_PATH="$HOME/.config/$dir"
    
    if [ -d "$SOURCE_PATH" ]; then
        echo "  - Deploying $dir configuration..."
        mkdir -p "$DEST_PATH"
        # Remove existing contents to ensure a clean overwrite
        if [ "$(ls -A "$DEST_PATH" 2>/dev/null)" ]; then # Check if directory is not empty
            echo "    - Clearing existing contents in $DEST_PATH..."
            sudo rm -rf "$DEST_PATH/*" || true # Use sudo and || true for robustness
        fi
        cp -r "$SOURCE_PATH/." "$DEST_PATH/"
        echo "    - $dir configs deployed to $DEST_PATH"
    else
        echo "  - Warning: Source directory $SOURCE_PATH not found, skipping $dir deployment."
    fi
done
echo "HyprQuiet configs deployment complete."


# 3. Deploy local scripts
echo "[3/14] Installing local scripts to ~/.local/bin/..."
mkdir -p "$HOME/.local/bin"
# Remove existing contents to ensure a clean overwrite
if [ "$(ls -A "$HOME/.local/bin" 2>/dev/null)" ]; then # Check if directory is not empty
    echo "  - Clearing existing contents in ~/.local/bin/..."
    sudo rm -rf "$HOME/.local/bin/*" || true
fi
cp -r "$PWD/local/bin/"* "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/"* # Re-apply executable permissions
echo "Local scripts deployed and made executable in ~/.local/bin/"

# 4. System update and package installation
echo "[4/14] Updating system and installing core packages..."
sudo dnf upgrade -y

# Enable Hyprland specific COPR for key packages, essential for hyprland and its devel packages
echo "--- Ensuring Hyprland COPR repository (solopasha/hyprland) is enabled ---"
# Switched to solopasha/hyprland COPR for comprehensive Hyprland component availability
if ! sudo dnf copr enable -y "solopasha/hyprland"; then
    echo "Error: Failed to enable COPR repository 'solopasha/hyprland'. Please check the COPR name or internet connection."
    exit 1 # Exit if this critical COPR cannot be enabled
fi


# --- PROACTIVE REMOVAL of potentially conflicting older versions from DNF/COPR ---
# This ensures that our newly installed COPR versions are the ones pkg-config finds.
# This step is crucial for preventing conflicts and ensuring the COPR versions are used.
echo "--- Proactively removing conflicting Hyprland-related DNF packages (if any) to ensure clean install from COPR ---"
for pkg in hyprlang hyprutils hyprgraphics hyprpaper mpvpaper swaync; do
    if sudo dnf list installed "$pkg" &>/dev/null; then
        echo "Removing conflicting DNF package: $pkg"
        sudo dnf remove -y "$pkg" || true # Use || true to prevent script exit if removal fails for non-critical reasons
    else
        echo "Conflicting DNF package $pkg not found, skipping removal."
    fi
done
echo "Attempted to remove conflicting Hyprland-related packages."


# Essential build tools and libraries for ALL projects (Rust and C++)
# Now installing hyprland, hyprpaper, hyprlang, hyprutils, hyprgraphics, mpvpaper, swaync from COPR.
sudo dnf install -y \
    git cargo pkgconfig \
    cmake make gcc-c++ \
    wayland-devel lz4-devel wayland-protocols-devel \
    libpng-devel cairo-devel gdk-pixbuf2-devel \
    file-devel \
    libei-devel libinput-devel \
    gtk3 gtk2 libnotify gsettings-desktop-schemas \
    fontconfig \
    dnf-plugins-core \
    hyprland hyprpaper hyprlang hyprutils hyprgraphics \
    mpvpaper swaync \
    waybar cava rofi mpv \
    thunar thunar-archive-plugin mate-polkit \
    sddm swayidle swaylock dmenu || \
    { echo "Error: One or more DNF packages could not be installed. Please check the output above."; exit 1; }
echo "Core packages and development tools installed."

# --- Removed manual source builds for hyprlang, hyprutils, hyprgraphics, hyprpaper, mpvpaper, and swaync ---
# These are now expected to be installed via the solopasha/hyprland COPR in the main dnf install step.

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
# swww is generally not in Hyprland COPRs, so keeping source build for it.
if ! command_exists swww; then
    # No specific custom_cd_path; dynamic discovery will handle.
    build_and_install_rust_project "https://github.com/LGFae/swww.git" "/tmp/swww" "swww"
else
    echo "swww already installed, skipping source build."
fi

# 8. Removed Hyprpaper specific install logic. It's now part of step 4 DNF install.
# Keeping the numbering for consistency with other steps.
echo "[8/14] Hyprpaper and related Hyprland components handled by DNF/COPR in Step 4."


# 9. Removed Mpvpaper specific install logic. It's now part of step 4 DNF install.
# Keeping the numbering for consistency with other steps.
echo "[9/14] Mpvpaper handled by DNF/COPR in Step 4."


# 10. Removed SwayNC specific install logic. It's now part of step 4 DNF install.
# Keeping the numbering for consistency with other steps.
echo "[10/14] SwayNC handled by DNF/COPR in Step 4."

# 11. Install Nerd Fonts fallback (This section might be problematic due to COPR availability or package names)
echo "[11/14] Installing Nerd Fonts..."
# Install base nerd-fonts package first
echo "  - Installing base 'nerd-fonts' package..."
sudo dnf install -y nerd-fonts || echo "Warning: Base 'nerd-fonts' package could not be installed."

# Using the new COPR for Nerd Fonts
echo "  - Enabling 'che/nerd-fonts' COPR..."
if ! sudo dnf copr enable -y "che/nerd-fonts"; then
    echo "⚠️ COPR enable failed for 'che/nerd-fonts', skipping further Nerd Fonts installation from this COPR."
else
    echo "  - Installing 'nerd-fonts-complete' from COPR..."
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
git clone --depth 1 https://github.com/vinceliuice/Tela-circle-icon-theme.git /tmp/tela
if [ $? -ne 0 ]; then
    echo "Error: Failed to clone Tela Circle Icon Theme repository."
    exit 1
fi
if [ ! -d "/tmp/tela" ]; then
    echo "Error: Cloned Tela Circle Icon Theme directory /tmp/tela does not exist."
    exit 1
fi

cd /tmp/tela
if [ -f "./install.sh" ]; then
    chmod +x ./install.sh
    echo "  - Running Tela Circle Icon Theme install script..."
    ./install.sh -a
else
    echo "Error: Tela Circle Icon Theme install.sh not found. Attempting manual copy."
    # Fallback to manual copy if install.sh is missing
    # Assumes themes are directly in subdirectories of the cloned repo
    find . -maxdepth 2 -type d -name "Tela-circle-dracula*" -exec sudo cp -r {} /usr/share/icons/ \; || { echo "Error: Failed to manually copy Tela-circle-dracula theme."; }
    sudo gtk-update-icon-cache -f -t /usr/share/icons/ || { echo "Warning: Failed to update GTK icon cache for Tela theme."; }
fi
cd - > /dev/null # Return to previous directory silently
echo "Tela Circle Dracula Icons installed."

cleanup_temp_dir "/tmp/catppuccin" # Ensure clean slate before cloning
git clone --depth 1 https://github.com/catppuccin/gtk.git /tmp/catppuccin
if [ $? -ne 0 ]; then
    echo "Error: Failed to clone Catppuccin GTK Theme repository."
    exit 1
fi
if [ ! -d "/tmp/catppuccin" ]; then
    echo "Error: Cloned Catppuccin GTK Theme directory /tmp/catppuccin does not exist."
    exit 1
fi

cd /tmp/catppuccin
# Check if install.sh exists and make it executable before running
if [ -f "./install.sh" ]; then
    chmod +x "./install.sh"
    echo "  - Running Catppuccin GTK Theme install script (Mocha)..."
    ./install.sh mocha
else
    echo "Error: Catppuccin GTK Theme install.sh not found. Attempting manual copy."
    # Fallback to manual copy if install.sh is missing
    # Assumes themes are directly in subdirectories of the cloned repo
    find . -maxdepth 2 -type d -name "Catppuccin-Mocha*" -exec sudo cp -r {} /usr/share/themes/ \; || { echo "Error: Failed to manually copy Catppuccin-Mocha theme."; }
fi
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
# Removed specific cleanup for repos no longer source-built
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
