#!/bin/sh
#
# zsh-sync — cross-platform shell environment setup
#
# Live:
#   curl:      sh -c "$(curl -fsSL https://incube.maborak.com/wa.sh)"
#   wget:      sh -c "$(wget -qO- https://incube.maborak.com/wa.sh)"
#   /dev/tcp:  bash -c 'exec 3<>/dev/tcp/incube.maborak.com/80 && printf "GET /wa.sh HTTP/1.0\r\nHost: incube.maborak.com\r\n\r\n" >&3 && awk "/^\r?$/{p=1;next}p" <&3 | sh'
#
# Dev (test-server.sh on port 8877):
#   curl:      H=192.168.0.40; sh -c "$(curl -fsSL http://$H:8877/wa.sh)"
#   wget:      H=192.168.0.40; sh -c "$(wget -qO- http://$H:8877/wa.sh)"
#   /dev/tcp:  H=192.168.0.40; bash -c "exec 3<>/dev/tcp/$H/8877 && printf 'GET /wa.sh HTTP/1.0\r\nHost: $H\r\n\r\n' >&3 && awk '/^\r?$/{p=1;next}p' <&3 | sh"
#

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PACKAGES="curl wget zsh swaks vim tmux git htop"
BACKUP_DIR="$HOME/.zsh-sync-backup/$(date +%Y%m%d%H%M%S)"

PLUGIN_AUTOSUGGESTIONS_URL="https://github.com/zsh-users/zsh-autosuggestions"
PLUGIN_SYNTAX_HIGHLIGHT_URL="https://github.com/zsh-users/zsh-syntax-highlighting"
TMUX_CONFIG_URL="https://github.com/gpakosz/.tmux.git"

DISTRO=""
SUDO_CMD=""

# ---------------------------------------------------------------------------
# Utility: output
# ---------------------------------------------------------------------------

_color() {
    if [ -t 1 ]; then
        printf "\033[%sm%s\033[0m\n" "$1" "$2"
    else
        printf "%s\n" "$2"
    fi
}

info()    { _color "34" "  [INFO] $*"; }
success() { _color "32" "  [OK]   $*"; }
warn()    { _color "33" "  [WARN] $*"; }
error()   { _color "31" "  [ERR]  $*"; }
die()     { error "$*"; exit 1; }

banner() {
    if [ -t 1 ]; then
        printf "\033[1;36m\n"
        printf "  ╔══════════════════════════════╗\n"
        printf "  ║        zsh-sync setup        ║\n"
        printf "  ╚══════════════════════════════╝\n"
        printf "\033[0m\n"
    else
        printf "\n=== zsh-sync setup ===\n\n"
    fi
}

# ---------------------------------------------------------------------------
# Utility: helpers
# ---------------------------------------------------------------------------

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

backup_file() {
    local file="$1"
    if [ -e "$file" ]; then
        local dest="$BACKUP_DIR$(dirname "$file")"
        mkdir -p "$dest"
        cp -r "$file" "$dest/"
        warn "Backed up $file → $BACKUP_DIR$(dirname "$file")/"
    fi
}

git_clone_or_pull() {
    local url="$1"
    local dest="$2"
    if [ -d "$dest/.git" ]; then
        info "Updating $(basename "$dest")..."
        git -C "$dest" pull --ff-only || warn "Could not update $dest — skipping"
    else
        info "Cloning $(basename "$dest")..."
        git clone "$url" "$dest" || die "Failed to clone $url"
    fi
}

ensure_line_in_file() {
    local line="$1"
    local file="$2"
    if [ -f "$file" ] && grep -qF "$line" "$file"; then
        return 0
    fi
    printf "%s\n" "$line" >> "$file"
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

detect_distro() {
    local uname
    uname=$(uname -s | tr '[:upper:]' '[:lower:]')

    if [ "$uname" = "darwin" ]; then
        DISTRO="darwin"
        return
    fi

    # Modern approach: /etc/os-release (works on all major distros since ~2013)
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        DISTRO=$(. /etc/os-release && printf "%s" "${ID:-}" | tr '[:upper:]' '[:lower:]')
    elif command_exists lsb_release; then
        DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
    fi

    # Normalize to package manager families
    case "$DISTRO" in
        ubuntu|debian|pop|linuxmint|elementary|kali|raspbian)
            DISTRO="debian"
            ;;
        rhel|redhatenterpriseserver)
            DISTRO="redhat"
            ;;
        centos|rocky|almalinux)
            DISTRO="centos"
            ;;
        fedora)
            DISTRO="fedora"
            ;;
        arch|manjaro|endeavouros)
            DISTRO="arch"
            ;;
    esac

    if [ -z "$DISTRO" ]; then
        die "Could not detect Linux distribution. Please install packages manually and re-run."
    fi
}

