#!/bin/bash
# ============================================================================
# Clawke Server Installer
# ============================================================================
# One-click installation script for macOS, Linux, and Windows (via WSL).
# Installs Node.js (if needed), clones the repo, builds the server,
# and sets up the `clawke` command globally.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/clawke/clawke/main/scripts/install.sh | bash
#
# Or with options:
#   curl -fsSL ... | bash -s -- --branch dev --skip-build
#
# ============================================================================

set -e

# ────────────── Colors ──────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'  # No Color
BOLD='\033[1m'

# ────────────── Configuration ──────────────

REPO_URL_SSH="git@github.com:clawke/clawke.git"
REPO_URL_HTTPS="https://github.com/clawke/clawke.git"
CLAWKE_HOME="${CLAWKE_HOME:-$HOME/.clawke}"
INSTALL_DIR="${CLAWKE_INSTALL_DIR:-$CLAWKE_HOME/clawke}"
NODE_VERSION="22"
NODE_MIN_VERSION="18"

# Options
BRANCH="main"
SKIP_BUILD=false
LOCAL_MODE=false
LOCAL_SOURCE=""

# Detect non-interactive mode (e.g. curl | bash)
if [ -t 0 ]; then
    IS_INTERACTIVE=true
else
    IS_INTERACTIVE=false
fi

# ────────────── Parse arguments ──────────────

while [[ $# -gt 0 ]]; do
    case $1 in
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --clawke-home)
            CLAWKE_HOME="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --local)
            LOCAL_MODE=true
            if [ -n "${2:-}" ] && [[ ! "$2" == --* ]]; then
                LOCAL_SOURCE="$2"
                shift 2
            else
                shift
            fi
            ;;
        -h|--help)
            echo "Clawke Server Installer"
            echo ""
            echo "Usage: install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --branch NAME       Git branch to install (default: main)"
            echo "  --dir PATH          Installation directory (default: ~/.clawke/clawke)"
            echo "  --clawke-home PATH  Data directory (default: ~/.clawke)"
            echo "  --skip-build        Skip TypeScript compilation"
            echo "  --local [PATH]      Use local project instead of git clone (dev mode)"
            echo "  -h, --help          Show this help"
            echo ""
            echo "Windows users: Install WSL first (wsl --install), then run this in WSL."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# Helper functions
# ============================================================================

print_banner() {
    echo ""
    echo -e "${MAGENTA}${BOLD}"
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│              🦅 Clawke Server Installer                 │"
    echo "├─────────────────────────────────────────────────────────┤"
    echo "│  Secure edge-cloud AI workspace.                       │"
    echo "│  https://github.com/clawke/clawke                      │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
}

log_info() {
    echo -e "${CYAN}→${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

prompt_yes_no() {
    local question="$1"
    local default="${2:-yes}"
    local prompt_suffix
    local answer=""

    case "$default" in
        [yY]|[yY][eE][sS]|1) prompt_suffix="[Y/n]" ;;
        *) prompt_suffix="[y/N]" ;;
    esac

    if [ "$IS_INTERACTIVE" = true ]; then
        read -r -p "$question $prompt_suffix " answer || answer=""
    elif [ -r /dev/tty ] && [ -w /dev/tty ]; then
        printf "%s %s " "$question" "$prompt_suffix" > /dev/tty
        IFS= read -r answer < /dev/tty || answer=""
    else
        answer=""
    fi

    # Trim whitespace
    answer="${answer#"${answer%%[![:space:]]*}"}"
    answer="${answer%"${answer##*[![:space:]]}"}"

    if [ -z "$answer" ]; then
        case "$default" in
            [yY]|[yY][eE][sS]|1) return 0 ;;
            *) return 1 ;;
        esac
    fi

    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

get_command_link_dir() {
    echo "$HOME/.local/bin"
}

# ────────────── Auto-detect local mode ──────────────
# If running from within the clawke repo (scripts/install.sh),
# auto-enable local mode using the repo root.
if [ "$LOCAL_MODE" = false ] && [ -z "$LOCAL_SOURCE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CANDIDATE_ROOT="$(dirname "$SCRIPT_DIR")"
    if [ -f "$CANDIDATE_ROOT/server/package.json" ] && [ -d "$CANDIDATE_ROOT/gateways" ]; then
        LOCAL_MODE=true
        LOCAL_SOURCE="$CANDIDATE_ROOT"
    fi
fi

# ============================================================================
# System detection
# ============================================================================

detect_os() {
    case "$(uname -s)" in
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                OS="wsl"
                DISTRO="wsl"
            elif [ -f /etc/os-release ]; then
                OS="linux"
                . /etc/os-release
                DISTRO="$ID"
            else
                OS="linux"
                DISTRO="unknown"
            fi
            ;;
        Darwin*)
            OS="macos"
            DISTRO="macos"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            log_error "Native Windows detected."
            log_info "Please install WSL first, then run this script inside WSL:"
            log_info "  1. Open PowerShell as Admin and run: wsl --install"
            log_info "  2. Restart your computer"
            log_info "  3. Open Ubuntu (WSL) and run this install script"
            exit 1
            ;;
        *)
            OS="unknown"
            DISTRO="unknown"
            log_warn "Unknown operating system: $(uname -s)"
            ;;
    esac

    log_success "Detected: $OS ($DISTRO)"
}

