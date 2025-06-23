#!/bin/bash
# Hyprland Dotfiles Installation Script for Fedora 42
# Author: Gemini

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Variables ---
DOTFILES_REPO="https://github.com/ackerman010/HyprQuiet.git"
DOTFILES_DIR_NAME="HyprQuiet"
TEMP_DIR="/tmp/$DOTFILES_DIR_NAME-install"

# --- Functions ---

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install DNF packages
install_dnf_packages() {
    echo "--- Installing DNF packages: $* ---"
    sudo dnf install -y "$@"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install DNF packages. Please check your internet connection or package names."
        exit 1
    fi
}

# Function to enable and install COPR repositories and packages
enable_copr_and_install() {
    local copr_repo="$1"
    shift
    local packages=("$@")

    echo "--- Enabling COPR repository: $copr_repo ---"
    if ! sudo dnf copr enable -y "$copr_repo"; then
        echo "Error: Failed to enable COPR repository $copr_repo."
        exit 1
    fi

    echo "--- Installing packages from $copr_repo: ${packages[@]} ---"
    install_dnf_packages "${packages[@]}"
}

# Function to clone dotfiles
clone_dotfiles() {
    echo "--- Cloning dotfiles from $DOTFILES_REPO ---"
    mkdir -p "$TEMP_DIR"
    if [ -d "$TEMP_DIR/$DOTFILES_DIR_NAME" ]; then
        echo "Removing existing temporary dotfiles directory..."
        rm -rf "$TEMP_DIR/$DOTFILES_DIR_NAME"
    fi
    git clone "$DOTFILES_REPO" "$TEMP_DIR/$DOTFILES_DIR_NAME"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to clone dotfiles. Please check the repository URL or your internet connection."
        exit 1
    fi
    echo "Dotfiles cloned to $TEMP_DIR/$DOTFILES_DIR_NAME"
}

# Function to backup and install Hyprland configurations
install_hyprland_configs() {
    echo "--- Backing up existing Hyprland configurations (if any) ---"
    if [ -d "$HOME/.config/hypr" ]; then
        mv "$HOME/.config/hypr" "$HOME/.config/hypr_backup_$(date +%Y%m%d_%H%M%S)"
        echo "Existing ~/.config/hypr backed up."
    fi

    echo "--- Installing new Hyprland configurations ---"
    mkdir -p "$HOME/.config/hypr"
    cp -r "$TEMP_DIR/$DOTFILES_DIR_NAME/config/hypr/"* "$HOME/.config/hypr/"
    echo "Hyprland configurations copied to ~/.config/hypr."

    echo "--- Copying local/bin scripts and making them executable ---"
    mkdir -p "$HOME/.local/bin"
    cp -r "$TEMP_DIR/$DOTFILES_DIR_NAME/local/bin/"* "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/"*
    echo "Scripts copied to ~/.local/bin and made executable."
}

# Function to install Nerd Fonts (Fira Code Nerd Font)
install_nerd_font() {
    echo "--- Installing Fira Code Nerd Font ---"
    FONT_DIR="$HOME/.local/share/fonts"
    mkdir -p "$FONT_DIR"
    FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/FiraCode.zip"
    FONT_ZIP="$TEMP_DIR/FiraCode.zip"

    echo "Downloading FiraCode Nerd Font from $FONT_URL..."
    wget -q --show-progress "$FONT_URL" -O "$FONT_ZIP"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download Fira Code Nerd Font."
        return 1
    fi

    echo "Unzipping font files to $FONT_DIR..."
    unzip -o "$FONT_ZIP" -d "$FONT_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to unzip Fira Code Nerd Font."
        return 1
    fi

    echo "Updating font cache..."
    fc-cache -fv
    echo "Fira Code Nerd Font installed."
}

