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
POST_INSTALL_SETUP=true

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
        --no-post-install)
            POST_INSTALL_SETUP=false
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
            echo "  --no-post-install   Do not prompt for gateway/server startup after install"
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
    printf "%b\n" "${CYAN}→${NC} $1"
}

log_success() {
    printf "%b\n" "${GREEN}✓${NC} $1"
}

log_warn() {
    printf "%b\n" "${YELLOW}⚠${NC} $1"
}

log_error() {
    printf "%b\n" "${RED}✗${NC} $1"
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
        [ -z "$answer" ] && printf '\n'
    elif can_use_tty; then
        printf "%s %s " "$question" "$prompt_suffix" > /dev/tty
        IFS= read -r answer < /dev/tty || answer=""
        [ -z "$answer" ] && printf '\n'
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

prompt_yes_no_required() {
    local question="$1"
    local answer=""

    while true; do
        answer=""
        if [ "$IS_INTERACTIVE" = true ]; then
            read -r -p "$question [y/n] " answer || answer=""
            [ -z "$answer" ] && printf '\n'
        elif can_use_tty; then
            printf "%s [y/n] " "$question" > /dev/tty
            IFS= read -r answer < /dev/tty || answer=""
            [ -z "$answer" ] && printf '\n'
        else
            return 1
        fi

        answer="${answer#"${answer%%[![:space:]]*}"}"
        answer="${answer%"${answer##*[![:space:]]}"}"

        case "$answer" in
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO]) return 1 ;;
            *) log_warn "Please enter y or n." ;;
        esac
    done
}

get_command_link_dir() {
    echo "$HOME/.local/bin"
}

resolve_existing_dir() {
    local target="$1"
    [ -d "$target" ] || return 1
    (cd "$target" && pwd -P)
}

resolve_path() {
    local target="$1"
    local parent
    local base
    parent="$(dirname "$target")"
    base="$(basename "$target")"

    if [ -d "$parent" ]; then
        printf "%s/%s\n" "$(cd "$parent" && pwd -P)" "$base"
    else
        printf "%s\n" "$target"
    fi
}