# ============================================================================
# Dependency checks
# ============================================================================

check_git() {
    log_info "Checking Git..."

    if command -v git &> /dev/null; then
        GIT_VERSION=$(git --version | awk '{print $3}')
        log_success "Git $GIT_VERSION found"
        return 0
    fi

    log_error "Git not found"

    log_info "Please install Git:"
    case "$OS" in
        linux|wsl)
            case "$DISTRO" in
                ubuntu|debian|wsl)
                    log_info "  sudo apt update && sudo apt install git"
                    ;;
                fedora)
                    log_info "  sudo dnf install git"
                    ;;
                arch)
                    log_info "  sudo pacman -S git"
                    ;;
                *)
                    log_info "  Use your package manager to install git"
                    ;;
            esac
            ;;
        macos)
            log_info "  xcode-select --install"
            log_info "  Or: brew install git"
            ;;
    esac

    exit 1
}

check_node() {
    log_info "Checking Node.js (>= $NODE_MIN_VERSION)..."

    # Check system-wide node
    if command -v node &> /dev/null; then
        local found_ver
        found_ver=$(node --version 2>/dev/null | sed 's/^v//')
        local major
        major=$(echo "$found_ver" | cut -d. -f1)
        if [ "$major" -ge "$NODE_MIN_VERSION" ] 2>/dev/null; then
            NODE_CMD="$(command -v node)"
            log_success "Node.js v$found_ver found"
            HAS_NODE=true
            return 0
        else
            log_warn "Node.js v$found_ver found but too old (need >= $NODE_MIN_VERSION)"
        fi
    fi

    # Check Clawke-managed install from a previous run
    if [ -x "$CLAWKE_HOME/node/bin/node" ]; then
        local found_ver
        found_ver=$("$CLAWKE_HOME/node/bin/node" --version 2>/dev/null | sed 's/^v//')
        local major
        major=$(echo "$found_ver" | cut -d. -f1)
        if [ "$major" -ge "$NODE_MIN_VERSION" ] 2>/dev/null; then
            export PATH="$CLAWKE_HOME/node/bin:$PATH"
            NODE_CMD="$CLAWKE_HOME/node/bin/node"
            log_success "Node.js v$found_ver found (Clawke-managed)"
            HAS_NODE=true
            return 0
        fi
    fi

    log_info "Node.js not found — installing Node.js $NODE_VERSION LTS..."
    install_node
}