# Function to install and set icon and GTK themes
install_and_set_themes() {
    echo "--- Installing Tela Circle Dracula Icon Theme ---"
    ICON_THEME_DIR="/usr/share/icons/Tela-Circle-Dracula"
    if [ -d "$ICON_THEME_DIR" ]; then
        echo "Tela Circle Dracula already exists, skipping clone."
    else
        sudo git clone https://github.com/dracula/tela-circle-dracula-icons.git "$TEMP_DIR/tela-circle-dracula-icons"
        sudo mv "$TEMP_DIR/tela-circle-dracula-icons" "$ICON_THEME_DIR"
    fi
    echo "Setting Tela Circle Dracula as default icon theme..."
    gsettings set org.gnome.desktop.interface icon-theme 'Tela-Circle-Dracula'
    echo "Tela Circle Dracula Icon Theme installed and set."

    echo "--- Installing Catppuccin GTK Theme ---"
    GTK_THEME_DIR="/usr/share/themes/Catppuccin"
    if [ -d "$GTK_THEME_DIR" ]; then
        echo "Catppuccin GTK theme already exists, skipping clone."
    else
        sudo git clone https://github.com/catppuccin/gtk.git "$TEMP_DIR/catppuccin-gtk"
        sudo mv "$TEMP_DIR/catppuccin-gtk" "$GTK_THEME_DIR"
    fi
    echo "Setting Catppuccin-Frappe-Standard as default GTK theme (you can change variant later)..."
    # Choose a variant, e.g., Latte, Frappe, Macchiato, Mocha
    gsettings set org.gnome.desktop.interface gtk-theme 'Catppuccin-Frappe-Standard'
    echo "Catppuccin GTK Theme installed and set."
}

# Function to install Thunar and its dependencies
install_thunar_and_dependencies() {
    echo "--- Installing Thunar and related packages ---"
    install_dnf_packages thunar thunar-archive-plugin polkit-gnome

    echo "--- Attempting to remove other common file managers (if installed) ---"
    echo "This step is optional and requires user confirmation. Please review."
    # List common file managers to attempt removal
    COMMON_FILE_MANAGERS=("nautilus" "dolphin" "pcmanfm" "caja" "konqueror" "gnome-files")
    for fm in "${COMMON_FILE_MANAGERS[@]}"; do
        if command_exists "$fm"; then
            read -rp "Do you want to remove '$fm'? (y/N): " choice
            case "$choice" in
                y|Y )
                    echo "Removing $fm..."
                    sudo dnf remove -y "$fm" || echo "Warning: Could not remove $fm."
                    ;;
                * )
                    echo "Skipping removal of $fm."
                    ;;
            esac
        fi
    done
    echo "Thunar and its dependencies installed."
}

# --- Main Script Execution ---

echo "Starting Hyprland Dotfiles Installation for Fedora 42..."

# 1. Update DNF and install core tools
echo "--- Updating DNF and installing core utilities ---"
sudo dnf update -y
install_dnf_packages git wget unzip tar

# 2. Enable Hyprland specific COPRs for key packages
echo "--- Enabling COPR repositories for Hyprland related packages ---"
# These COPRs often contain swww, hyprpaper, mpvpaper and other Hyprland tools.
# If these don't work, you might need to find the specific COPR or compile from source.
enable_copr_and_install "agustinesteso/Hyprland" swww hyprpaper mpvpaper
# If you encounter issues with the above COPR, you might try a specific COPR for swww/mpvpaper if they exist, or build from source.
# Example for swww if not in 'agustinesteso/Hyprland':
# enable_copr_and_install "xddxdd/swww" swww

# 3. Install main dependencies
install_dnf_packages waybar rofi swaync cava sddm

# 4. Clone dotfiles
clone_dotfiles

# 5. Install Hyprland configurations
install_hyprland_configs

# 6. Install Nerd Fonts
install_nerd_font

# 7. Install and set icon and GTK themes
install_and_set_themes

# 8. Install Thunar and its dependencies
install_thunar_and_dependencies

# 9. Configure SDDM
echo "--- Configuring SDDM as the display manager ---"
sudo systemctl enable sddm
sudo systemctl set-default graphical.target
echo "SDDM enabled and set as default display manager."
echo "You might need to reboot for SDDM to take effect."

echo "--- Cleaning up temporary files ---"
rm -rf "$TEMP_DIR"

echo "Installation complete!"
echo "------------------------------------------------------------"
echo "IMPORTANT NEXT STEPS:"
echo "1. Reboot your system: 'sudo reboot'"
echo "2. After reboot, select 'Hyprland' session from SDDM."
echo "3. Review your ~/.config/hypr/hyprland.conf and related files to ensure everything is sourced correctly."
echo "4. You might need to adjust GTK theme variants via 'gsettings set org.gnome.desktop.interface gtk-theme <variant>' or a GUI tool if you prefer a different Catppuccin flavor."
echo "Enjoy your new Hyprland setup!"