detect_sudo() {
    if [ "$(id -u)" = "0" ]; then
        SUDO_CMD=""
        info "Running as root — no sudo needed"
    elif command_exists sudo; then
        SUDO_CMD="sudo"
        info "Non-root user detected — will use sudo for package installation"
        sudo -v || die "sudo access required but credentials could not be validated"
    else
        warn "Not root and sudo not found — package installation may fail"
        SUDO_CMD=""
    fi
}

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------

install_packages() {
    info "Checking packages: $PACKAGES"

    local missing=""
    for pkg in $PACKAGES; do
        if command_exists "$pkg"; then
            success "$pkg already installed"
        else
            missing="$missing $pkg"
        fi
    done

    if [ -z "$missing" ]; then
        success "All packages already installed"
        return
    fi

    info "Installing:$missing"

    case "$DISTRO" in
        centos|redhat)
            $SUDO_CMD yum install -y epel-release || warn "EPEL install failed — continuing anyway"
            $SUDO_CMD yum install -y $missing || die "Package installation failed"
            ;;
        fedora)
            $SUDO_CMD dnf install -y $missing || die "Package installation failed"
            ;;
        debian)
            $SUDO_CMD apt-get update -qq || warn "apt-get update failed — continuing anyway"
            $SUDO_CMD apt-get install -y $missing || die "Package installation failed"
            ;;
        darwin)
            if ! command_exists brew; then
                die "Homebrew not found. Install it first: https://brew.sh"
            fi
            brew install $missing || die "brew install failed"
            ;;
        arch)
            $SUDO_CMD pacman -S --noconfirm $missing || die "Package installation failed"
            ;;
        *)
            die "Unsupported distro: $DISTRO. Install manually: $missing"
            ;;
    esac

    success "Packages installed"
}

install_ohmyzsh() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        success "Oh My Zsh already installed — skipping"
        return
    fi

    info "Installing Oh My Zsh..."
    backup_file "$HOME/.zshrc"

    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
        || die "Oh My Zsh installation failed"

    success "Oh My Zsh installed"
}

install_zsh_plugins() {
    info "Installing zsh plugins..."

    git_clone_or_pull "$PLUGIN_AUTOSUGGESTIONS_URL" "$HOME/.zsh/zsh-autosuggestions"
    ensure_line_in_file \
        "source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" \
        "$HOME/.zshrc"

    git_clone_or_pull "$PLUGIN_SYNTAX_HIGHLIGHT_URL" "$HOME/.zsh/zsh-syntax-highlighting"
    ensure_line_in_file \
        "source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
        "$HOME/.zshrc"

    success "Zsh plugins configured"
}

configure_zshrc() {
    if [ ! -f "$HOME/.zshrc" ]; then
        warn "~/.zshrc not found — skipping theme configuration"
        return
    fi

    if grep -q 'ZSH_THEME="random"' "$HOME/.zshrc"; then
        success "ZSH_THEME already set to random — skipping"
        return
    fi

    info "Setting ZSH_THEME to random..."
    if [ "$DISTRO" = "darwin" ]; then
        sed -i '' 's/ZSH_THEME="robbyrussell"/ZSH_THEME="random"/' "$HOME/.zshrc"
    else
        sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="random"/' "$HOME/.zshrc"
    fi

    success "ZSH_THEME set to random"
}

setup_tmux() {
    info "Setting up tmux config..."

    git_clone_or_pull "$TMUX_CONFIG_URL" "$HOME/.tmux"

    if [ ! -L "$HOME/.tmux.conf" ]; then
        ln -sf "$HOME/.tmux/.tmux.conf" "$HOME/.tmux.conf"
        success "Symlinked ~/.tmux.conf"
    else
        success "~/.tmux.conf symlink already exists"
    fi

    if [ ! -f "$HOME/.tmux.conf.local" ]; then
        cp "$HOME/.tmux/.tmux.conf.local" "$HOME/.tmux.conf.local"
        success "Copied .tmux.conf.local"
    else
        success "~/.tmux.conf.local already exists — preserving user customizations"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    banner

    info "Detecting system..."
    detect_distro
    info "Distribution: $DISTRO"
    detect_sudo

    printf "\n"
    install_packages

    printf "\n"
    install_ohmyzsh

    printf "\n"
    install_zsh_plugins
    configure_zshrc

    printf "\n"
    setup_tmux

    printf "\n"
    if _color "1;32" "" >/dev/null 2>&1 && [ -t 1 ]; then
        printf "\033[1;32m  Setup complete!\033[0m\n\n"
    else
        printf "  Setup complete!\n\n"
    fi

    # Suggest chsh if current shell is not zsh
    if [ "$(basename "$SHELL")" != "zsh" ]; then
        local zsh_path
        zsh_path=$(command -v zsh 2>/dev/null || true)
        if [ -n "$zsh_path" ]; then
            warn "Your current shell is $SHELL. To switch to zsh, run:"
            warn "  chsh -s $zsh_path"
        fi
    fi

    if [ -d "$BACKUP_DIR" ]; then
        info "Backups saved to: $BACKUP_DIR"
    fi
}

main "$@"