install_node() {
    local arch
    arch=$(uname -m)
    local node_arch
    case "$arch" in
        x86_64)        node_arch="x64"    ;;
        aarch64|arm64) node_arch="arm64"  ;;
        armv7l)        node_arch="armv7l" ;;
        *)
            log_error "Unsupported architecture ($arch) for Node.js auto-install"
            log_info "Install Node.js manually: https://nodejs.org/en/download/"
            HAS_NODE=false
            exit 1
            ;;
    esac

    local node_os
    case "$OS" in
        linux|wsl) node_os="linux"  ;;
        macos)     node_os="darwin" ;;
        *)
            log_error "Unsupported OS for Node.js auto-install"
            HAS_NODE=false
            exit 1
            ;;
    esac

    # Resolve the latest tarball name from the index page
    local index_url="https://nodejs.org/dist/latest-v${NODE_VERSION}.x/"
    local tarball_name
    tarball_name=$(curl -fsSL "$index_url" \
        | grep -oE "node-v${NODE_VERSION}\.[0-9]+\.[0-9]+-${node_os}-${node_arch}\.tar\.xz" \
        | head -1)

    # Fallback to .tar.gz if .tar.xz not available
    if [ -z "$tarball_name" ]; then
        tarball_name=$(curl -fsSL "$index_url" \
            | grep -oE "node-v${NODE_VERSION}\.[0-9]+\.[0-9]+-${node_os}-${node_arch}\.tar\.gz" \
            | head -1)
    fi

    if [ -z "$tarball_name" ]; then
        log_error "Could not find Node.js $NODE_VERSION binary for $node_os-$node_arch"
        log_info "Install manually: https://nodejs.org/en/download/"
        HAS_NODE=false
        exit 1
    fi

    local download_url="${index_url}${tarball_name}"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    log_info "Downloading $tarball_name..."
    if ! curl -fsSL "$download_url" -o "$tmp_dir/$tarball_name"; then
        log_error "Download failed"
        rm -rf "$tmp_dir"
        exit 1
    fi

    log_info "Extracting to ~/.clawke/node/..."
    if [[ "$tarball_name" == *.tar.xz ]]; then
        tar xf "$tmp_dir/$tarball_name" -C "$tmp_dir"
    else
        tar xzf "$tmp_dir/$tarball_name" -C "$tmp_dir"
    fi

    local extracted_dir
    extracted_dir=$(ls -d "$tmp_dir"/node-v* 2>/dev/null | head -1)

    if [ ! -d "$extracted_dir" ]; then
        log_error "Extraction failed"
        rm -rf "$tmp_dir"
        exit 1
    fi

    # Place into ~/.clawke/node/
    rm -rf "$CLAWKE_HOME/node"
    mkdir -p "$CLAWKE_HOME"
    mv "$extracted_dir" "$CLAWKE_HOME/node"
    rm -rf "$tmp_dir"

    export PATH="$CLAWKE_HOME/node/bin:$PATH"
    NODE_CMD="$CLAWKE_HOME/node/bin/node"

    local installed_ver
    installed_ver=$("$NODE_CMD" --version 2>/dev/null)
    log_success "Node.js $installed_ver installed to ~/.clawke/node/"
    HAS_NODE=true
}

# ============================================================================
# Installation
# ============================================================================

clone_repo() {
    if [ "$LOCAL_MODE" = true ]; then
        # Local mode: copy or symlink from local project
        if [ -z "$LOCAL_SOURCE" ]; then
            log_error "--local specified but no source path found"
            exit 1
        fi

        log_info "Local mode: using $LOCAL_SOURCE"

        if [ "$INSTALL_DIR" = "$LOCAL_SOURCE" ]; then
            # Already pointing at the same directory
            log_success "Install dir is the source dir, skipping copy"
        elif [ -d "$INSTALL_DIR" ]; then
            log_info "Existing installation found at $INSTALL_DIR, updating from local..."
            # rsync for incremental update, exclude runtime artifacts
            rsync -a --delete \
                --exclude 'node_modules' \
                --exclude 'dist' \
                --exclude '.git' \
                --exclude 'build' \
                --exclude '.dart_tool' \
                --exclude 'server/data' \
                "$LOCAL_SOURCE/" "$INSTALL_DIR/"
            log_success "Updated from local source"
        else
            log_info "Copying project to $INSTALL_DIR..."
            mkdir -p "$(dirname "$INSTALL_DIR")"
            rsync -a \
                --exclude 'node_modules' \
                --exclude 'dist' \
                --exclude '.git' \
                --exclude 'build' \
                --exclude '.dart_tool' \
                --exclude 'server/data' \
                "$LOCAL_SOURCE/" "$INSTALL_DIR/"
            log_success "Copied from local source"
        fi

        cd "$INSTALL_DIR"
        log_success "Repository ready (local mode)"
        return 0
    fi

    log_info "Installing to $INSTALL_DIR..."

    if [ -d "$INSTALL_DIR" ]; then
        if [ -d "$INSTALL_DIR/.git" ]; then
            log_info "Existing installation found, updating..."
            cd "$INSTALL_DIR"

            local did_stash=false
            if [ -n "$(git status --porcelain)" ]; then
                local stash_name
                stash_name="clawke-install-autostash-$(date -u +%Y%m%d-%H%M%S)"
                log_info "Local changes detected, stashing before update..."
                git stash push --include-untracked -m "$stash_name"
                did_stash=true
            fi

            git fetch origin
            git checkout "$BRANCH"
            git pull --ff-only origin "$BRANCH"

            if [ "$did_stash" = true ]; then
                log_info "Restoring local changes..."
                if git stash pop; then
                    log_warn "Local changes restored on top of updated codebase."
                else
                    log_error "Restoring local changes failed. Your changes are in git stash."
                    log_info "Resolve manually: cd $INSTALL_DIR && git stash pop"
                fi
            fi
        else
            log_error "Directory exists but is not a git repository: $INSTALL_DIR"
            log_info "Remove it or choose a different directory with --dir"
            exit 1
        fi
    else
        # Try SSH first, fall back to HTTPS
        log_info "Trying SSH clone..."
        if GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5" \
           git clone --branch "$BRANCH" "$REPO_URL_SSH" "$INSTALL_DIR" 2>/dev/null; then
            log_success "Cloned via SSH"
        else
            rm -rf "$INSTALL_DIR" 2>/dev/null  # Clean up partial SSH clone
            log_info "SSH failed, trying HTTPS..."
            if git clone --branch "$BRANCH" "$REPO_URL_HTTPS" "$INSTALL_DIR"; then
                log_success "Cloned via HTTPS"
            else
                log_error "Failed to clone repository"
                exit 1
            fi
        fi
    fi

    cd "$INSTALL_DIR"
    log_success "Repository ready"
}