is_path_inside() {
    local child="$1"
    local parent="$2"

    case "$child" in
        "$parent"|"$parent"/*) return 0 ;;
        *) return 1 ;;
    esac
}

assert_safe_local_sync_target() {
    local source="$1"
    local target="$2"
    local clawke_home="$3"

    [ "$source" != "$target" ] || return 0

    if [ -f "$target/.git" ]; then
        log_error "Refusing to sync local install into a linked Git worktree: $target"
        log_info "Use a dedicated install directory under $clawke_home, or set --dir to the source directory to skip copying."
        exit 1
    fi

    if [ -d "$target/.git" ] && ! is_path_inside "$target" "$clawke_home"; then
        log_error "Refusing to sync local install into a Git repository outside Clawke home: $target"
        log_info "Use a dedicated install directory under $clawke_home, or set --dir to the source directory to skip copying."
        exit 1
    fi
}

can_use_tty() {
    [ -r /dev/tty ] && [ -w /dev/tty ] || return 1
    { : < /dev/tty > /dev/tty; } 2>/dev/null
}

can_prompt() {
    [ "$IS_INTERACTIVE" = true ] || can_use_tty
}

run_clawke_command() {
    local clawke_cmd
    clawke_cmd="$(get_command_link_dir)/clawke"

    if [ ! -x "$clawke_cmd" ]; then
        log_warn "clawke command not found at $clawke_cmd"
        return 1
    fi

    if [ "$IS_INTERACTIVE" = true ]; then
        "$clawke_cmd" "$@"
    elif can_use_tty; then
        "$clawke_cmd" "$@" < /dev/tty
    else
        "$clawke_cmd" "$@"
    fi
}

run_clawke_command_record() {
    RUN_CLAWKE_COMMAND_OUTPUT=""
    local output_file
    output_file="$(mktemp "${TMPDIR:-/tmp}/clawke-command-output.XXXXXX")" || return 1

    run_clawke_command "$@" 2>&1 | tee "$output_file"
    local status="${PIPESTATUS[0]}"
    RUN_CLAWKE_COMMAND_OUTPUT="$(cat "$output_file")"
    rm -f "$output_file"
    return "$status"
}

sync_configured_local_gateways() {
    local clawke_cmd
    clawke_cmd="$(get_command_link_dir)/clawke"

    log_info "Updating configured local gateways..."
    if run_clawke_command gateway update --local-only; then
        log_success "Configured local gateways updated"
    else
        log_warn "Configured local gateway update did not complete. Run later: $clawke_cmd gateway update"
    fi
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

        if [ ! -d "$LOCAL_SOURCE" ]; then
            log_error "Local source not found: $LOCAL_SOURCE"
            exit 1
        fi

        # 规范化路径，避免相同目录因相对/绝对路径不同而误触发同步 — Normalize paths so identical directories do not sync by mistake
        LOCAL_SOURCE="$(resolve_existing_dir "$LOCAL_SOURCE")"
        INSTALL_DIR="$(resolve_path "$INSTALL_DIR")"
        CLAWKE_HOME="$(resolve_path "$CLAWKE_HOME")"

        if [ ! -f "$LOCAL_SOURCE/server/package.json" ] || [ ! -d "$LOCAL_SOURCE/gateways" ]; then
            log_error "Local source does not look like a Clawke checkout: $LOCAL_SOURCE"
            exit 1
        fi

        log_info "Local mode: using $LOCAL_SOURCE"

        if [ "$INSTALL_DIR" = "$LOCAL_SOURCE" ]; then
            # Already pointing at the same directory
            log_success "Install dir is the source dir, skipping copy"
        elif [ -d "$INSTALL_DIR" ]; then
            log_info "Existing installation found at $INSTALL_DIR, updating from local..."
            assert_safe_local_sync_target "$LOCAL_SOURCE" "$INSTALL_DIR" "$CLAWKE_HOME"
            # 禁止添加 --delete，错误的 INSTALL_DIR 会清空 worktree 或用户目录 — Do not add --delete; a wrong INSTALL_DIR can erase worktrees or user directories
            rsync -a \
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

install_builtin_skills() {
    log_info "Installing built-in skills..."

    local registry_path="$INSTALL_DIR/skills-registry.json"
    if [ ! -f "$registry_path" ]; then
        log_info "No skills registry found at $registry_path; skipping built-in skills"
        return 0
    fi

    local node_bin
    if [ -n "${NODE_CMD:-}" ]; then
        node_bin="$NODE_CMD"
    elif [ -x "$CLAWKE_HOME/node/bin/node" ]; then
        node_bin="$CLAWKE_HOME/node/bin/node"
    elif command -v node &> /dev/null; then
        node_bin="$(command -v node)"
    else
        log_warn "Node.js not found; skipping built-in skills"
        return 0
    fi

    INSTALL_DIR="$INSTALL_DIR" CLAWKE_HOME="$CLAWKE_HOME" "$node_bin" <<'NODE_HELPER'
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const installDir = process.env.INSTALL_DIR;
const clawkeHome = process.env.CLAWKE_HOME;
const registryPath = path.join(installDir, 'skills-registry.json');
const reposDir = path.join(clawkeHome, 'skill-repos');
const skillsDir = path.join(clawkeHome, 'skills');
const disabledDir = path.join(clawkeHome, 'disabled-skills');
const lockPath = path.join(clawkeHome, 'skills-lock.json');

const stats = {
  installed: 0,
  updated: 0,
  skipped: 0,
  conflicts: 0,
};

function info(message) {
  console.log(`→ ${message}`);
}

function warn(message) {
  console.log(`⚠ ${message}`);
}

function success(message) {
  console.log(`✓ ${message}`);
}

function runGit(args, cwd) {
  execFileSync('git', args, {
    cwd,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function gitOutput(args, cwd) {
  return execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

function gitRefExists(ref, cwd) {
  try {
    runGit(['rev-parse', '--verify', '--quiet', ref], cwd);
    return true;
  } catch (_) {
    return false;
  }
}

function readJson(filePath, fallback) {
  if (!fs.existsSync(filePath)) {
    return fallback;
  }
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function writeJson(filePath, data) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(data, null, 2)}\n`);
}

function safeSegment(value) {
  return String(value)
    .replace(/\.git$/i, '')
    .replace(/[^a-zA-Z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(-48) || 'repo';
}

function repoKey(url) {
  const hash = crypto.createHash('sha256').update(url).digest('hex').slice(0, 16);
  const parsed = safeSegment(path.basename(url));
  return `${parsed}-${hash}`;
}

function assertSafeRelativePath(value, label) {
  if (!value || path.isAbsolute(value) || value.split(/[\\/]+/).includes('..')) {
    throw new Error(`${label} must be a safe relative path`);
  }
}

function assertSafePathSegment(value, label) {
  if (!value || value === '.' || value === '..' || /[\\/]/.test(value)) {
    throw new Error(`${label} must be a single safe path segment`);
  }
}

function hashDirectory(dirPath) {
  const hash = crypto.createHash('sha256');

  function walk(current, relativeBase) {
    const entries = fs.readdirSync(current, { withFileTypes: true })
      .sort((a, b) => a.name.localeCompare(b.name));

    for (const entry of entries) {
      const absolute = path.join(current, entry.name);
      const relative = path.join(relativeBase, entry.name).split(path.sep).join('/');
      const stat = fs.lstatSync(absolute);

      if (entry.isDirectory()) {
        hash.update(`dir\0${relative}\0${stat.mode & 0o777}\0`);
        walk(absolute, relative);
      } else if (entry.isSymbolicLink()) {
        hash.update(`link\0${relative}\0${fs.readlinkSync(absolute)}\0`);
      } else if (entry.isFile()) {
        hash.update(`file\0${relative}\0${stat.mode & 0o777}\0`);
        hash.update(fs.readFileSync(absolute));
        hash.update('\0');
      }
    }
  }

  walk(dirPath, '');
  return hash.digest('hex');
}

function normalizeLock(rawLock) {
  const lock = rawLock && typeof rawLock === 'object' ? rawLock : {};
  if (!lock.version) {
    lock.version = 1;
  }
  if (!lock.skills || Array.isArray(lock.skills) || typeof lock.skills !== 'object') {
    lock.skills = {};
  }
  return lock;
}

function validateSkill(skill) {
  if (!skill || typeof skill !== 'object') {
    throw new Error('skill entry must be an object');
  }
  for (const key of ['id', 'category', 'name']) {
    if (!skill[key] || typeof skill[key] !== 'string') {
      throw new Error(`skill.${key} is required`);
    }
  }
  if (!skill.source || skill.source.type !== 'git') {
    throw new Error(`skill ${skill.name} source.type must be git`);
  }
  for (const key of ['url', 'ref', 'path']) {
    if (!skill.source[key] || typeof skill.source[key] !== 'string') {
      throw new Error(`skill ${skill.name} source.${key} is required`);
    }
  }
  assertSafePathSegment(skill.name, `skill ${skill.name} name`);
  assertSafeRelativePath(skill.source.path, `skill ${skill.name} source.path`);
}

function ensureRepo(source) {
  const cachePath = path.join(reposDir, repoKey(source.url));

  if (fs.existsSync(cachePath)) {
    if (!fs.existsSync(path.join(cachePath, '.git'))) {
      throw new Error(`repo cache exists but is not a git repo: ${cachePath}`);
    }
    runGit(['fetch', '--tags', '--prune', 'origin'], cachePath);
  } else {
    fs.mkdirSync(path.dirname(cachePath), { recursive: true });
    runGit(['clone', source.url, cachePath], installDir);
  }

  let checkoutRef = source.ref;
  if (source.ref === 'HEAD' && gitRefExists('refs/remotes/origin/HEAD', cachePath)) {
    checkoutRef = 'origin/HEAD';
  } else if (gitRefExists(`refs/remotes/origin/${source.ref}`, cachePath)) {
    checkoutRef = `origin/${source.ref}`;
  }

  runGit(['checkout', '--detach', checkoutRef], cachePath);

  const resolvedCommit = gitOutput(['rev-parse', 'HEAD'], cachePath);

  return { cachePath, resolvedCommit };
}

function copySkill(sourcePath, targetPath) {
  const tmpPath = `${targetPath}.tmp-${process.pid}`;
  fs.rmSync(tmpPath, { recursive: true, force: true });
  fs.cpSync(sourcePath, tmpPath, {
    recursive: true,
    preserveTimestamps: true,
    filter: (source) => path.basename(source) !== '.git',
  });
  fs.rmSync(targetPath, { recursive: true, force: true });
  fs.renameSync(tmpPath, targetPath);
}

function main() {
  const registry = readJson(registryPath, null);
  if (!registry || registry.version !== 1 || !Array.isArray(registry.skills)) {
    throw new Error('skills-registry.json must contain version=1 and skills[]');
  }

  fs.mkdirSync(reposDir, { recursive: true });
  fs.mkdirSync(skillsDir, { recursive: true });
  fs.mkdirSync(disabledDir, { recursive: true });

  const lock = normalizeLock(readJson(lockPath, { version: 1, skills: {} }));
  const duplicateNames = new Set();
  const seenNames = new Set();

  for (const skill of registry.skills) {
    if (skill && typeof skill.name === 'string') {
      if (seenNames.has(skill.name)) {
        duplicateNames.add(skill.name);
      }
      seenNames.add(skill.name);
    }
  }

  for (const skill of registry.skills) {
    try {
      validateSkill(skill);

      if (duplicateNames.has(skill.name)) {
        warn(`Conflict: duplicate built-in skill name "${skill.name}" in registry`);
        stats.conflicts += 1;
        continue;
      }

      const targetPath = path.join(skillsDir, skill.name);
      const disabledPath = path.join(disabledDir, skill.name);
      const locked = lock.skills[skill.name];

      if (fs.existsSync(disabledPath)) {
        warn(`Skipped disabled skill "${skill.name}" (left in disabled-skills)`);
        stats.skipped += 1;
        continue;
      }

      const targetExists = fs.existsSync(targetPath);
      let action = 'installed';
      if (targetExists) {
        const currentChecksum = hashDirectory(targetPath);
        if (!locked || locked.checksum !== currentChecksum) {
          warn(`Conflict: skill "${skill.name}" has local changes; skipping`);
          stats.conflicts += 1;
          continue;
        }
        action = 'updated';
      }

      const { cachePath, resolvedCommit } = ensureRepo(skill.source);
      const sourcePath = path.resolve(cachePath, skill.source.path);
      if (
        sourcePath !== cachePath &&
        !sourcePath.startsWith(`${cachePath}${path.sep}`)
      ) {
        throw new Error(`source path escapes repo for ${skill.name}: ${skill.source.path}`);
      }
      if (!fs.existsSync(sourcePath)) {
        throw new Error(`source path not found for ${skill.name}: ${skill.source.path}`);
      }
      if (!fs.statSync(sourcePath).isDirectory()) {
        throw new Error(`source path is not a directory for ${skill.name}: ${skill.source.path}`);
      }
      if (!fs.existsSync(path.join(sourcePath, 'SKILL.md'))) {
        throw new Error(`source path missing SKILL.md for ${skill.name}: ${skill.source.path}`);
      }

      copySkill(sourcePath, targetPath);
      const checksum = hashDirectory(targetPath);

      lock.skills[skill.name] = {
        category: skill.category,
        name: skill.name,
        sourceUrl: skill.source.url,
        ref: skill.source.ref,
        resolvedCommit,
        sourcePath: skill.source.path,
        installedPath: targetPath,
        checksum,
        installedAt: new Date().toISOString(),
      };

      stats[action] += 1;
      success(`${action === 'installed' ? 'Installed' : 'Updated'} skill "${skill.name}"`);
    } catch (error) {
      warn(`Conflict: ${error.message}`);
      stats.conflicts += 1;
    }
  }

  writeJson(lockPath, lock);
  info(`Built-in skills summary: installed=${stats.installed}, updated=${stats.updated}, skipped=${stats.skipped}, conflicts=${stats.conflicts}`);
}

main();
NODE_HELPER
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
    echo -e "   ${GREEN}clawke server stop${NC}            Stop Clawke Server"
    echo -e "   ${GREEN}clawke server restart${NC}         Restart Clawke Server"
    echo -e "   ${GREEN}clawke doctor${NC}                 Check local setup"
    echo -e "   ${GREEN}clawke gateway install${NC}        Install AI gateway plugin"
    echo -e "   ${GREEN}clawke --help${NC}                 Show all commands"
    echo ""

    echo -e "${CYAN}─────────────────────────────────────────────────────────${NC}"
    echo ""

    LOGIN_SHELL="$(basename "${SHELL:-/bin/bash}")"
    echo -e "${YELLOW}⚡ If 'clawke' is not found in this terminal, reload your shell:${NC}"
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
    echo "   1. clawke gateway install    # Connect to your AI agent"
    echo "   2. clawke server start       # Start the server"
    echo ""
}

run_post_install_setup() {
    if [ "$POST_INSTALL_SETUP" != true ]; then
        return 0
    fi

    local clawke_cmd
    clawke_cmd="$(get_command_link_dir)/clawke"

    echo -e "${CYAN}─────────────────────────────────────────────────────────${NC}"
    echo ""

    if ! can_prompt; then
        echo -e "${CYAN}${BOLD}▶ Continue now without reloading your shell:${NC}"
        echo ""
        echo "   $clawke_cmd gateway install"
        echo "   $clawke_cmd server start"
        echo ""
        return 0
    fi

    echo -e "${CYAN}${BOLD}▶ Continue setup now:${NC}"
    echo ""

    if prompt_yes_no "Install an AI gateway now?" "yes"; then
        while true; do
            log_info "Running: $clawke_cmd gateway install"
            if run_clawke_command_record gateway install; then
                case "$RUN_CLAWKE_COMMAND_OUTPUT" in
                    *"Gateway installation skipped."*)
                        break
                        ;;
                    *)
                        log_success "Gateway setup finished"
                        ;;
                esac
            else
                log_warn "Gateway setup did not complete. Run later: $clawke_cmd gateway install"
            fi
            echo ""

            if ! prompt_yes_no_required "Install another AI gateway?"; then
                break
            fi
            echo ""
        done
    else
        log_info "Gateway setup skipped. Run later: $clawke_cmd gateway install"
        echo ""
    fi

    if prompt_yes_no "Start Clawke Server now?" "yes"; then
        log_info "Starting Clawke Server. Press Ctrl+C to stop it."
        if ! run_clawke_command server start; then
            log_warn "Server did not start. Run later: $clawke_cmd server start"
        fi
    else
        log_info "Server start skipped. Run later: $clawke_cmd server start"
    fi
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
    install_builtin_skills
    sync_configured_local_gateways

    print_success
    run_post_install_setup
}

main