install_deps() {
    log_info "Installing server dependencies..."

    cd "$INSTALL_DIR/server"

    if [ ! -f "package.json" ]; then
        log_error "package.json not found in $INSTALL_DIR/server"
        exit 1
    fi

    # npm install triggers the `prepare` script which runs tsc
    if npm install --silent 2>&1; then
        log_success "Dependencies installed and TypeScript compiled"
    else
        log_warn "npm install had issues, retrying without --silent..."
        npm install || {
            log_error "npm install failed"
            log_info "Try running manually: cd $INSTALL_DIR/server && npm install"
            exit 1
        }
        log_success "Dependencies installed"
    fi

    # Verify the CLI entry point was compiled
    if [ ! -f "dist/cli/clawke.js" ]; then
        if [ "$SKIP_BUILD" = true ]; then
            log_warn "TypeScript not compiled (--skip-build). Run 'npm run build' in $INSTALL_DIR/server"
        else
            log_info "Building TypeScript..."
            npm run build || {
                log_error "TypeScript build failed"
                exit 1
            }
            log_success "TypeScript compiled"
        fi
    fi
}

setup_clawke_command() {
    log_info "Setting up clawke command..."

    # Find the Node.js binary to use
    local node_bin
    if [ -n "${NODE_CMD:-}" ]; then
        node_bin="$NODE_CMD"
    elif [ -x "$CLAWKE_HOME/node/bin/node" ]; then
        node_bin="$CLAWKE_HOME/node/bin/node"
    elif command -v node &> /dev/null; then
        node_bin="$(command -v node)"
    else
        log_error "Node.js not found — cannot create clawke command"
        return 1
    fi

    local cli_entry="$INSTALL_DIR/server/dist/cli/clawke.js"

    if [ ! -f "$cli_entry" ]; then
        log_warn "CLI entry point not found: $cli_entry"
        log_info "Run 'cd $INSTALL_DIR/server && npm run build' first"
        return 1
    fi

    local command_link_dir
    command_link_dir="$(get_command_link_dir)"
    mkdir -p "$command_link_dir"

    # Create wrapper script (not symlink) so it works even if node isn't on PATH
    cat > "$command_link_dir/clawke" << WRAPPER_EOF
#!/bin/bash
# Clawke CLI wrapper — auto-generated by install.sh
# Do not edit manually; re-run install.sh to update.
exec "$node_bin" "$cli_entry" "\$@"
WRAPPER_EOF
    chmod +x "$command_link_dir/clawke"
    log_success "Created clawke command at ~/.local/bin/clawke"

    # Ensure ~/.local/bin is on PATH
    if ! echo "$PATH" | tr ':' '\n' | grep -q "^$command_link_dir$"; then
        SHELL_CONFIGS=()
        IS_FISH=false
        LOGIN_SHELL="$(basename "${SHELL:-/bin/bash}")"
        case "$LOGIN_SHELL" in
            zsh)
                [ -f "$HOME/.zshrc" ] && SHELL_CONFIGS+=("$HOME/.zshrc")
                [ -f "$HOME/.zprofile" ] && SHELL_CONFIGS+=("$HOME/.zprofile")
                if [ ${#SHELL_CONFIGS[@]} -eq 0 ]; then
                    touch "$HOME/.zshrc"
                    SHELL_CONFIGS+=("$HOME/.zshrc")
                fi
                ;;
            bash)
                [ -f "$HOME/.bashrc" ] && SHELL_CONFIGS+=("$HOME/.bashrc")
                [ -f "$HOME/.bash_profile" ] && SHELL_CONFIGS+=("$HOME/.bash_profile")
                ;;
            fish)
                IS_FISH=true
                ;;
            *)
                [ -f "$HOME/.bashrc" ] && SHELL_CONFIGS+=("$HOME/.bashrc")
                [ -f "$HOME/.zshrc" ] && SHELL_CONFIGS+=("$HOME/.zshrc")
                ;;
        esac

        PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

        for SHELL_CONFIG in "${SHELL_CONFIGS[@]}"; do
            if ! grep -v '^[[:space:]]*#' "$SHELL_CONFIG" 2>/dev/null | grep -qE 'PATH=.*\.local/bin'; then
                echo "" >> "$SHELL_CONFIG"
                echo "# Clawke — ensure ~/.local/bin is on PATH" >> "$SHELL_CONFIG"
                echo "$PATH_LINE" >> "$SHELL_CONFIG"
                log_success "Added ~/.local/bin to PATH in $SHELL_CONFIG"
            fi
        done

        if [ "$IS_FISH" = "true" ]; then
            FISH_CONFIG="$HOME/.config/fish/config.fish"
            mkdir -p "$(dirname "$FISH_CONFIG")"
            touch "$FISH_CONFIG"
            if ! grep -q 'fish_add_path.*\.local/bin' "$FISH_CONFIG" 2>/dev/null; then
                echo "" >> "$FISH_CONFIG"
                echo "# Clawke — ensure ~/.local/bin is on PATH" >> "$FISH_CONFIG"
                echo 'fish_add_path "$HOME/.local/bin"' >> "$FISH_CONFIG"
                log_success "Added ~/.local/bin to PATH in $FISH_CONFIG"
            fi
        fi
    else
        log_info "~/.local/bin already on PATH"
    fi

    # Export for current session
    export PATH="$command_link_dir:$PATH"
    log_success "clawke command ready"
}

setup_config() {
    log_info "Setting up configuration..."

    mkdir -p "$CLAWKE_HOME"

    # Config file is auto-created on first server start via config.ts
    # But we can pre-copy the template for visibility
    if [ ! -f "$CLAWKE_HOME/clawke.json" ]; then
        local template="$INSTALL_DIR/server/config/clawke.json"
        if [ -f "$template" ]; then
            cp "$template" "$CLAWKE_HOME/clawke.json"
            log_success "Created ~/.clawke/clawke.json from template"
        fi
    else
        log_info "~/.clawke/clawke.json already exists"
    fi

    # Create data directory
    mkdir -p "$CLAWKE_HOME/data"

    log_success "Configuration directory ready: ~/.clawke/"
}

# ============================================================================
# Output
# ============================================================================

print_success() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│              ✓ Installation Complete!                   │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
    echo ""

    # File locations
    echo -e "${CYAN}${BOLD}📁 Your files:${NC}"
    echo ""
    echo -e "   ${YELLOW}Config:${NC}    ~/.clawke/clawke.json"
    echo -e "   ${YELLOW}Database:${NC}  ~/.clawke/data/clawke.db (created on first run)"
    echo -e "   ${YELLOW}Code:${NC}      ~/.clawke/clawke/"
    if [ -d "$CLAWKE_HOME/node" ]; then
        echo -e "   ${YELLOW}Node.js:${NC}   ~/.clawke/node/"
    fi
    echo ""

    echo -e "${CYAN}─────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}🚀 Commands:${NC}"
    echo ""
    echo -e "   ${GREEN}clawke server start${NC}           Start Clawke Server"
    echo -e "   ${GREEN}clawke gateway install${NC}        Install AI gateway plugin"
    echo -e "   ${GREEN}clawke --help${NC}                 Show all commands"
    echo ""

    echo -e "${CYAN}─────────────────────────────────────────────────────────${NC}"
    echo ""

    LOGIN_SHELL="$(basename "${SHELL:-/bin/bash}")"
    echo -e "${YELLOW}⚡ Reload your shell to use 'clawke' command:${NC}"
    echo ""
    if [ "$LOGIN_SHELL" = "zsh" ]; then
        echo "   source ~/.zshrc"
    elif [ "$LOGIN_SHELL" = "bash" ]; then
        echo "   source ~/.bashrc"
    elif [ "$LOGIN_SHELL" = "fish" ]; then
        echo "   source ~/.config/fish/config.fish"
    else
        echo "   source ~/.bashrc   # or ~/.zshrc"
    fi
    echo ""

    echo -e "${CYAN}${BOLD}📖 Quick Start:${NC}"
    echo ""
    echo "   1. Reload shell (above)"
    echo "   2. clawke gateway install    # Connect to your AI agent"
    echo "   3. clawke server start       # Start the server"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    print_banner

    detect_os
    check_git
    check_node

    clone_repo
    install_deps
    setup_clawke_command
    setup_config

    print_success
}

main
