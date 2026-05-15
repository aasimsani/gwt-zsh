# gwt - Git Worktree helper for Linear tickets and regular branches
# Usage: gwt [options] <branch-name>
#        gwt --config
#        gwt --list
#        gwt --update
#        gwt --version
#
# Options:
#   --config                  Configure all gwt settings (interactive)
#   --copy-config-dirs <dir>  Copy directory from repo root to worktree (repeatable)
#   --list                    List worktrees for this repo
#   --list-copy-dirs          List configured directories to copy
#   --prune                   Interactive worktree pruning
#   --setup-skill             Install Claude Code skill globally
#   --update                  Update gwt to the latest version
#   --version                 Show version information
#
# Environment Variables:
#   GWT_MAIN_BRANCH           Default base branch (default: "main")
#   GWT_COPY_DIRS             Comma-separated list of directories to always copy
#   GWT_ALIAS                 Alias for gwt command (default: "wt", set "" to disable)
#   GWT_NO_FZF                Set to 1 to disable fzf menus
#   GWT_POST_CREATE_CMD       Command to run after worktree creation
#
# Config Files (local overrides global, env vars override both):
#   Global: ~/.config/gwt/config
#   Local:  .gwt/config (per-repo)
#
# Examples:
#   gwt aasim/eng-1045-allow-changing-user-types  -> ../repo-eng-1045
#   gwt feature/add-new-dashboard-components      -> ../repo-add-new-dashboard
#   gwt --copy-config-dirs serena feature/branch  -> copies ./serena to worktree
#   gwt --config                                  -> interactive config menu

GWT_VERSION="1.6.0"
GWT_REPO="aasimsani/gwt-zsh"

# Store install directory when sourced (works with all plugin managers)
GWT_INSTALL_DIR="${0:A:h}"

# Load ZSH colors module (built-in)
autoload -U colors && colors

# =============================================================================
# Color Palette — Catppuccin Frappe (matches assets/demo.tape)
# =============================================================================

GWT_COLOR_PRIMARY="#ca9ee6"    # mauve    — headers, prompts, cursor
GWT_COLOR_ACCENT="#f4b8e4"     # pink     — selections, highlights, markers
GWT_COLOR_SUCCESS="#a6d189"    # green    — ✓, existing worktrees (●)
GWT_COLOR_DANGER="#e78284"     # red      — ✕, missing worktrees (○)
GWT_COLOR_WARN="#e5c890"       # yellow   — ⚠ warnings
GWT_COLOR_INFO="#8caaee"       # blue     — └─ tree, info paths
GWT_COLOR_HIGHLIGHT="#81c8be"  # teal     — current worktree marker
GWT_COLOR_DIM="#737994"        # overlay0 — secondary labels
GWT_COLOR_BORDER="#626880"     # surface2 — borders

# =============================================================================
# UI Backend Abstraction (gum > fzf > plain)
# =============================================================================
#
# Resolves which interactive UI backend to use for menus, prompts and confirms.
# Precedence (highest → lowest):
#   1. GWT_UI_BACKEND env/config (explicit override: gum | fzf | plain)
#   2. Non-TTY stdin                                              → plain
#   3. gum on PATH and GWT_NO_GUM unset                           → gum
#   4. fzf on PATH and GWT_NO_FZF unset                           → fzf
#   5. fallback                                                   → plain
#
# All helpers below dispatch to one of three branches with identical semantics
# so swapping backends never changes behavior — only presentation.

_gwt_ui_backend() {
    local override=""
    if typeset -f _gwt_config_resolve &>/dev/null; then
        override=$(_gwt_config_resolve "GWT_UI_BACKEND" "")
    else
        override="${GWT_UI_BACKEND:-}"
    fi
    case "$override" in
        gum|fzf|plain) echo "$override"; return ;;
    esac

    # Non-TTY → always plain (scripts, pipes)
    [[ ! -t 0 ]] && { echo plain; return; }

    local no_gum="" no_fzf=""
    if typeset -f _gwt_config_resolve &>/dev/null; then
        no_gum=$(_gwt_config_resolve "GWT_NO_GUM" "")
        no_fzf=$(_gwt_config_resolve "GWT_NO_FZF" "")
    else
        no_gum="${GWT_NO_GUM:-}"
        no_fzf="${GWT_NO_FZF:-}"
    fi

    if [[ -z "$no_gum" ]] && command -v gum &>/dev/null; then
        echo gum; return
    fi
    if [[ -z "$no_fzf" ]] && command -v fzf &>/dev/null; then
        echo fzf; return
    fi
    echo plain
}

# One-shot hint when gum would be preferred but isn't installed.
# Shown at most once per shell session, only when an interactive command runs.
_gwt_ui_hint_gum_missing() {
    [[ -n "$_GWT_GUM_HINT_SHOWN" ]] && return
    command -v gum &>/dev/null && return
    local no_gum=""
    if typeset -f _gwt_config_resolve &>/dev/null; then
        no_gum=$(_gwt_config_resolve "GWT_NO_GUM" "")
    else
        no_gum="${GWT_NO_GUM:-}"
    fi
    [[ -n "$no_gum" ]] && return
    _GWT_GUM_HINT_SHOWN=1
    print -P "%F{$GWT_COLOR_DIM}gwt: install %Bgum%b for a richer UI — %Bbrew install gum%b (or apt/scoop/pacman). Set GWT_NO_GUM=1 to silence.%f" >&2
}

# Single-select. Items passed as args. Prints chosen item to stdout.
# Usage: _gwt_ui_select_one "<header>" "<item1>" "<item2>" ...
_gwt_ui_select_one() {
    local header="$1"; shift
    local -a items=("$@")
    [[ ${#items[@]} -eq 0 ]] && return 1
    local backend=$(_gwt_ui_backend)

    case "$backend" in
        gum)
            printf '%s\n' "${items[@]}" | gum filter \
                --header="$header" \
                --indicator="▶" \
                --height=15 \
                --reverse=false 2>/dev/null
            ;;
        fzf)
            printf '%s\n' "${items[@]}" | fzf --no-multi \
                --header="$header" \
                --prompt="❯ " --pointer="▶" \
                --color="hl:$GWT_COLOR_PRIMARY,hl+:$GWT_COLOR_ACCENT,pointer:$GWT_COLOR_PRIMARY,prompt:$GWT_COLOR_PRIMARY,header:$GWT_COLOR_DIM,marker:$GWT_COLOR_ACCENT,fg+:$GWT_COLOR_HIGHLIGHT,info:$GWT_COLOR_INFO" \
                --reverse --height=40% \
                --bind='ctrl-k:up,ctrl-j:down'
            _gwt_ui_hint_gum_missing
            ;;
        plain)
            local i=1 item
            print -P "%F{$GWT_COLOR_DIM}$header%f" >&2
            for item in "${items[@]}"; do
                print -P "  %F{$GWT_COLOR_PRIMARY}$i)%f $item" >&2
                ((i++))
            done
            print -Pn "%F{$GWT_COLOR_PRIMARY}❯%f " >&2
            local choice
            read choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
                echo "${items[$choice]}"
            elif [[ -n "$choice" ]]; then
                # Pass non-numeric input through so callers preserving the
                # legacy numbered-menu UX (e.g. typed names, "q" for quit) can
                # handle it in their case statement, matching v1.x behavior.
                echo "$choice"
            fi
            _gwt_ui_hint_gum_missing
            ;;
    esac
}

# Multi-select. Prints newline-separated selections to stdout.
_gwt_ui_select_many() {
    local header="$1"; shift
    local -a items=("$@")
    [[ ${#items[@]} -eq 0 ]] && return 1
    local backend=$(_gwt_ui_backend)

    case "$backend" in
        gum)
            printf '%s\n' "${items[@]}" | gum filter \
                --no-limit \
                --header="$header" \
                --indicator="▶" \
                --selected-indicator="✓" \
                --height=15 2>/dev/null
            ;;
        fzf)
            printf '%s\n' "${items[@]}" | fzf --multi \
                --header="$header" \
                --prompt="❯ " --pointer="▶" --marker="✓" \
                --color="hl:$GWT_COLOR_PRIMARY,hl+:$GWT_COLOR_ACCENT,pointer:$GWT_COLOR_PRIMARY,prompt:$GWT_COLOR_PRIMARY,header:$GWT_COLOR_DIM,marker:$GWT_COLOR_ACCENT,fg+:$GWT_COLOR_HIGHLIGHT,info:$GWT_COLOR_INFO" \
                --reverse --height=50% \
                --bind='ctrl-k:up,ctrl-j:down'
            _gwt_ui_hint_gum_missing
            ;;
        plain)
            local i=1 item
            print -P "%F{$GWT_COLOR_DIM}$header%f" >&2
            print -P "%F{$GWT_COLOR_DIM}(space-separated numbers, 'all', or 'q' to cancel)%f" >&2
            for item in "${items[@]}"; do
                print -P "  %F{$GWT_COLOR_PRIMARY}$i)%f $item" >&2
                ((i++))
            done
            print -Pn "%F{$GWT_COLOR_PRIMARY}❯%f " >&2
            local input
            read input
            [[ "$input" == "q" ]] && return 0
            if [[ "$input" == "all" ]]; then
                printf '%s\n' "${items[@]}"
            else
                local num
                for num in ${=input}; do
                    if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#items[@]} )); then
                        echo "${items[$num]}"
                    fi
                done
            fi
            _gwt_ui_hint_gum_missing
            ;;
    esac
}

# Yes/no. Returns 0 (yes) or 1 (no/cancel).
_gwt_ui_confirm() {
    local msg="$1"
    local backend=$(_gwt_ui_backend)
    case "$backend" in
        gum)
            gum confirm "$msg"
            ;;
        *)
            print -Pn "  %F{$GWT_COLOR_PRIMARY}❯%f $msg (y/N): " >&2
            local answer
            read answer
            [[ "$answer" == "y" || "$answer" == "Y" ]]
            ;;
    esac
}

# Single-line input. Echoes typed value to stdout.
# Usage: _gwt_ui_input <prompt> [placeholder] [default]
_gwt_ui_input() {
    local prompt="$1"
    local placeholder="${2:-}"
    local default="${3:-}"
    local backend=$(_gwt_ui_backend)
    case "$backend" in
        gum)
            local -a args
            args=(--prompt="$prompt: ")
            [[ -n "$placeholder" ]] && args+=(--placeholder="$placeholder")
            [[ -n "$default" ]] && args+=(--value="$default")
            gum input "${args[@]}"
            ;;
        *)
            local hint=""
            [[ -n "$placeholder" ]] && hint=" %F{$GWT_COLOR_DIM}($placeholder)%f"
            print -Pn "  %F{$GWT_COLOR_PRIMARY}❯%f $prompt${hint}: " >&2
            local val
            read val
            if [[ -z "$val" && -n "$default" ]]; then
                echo "$default"
            else
                echo "$val"
            fi
            ;;
    esac
}

# Multi-line input (Ctrl+D submits under gum, single-line elsewhere).
_gwt_ui_write() {
    local prompt="$1"
    local placeholder="${2:-}"
    local backend=$(_gwt_ui_backend)
    case "$backend" in
        gum)
            local -a args
            args=(--header="$prompt (Ctrl+D to save)")
            [[ -n "$placeholder" ]] && args+=(--placeholder="$placeholder")
            gum write "${args[@]}"
            ;;
        *)
            _gwt_ui_input "$prompt" "$placeholder"
            ;;
    esac
}

# Directory picker (tree-style under gum, text input elsewhere).
_gwt_ui_pick_dir() {
    local prompt="$1"
    local base_dir="${2:-.}"
    local backend=$(_gwt_ui_backend)
    case "$backend" in
        gum)
            gum file --directory "$base_dir" --header="$prompt" 2>/dev/null
            ;;
        *)
            _gwt_ui_input "$prompt"
            ;;
    esac
}

# Run a command with a spinner (gum only; otherwise just runs the command).
# Usage: _gwt_ui_spin "<title>" -- <cmd> [args...]
_gwt_ui_spin() {
    local title="$1"; shift
    [[ "$1" == "--" ]] && shift
    local backend=$(_gwt_ui_backend)
    case "$backend" in
        gum)
            gum spin --spinner=dot --title="$title" -- "$@"
            ;;
        *)
            "$@"
            ;;
    esac
}

# Status log. Levels: success | warn | error | info.
_gwt_ui_log() {
    local level="$1"
    local msg="$2"
    local glyph color
    case "$level" in
        success) glyph="✓"; color="$GWT_COLOR_SUCCESS" ;;
        warn)    glyph="⚠"; color="$GWT_COLOR_WARN" ;;
        error)   glyph="✕"; color="$GWT_COLOR_DANGER" ;;
        info)    glyph="●"; color="$GWT_COLOR_INFO" ;;
        *)       glyph="●"; color="$GWT_COLOR_PRIMARY" ;;
    esac
    print -P "  %F{$color}$glyph%f $msg"
}

# Bold colored section header.
_gwt_ui_header() {
    print -P "%B%F{$GWT_COLOR_PRIMARY}$1%f%b"
}

# Auto-paginate stdin if it exceeds terminal height. gum only.
_gwt_ui_pager_if_long() {
    local content=$(cat)
    local lines=$(echo "$content" | wc -l | tr -d ' ')
    local no_pager=""
    if typeset -f _gwt_config_resolve &>/dev/null; then
        no_pager=$(_gwt_config_resolve "GWT_NO_PAGER" "")
    fi
    if (( lines > LINES - 5 )) && [[ "$(_gwt_ui_backend)" == gum ]] && [[ -z "$no_pager" ]]; then
        echo "$content" | gum pager
    else
        echo "$content"
    fi
}

# Pre-configure gum's per-command styling once at plugin load.
# Individual gum calls stay terse because these defaults apply globally.
if command -v gum &>/dev/null; then
    export GUM_FILTER_INDICATOR="▶"
    export GUM_FILTER_INDICATOR_FOREGROUND="$GWT_COLOR_PRIMARY"
    export GUM_FILTER_SELECTED_INDICATOR="✓"
    export GUM_FILTER_SELECTED_INDICATOR_FOREGROUND="$GWT_COLOR_ACCENT"
    export GUM_FILTER_HEADER_FOREGROUND="$GWT_COLOR_DIM"
    export GUM_FILTER_PROMPT="❯ "
    export GUM_FILTER_PROMPT_FOREGROUND="$GWT_COLOR_PRIMARY"
    export GUM_FILTER_MATCH_FOREGROUND="$GWT_COLOR_ACCENT"
    export GUM_FILTER_CURSOR_TEXT_FOREGROUND="$GWT_COLOR_HIGHLIGHT"
    export GUM_FILTER_TEXT_FOREGROUND=""
    export GUM_INPUT_PROMPT="❯ "
    export GUM_INPUT_PROMPT_FOREGROUND="$GWT_COLOR_PRIMARY"
    export GUM_INPUT_CURSOR_FOREGROUND="$GWT_COLOR_ACCENT"
    export GUM_INPUT_PLACEHOLDER_FOREGROUND="$GWT_COLOR_DIM"
    export GUM_CONFIRM_PROMPT_FOREGROUND="$GWT_COLOR_PRIMARY"
    export GUM_CONFIRM_SELECTED_BACKGROUND="$GWT_COLOR_PRIMARY"
    export GUM_CONFIRM_UNSELECTED_FOREGROUND="$GWT_COLOR_DIM"
    export GUM_SPIN_SPINNER="dot"
    export GUM_SPIN_SPINNER_FOREGROUND="$GWT_COLOR_PRIMARY"
    export GUM_SPIN_TITLE_FOREGROUND="$GWT_COLOR_DIM"
    export GUM_WRITE_HEADER_FOREGROUND="$GWT_COLOR_DIM"
    export GUM_WRITE_CURSOR_LINE_NUMBER_FOREGROUND="$GWT_COLOR_PRIMARY"
    export GUM_WRITE_PLACEHOLDER_FOREGROUND="$GWT_COLOR_DIM"
    export GUM_FILE_CURSOR_FOREGROUND="$GWT_COLOR_PRIMARY"
    export GUM_FILE_DIRECTORY_FOREGROUND="$GWT_COLOR_INFO"
fi

# Terminal formatting helpers
_gwt_print() {
    # Usage: _gwt_print "message" [color] [prefix_symbol]
    local msg="$1"
    local color="${2:-default}"
    local prefix="$3"

    local color_code=""
    case "$color" in
        green)  color_code="%F{green}" ;;
        red)    color_code="%F{red}" ;;
        yellow) color_code="%F{yellow}" ;;
        cyan)   color_code="%F{cyan}" ;;
        dim)    color_code="%F{240}" ;;
        bold)   color_code="%B" ;;
        *)      color_code="" ;;
    esac

    if [[ -n "$prefix" ]]; then
        print -P "  ${color_code}${prefix}%f %B${msg}%b"
    else
        print -P "  ${color_code}${msg}%f"
    fi
}

# Install Claude Code skill for gwt
_gwt_setup_skill() {
    local skill_source="$GWT_INSTALL_DIR/skills/gwt.md"
    local skill_dir="$HOME/.claude/skills/gwt"
    local skill_dest="$skill_dir/SKILL.md"

    if [[ ! -f "$skill_source" ]]; then
        _gwt_ui_log error "Could not find skill source at $skill_source"
        return 1
    fi

    local is_update=false
    if [[ -f "$skill_dest" ]]; then
        is_update=true
    fi

    mkdir -p "$skill_dir"
    cp "$skill_source" "$skill_dest"

    if $is_update; then
        _gwt_ui_log success "Skill updated at $skill_dest"
    else
        _gwt_ui_log success "Skill installed at $skill_dest"
    fi
    echo ""
    echo "Usage: Type /gwt in Claude Code to load gwt command reference."
}

# Update gwt to the latest version
_gwt_update() {
    local install_dir="$GWT_INSTALL_DIR"

    # Fallback detection if GWT_INSTALL_DIR wasn't set
    if [[ -z "$install_dir" || ! -d "$install_dir" ]]; then
        # Try common locations
        for dir in \
            "$HOME/.oh-my-zsh/custom/plugins/gwt" \
            "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/gwt" \
            "$HOME/.antigen/bundles/aasimsani/gwt-zsh" \
            "$HOME/.zplug/repos/aasimsani/gwt-zsh" \
            "$HOME/.zinit/plugins/aasimsani---gwt-zsh" \
            "$HOME/.local/share/zinit/plugins/aasimsani---gwt-zsh" \
            "$HOME/.zgenom/sources/aasimsani/gwt-zsh___main"
        do
            if [[ -d "$dir" ]]; then
                install_dir="$dir"
                break
            fi
        done
    fi

    if [[ -z "$install_dir" || ! -d "$install_dir" ]]; then
        echo "Error: Could not find gwt installation directory" >&2
        echo "Manual update: cd <install-dir> && git pull" >&2
        return 1
    fi

    echo "Updating gwt from $install_dir..."

    # Save current directory
    local orig_dir=$(pwd)

    cd "$install_dir" || return 1

    # Check if it's a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Installation directory is not a git repository" >&2
        cd "$orig_dir"
        return 1
    fi

    # Fetch and pull
    _gwt_ui_spin "Fetching latest..." -- git fetch origin

    local local_rev=$(git rev-parse HEAD)
    local remote_rev=$(git rev-parse origin/main)

    if [[ "$local_rev" == "$remote_rev" ]]; then
        echo "Already up to date (v$GWT_VERSION)"
    else
        echo "Updating..."
        git pull origin main

        # Unset old functions and reload
        echo "Reloading..."
        unset -f gwt _gwt_update _gwt_config _gwt_config_read _gwt_config_write _gwt_validate_dir _gwt_copy_dirs _gwt_prune 2>/dev/null
        source "$install_dir/gwt.plugin.zsh"

        echo "Updated to v$GWT_VERSION!"
    fi

    cd "$orig_dir"
}

# Security: Validate directory name to prevent path traversal and injection
_gwt_validate_dir() {
    local dir="$1"

    # Reject empty
    [[ -z "$dir" ]] && return 1

    # Reject path traversal (..)
    if [[ "$dir" == *".."* ]]; then
        echo "Error: Invalid directory '$dir' - path traversal not allowed" >&2
        return 1
    fi

    # Reject absolute paths
    if [[ "$dir" == /* ]]; then
        echo "Error: Invalid directory '$dir' - absolute paths not allowed" >&2
        return 1
    fi

    # Reject shell metacharacters and quotes (security)
    # Only allow: alphanumeric, dash, underscore, dot, forward slash
    if [[ ! "$dir" =~ ^[a-zA-Z0-9_./-]+$ ]]; then
        echo "Error: Invalid directory '$dir' - special characters not allowed" >&2
        return 1
    fi

    return 0
}

# Security: Validate branch name to prevent injection attacks
_gwt_validate_branch() {
    local branch="$1"

    # Reject empty
    [[ -z "$branch" ]] && return 1

    # Reject path traversal (..)
    if [[ "$branch" == *".."* ]]; then
        echo "Error: Invalid branch '$branch' - path traversal not allowed" >&2
        return 1
    fi

    # Reject shell metacharacters and quotes (security)
    # Only allow: alphanumeric, dash, underscore, dot, forward slash
    if [[ ! "$branch" =~ ^[a-zA-Z0-9_./-]+$ ]]; then
        echo "Error: Invalid branch '$branch' - special characters not allowed" >&2
        return 1
    fi

    return 0
}

# Get the configured main branch name (default: "main")
# Uses layered config: env var > local .gwt/config > global ~/.config/gwt/config > "main"
_gwt_get_main_branch() {
    _gwt_config_resolve "GWT_MAIN_BRANCH" "main"
}

# Read GWT_MAIN_BRANCH from zshrc file
_gwt_config_read_main() {
    local zshrc="${1:-$HOME/.zshrc}"
    if [[ -f "$zshrc" ]]; then
        grep -E '^export GWT_MAIN_BRANCH=' "$zshrc" 2>/dev/null | sed 's/^export GWT_MAIN_BRANCH="//' | sed 's/"$//'
    fi
}

# =============================================================================
# Layered Config System (global + local config files)
# =============================================================================

# Read a key from a config file (KEY=VALUE format, supports # comments)
_gwt_config_read_file() {
    local key="$1"
    local config_file="$2"

    [[ ! -f "$config_file" ]] && return 0

    local line value
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        # Match KEY=VALUE (with optional quotes)
        if [[ "$line" =~ ^${key}=(.*) ]]; then
            value="${match[1]}"
            # Strip surrounding quotes if present
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            echo "$value"
            return 0
        fi
    done < "$config_file"
}

# Write a key to a config file (creates parent dirs if needed)
# Use --keep-empty flag to write KEY= instead of removing the key
_gwt_config_write_file() {
    local key="$1"
    local value="$2"
    local config_file="$3"
    local keep_empty=false

    if [[ "$4" == "--keep-empty" ]]; then
        keep_empty=true
    fi

    # Security: Sanitize value - remove backticks and dollar signs
    value=$(echo "$value" | tr -d '`$\\')

    # Create parent directories if needed
    local parent_dir="${config_file:h}"
    [[ ! -d "$parent_dir" ]] && mkdir -p "$parent_dir"

    # Create file if it doesn't exist
    [[ ! -f "$config_file" ]] && touch "$config_file"

    # Remove existing key line
    if grep -q "^${key}=" "$config_file" 2>/dev/null; then
        local grep_exit=0
        grep -v "^${key}=" "$config_file" > "$config_file.tmp" 2>/dev/null || grep_exit=$?
        if [[ $grep_exit -le 1 ]]; then
            mv "$config_file.tmp" "$config_file"
        else
            rm -f "$config_file.tmp"
            return 1
        fi
    fi

    # Add new line
    if [[ -n "$value" ]]; then
        echo "${key}=${value}" >> "$config_file"
    elif $keep_empty; then
        echo "${key}=" >> "$config_file"
    fi
}

# Resolve a config value with layered priority: env > local > global > default
_gwt_config_resolve() {
    local key="$1"
    local default="$2"

    # 1. Environment variable (highest priority)
    local env_val="${(P)key}"
    if [[ -n "$env_val" ]]; then
        echo "$env_val"
        return 0
    fi

    # 2. Local .gwt/config (per-repo)
    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$repo_root" && -f "$repo_root/.gwt/config" ]]; then
        local local_val
        local_val=$(_gwt_config_read_file "$key" "$repo_root/.gwt/config")
        if [[ -n "$local_val" ]]; then
            echo "$local_val"
            return 0
        fi
    fi

    # 3. Global config (~/.config/gwt/config)
    local global_config="${XDG_CONFIG_HOME:-$HOME/.config}/gwt/config"
    if [[ -f "$global_config" ]]; then
        local global_val
        global_val=$(_gwt_config_read_file "$key" "$global_config")
        if [[ -n "$global_val" ]]; then
            echo "$global_val"
            return 0
        fi
    fi

    # 4. Default
    echo "$default"
}

# Auto-migrate GWT_* settings from ~/.zshrc to ~/.config/gwt/config
_gwt_migrate_config() {
    local zshrc="$HOME/.zshrc"
    local global_config="${XDG_CONFIG_HOME:-$HOME/.config}/gwt/config"

    # Skip if no zshrc
    [[ ! -f "$zshrc" ]] && return 0

    # Skip if no GWT_* exports in zshrc
    grep -q '^export GWT_' "$zshrc" 2>/dev/null || return 0

    # Skip if global config already exists (don't overwrite)
    if [[ -f "$global_config" ]]; then
        # Still show deprecation warning if zshrc has GWT vars (once per session)
        if [[ -z "$_GWT_MIGRATE_WARNED" ]]; then
            print -P "%F{$GWT_COLOR_WARN}gwt:%f you can now remove GWT_* exports from ~/.zshrc (deprecated)" >&2
            _GWT_MIGRATE_WARNED=1
        fi
        return 0
    fi

    # Create global config directory
    mkdir -p "${global_config:h}"

    # Extract and migrate each GWT_* export
    local line key value
    while IFS= read -r line; do
        if [[ "$line" =~ ^export\ (GWT_[A-Z_]+)=\"(.*)\"$ ]]; then
            key="${match[1]}"
            value="${match[2]}"
            echo "${key}=${value}" >> "$global_config"
        fi
    done < <(grep '^export GWT_' "$zshrc")

    print -P "%F{$GWT_COLOR_WARN}gwt:%f migrated settings to ~/.config/gwt/config" >&2
    print -P "%F{$GWT_COLOR_WARN}gwt:%f you can now remove GWT_* exports from ~/.zshrc (deprecated)" >&2
    _GWT_MIGRATE_WARNED=1
}

# =============================================================================
# Worktree Metadata Functions (for base branch tracking)
# =============================================================================

# Store base branch metadata for a worktree
# Usage: _gwt_metadata_set <base_branch> <base_worktree_path>
# Must be called from within the worktree directory
_gwt_metadata_set() {
    local base_branch="$1"
    local base_path="$2"

    # Enable worktree-specific config
    git config extensions.worktreeConfig true 2>/dev/null

    # Ensure core.bare=false in this worktree's config.worktree
    # Protects against config.worktree deletion leaking core.bare=true from shared config
    git config --worktree core.bare false 2>/dev/null

    # Also protect the main worktree's config.worktree
    local git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
    if [[ -n "$git_common_dir" && "$git_common_dir" != ".git" ]]; then
        local main_config_worktree="$git_common_dir/config.worktree"
        if [[ ! -f "$main_config_worktree" ]]; then
            echo "[core]" > "$main_config_worktree"
            echo "	bare = false" >> "$main_config_worktree"
        fi
    fi

    # Store metadata in worktree-local config
    git config --worktree gwt.baseBranch "$base_branch"
    git config --worktree gwt.baseWorktreePath "$base_path"
}

# Get metadata value for the current worktree
# Usage: _gwt_metadata_get <key>  (key: baseBranch or baseWorktreePath)
_gwt_metadata_get() {
    local key="$1"
    git config --worktree "gwt.$key" 2>/dev/null
}

# Clear all gwt metadata from the current worktree
_gwt_metadata_clear() {
    git config --worktree --unset gwt.baseBranch 2>/dev/null
    git config --worktree --unset gwt.baseWorktreePath 2>/dev/null
}

# Check and repair missing config.worktree when extensions.worktreeConfig is enabled
# Prevents core.bare=true leak from shared config after config.worktree deletion
_gwt_health_check() {
    # Only check if extensions.worktreeConfig is enabled
    local wt_config=$(git config extensions.worktreeConfig 2>/dev/null)
    [[ "$wt_config" != "true" ]] && return 0

    # Determine the config.worktree path for current worktree
    local git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 0
    local config_worktree="$git_dir/config.worktree"

    if [[ ! -f "$config_worktree" ]]; then
        # Recreate with core.bare=false to prevent bare repo leak
        git config --worktree core.bare false 2>/dev/null
        print -P "%F{$GWT_COLOR_WARN}gwt:%f repaired missing config.worktree (set core.bare=false)"
    fi
}

# =============================================================================
# Worktree Registry Functions (for querying dependents)
# =============================================================================

# Add a worktree to the central registry
# Usage: _gwt_registry_add <worktree_name> <base_branch> <base_path>
# Must be called from the main repo directory
_gwt_registry_add() {
    local wt_name="$1"
    local base_branch="$2"
    local base_path="$3"

    git config "gwt.registry.$wt_name.baseBranch" "$base_branch"
    git config "gwt.registry.$wt_name.basePath" "$base_path"
}

# Remove a worktree from the central registry
# Usage: _gwt_registry_remove <worktree_name>
_gwt_registry_remove() {
    local wt_name="$1"

    git config --unset "gwt.registry.$wt_name.baseBranch" 2>/dev/null
    git config --unset "gwt.registry.$wt_name.basePath" 2>/dev/null
}

# Get all worktrees that depend on a given branch
# Usage: _gwt_registry_get_dependents <branch_name>
# Returns: newline-separated list of worktree names
_gwt_registry_get_dependents() {
    local branch="$1"
    local result=""

    # Get all registry entries and filter by base branch
    # Note: git config normalizes keys to lowercase, so baseBranch becomes basebranch
    git config --get-regexp '^gwt\.registry\..*\.basebranch$' 2>/dev/null | while read -r key value; do
        if [[ "$value" == "$branch" ]]; then
            # Extract worktree name from key: gwt.registry.<name>.basebranch
            local wt_name=$(echo "$key" | sed 's/^gwt\.registry\.//' | sed 's/\.basebranch$//')
            echo "$wt_name"
        fi
    done
}

# =============================================================================
# Worktree Navigation Functions
# =============================================================================

# Navigate to the base worktree of the current worktree
# Returns: 0 on success, 1 on error
_gwt_navigate_base() {
    # Get base worktree path from metadata
    local base_path=$(_gwt_metadata_get "baseWorktreePath")

    if [[ -z "$base_path" ]]; then
        print -P "%F{$GWT_COLOR_DANGER}Error: No base worktree tracked for this worktree%f" >&2
        print -P "%F{$GWT_COLOR_DIM}This worktree was not created with --stack or --from%f" >&2
        return 1
    fi

    # Check if base worktree still exists
    if [[ ! -d "$base_path" ]]; then
        local base_branch=$(_gwt_metadata_get "baseBranch")
        print -P "%F{$GWT_COLOR_DANGER}Error: Base worktree no longer exists%f" >&2
        print -P "%F{$GWT_COLOR_DIM}Base branch: $base_branch%f" >&2
        print -P "%F{$GWT_COLOR_DIM}Expected path: $base_path%f" >&2
        return 1
    fi

    # Navigate to base worktree
    cd "$base_path"
    return 0
}

# Navigate to the main worktree (ultimate root) of this repository
# Uses git rev-parse --git-common-dir to find the shared .git directory
# Returns: 0 on success, 1 on error
_gwt_navigate_root() {
    local git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)

    if [[ -z "$git_common_dir" ]]; then
        print -P "%F{$GWT_COLOR_DANGER}Error: Not in a git repository%f" >&2
        return 1
    fi

    # If git-common-dir returns relative ".git", we're already in main worktree
    if [[ "$git_common_dir" == ".git" ]]; then
        print -P "%F{$GWT_COLOR_DIM}Already in main worktree%f"
        return 0
    fi

    # Get parent directory of .git (the main worktree path)
    local main_worktree="${git_common_dir:h}"

    # Verify the main worktree exists
    if [[ ! -d "$main_worktree" ]]; then
        print -P "%F{$GWT_COLOR_DANGER}Error: Main worktree no longer exists%f" >&2
        print -P "%F{$GWT_COLOR_DIM}Expected path: $main_worktree%f" >&2
        return 1
    fi

    # Navigate to main worktree
    cd "$main_worktree"
    return 0
}

# Show information about the current worktree's stack relationships
_gwt_show_info() {
    local current_branch=$(git branch --show-current 2>/dev/null)
    local worktree_path=$(pwd)

    echo ""
    _gwt_ui_header "Worktree Info"
    echo ""

    # Current branch
    print -P "  %F{$GWT_COLOR_SUCCESS}●%f Branch: %B$current_branch%b"
    print -P "  %F{$GWT_COLOR_DIM}  Path: $worktree_path%f"
    echo ""

    # Main worktree info (ultimate root)
    local git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
    if [[ -n "$git_common_dir" && "$git_common_dir" != ".git" ]]; then
        local main_worktree="${git_common_dir:h}"
        _gwt_ui_header "Main Worktree"
        print -P "  %F{$GWT_COLOR_DIM}(use %Bgwt ...%b or %Bgwt --root%b to navigate)%f"
        echo ""
        print -P "  %F{$GWT_COLOR_SUCCESS}●%f Path: %B$main_worktree%b"
        echo ""
    fi

    # Base worktree info (immediate parent)
    local base_branch=$(_gwt_metadata_get "baseBranch")
    local base_path=$(_gwt_metadata_get "baseWorktreePath")

    if [[ -n "$base_branch" ]]; then
        _gwt_ui_header "Base Worktree"
        print -P "  %F{$GWT_COLOR_DIM}(use %Bgwt ..%b or %Bgwt --base%b to navigate)%f"
        echo ""
        if [[ -d "$base_path" ]]; then
            print -P "  %F{$GWT_COLOR_SUCCESS}●%f Branch: %B$base_branch%b"
            print -P "  %F{$GWT_COLOR_DIM}  Path: $base_path%f"
        else
            print -P "  %F{$GWT_COLOR_DANGER}○%f Branch: %B$base_branch%b %F{$GWT_COLOR_DANGER}(missing)%f"
            print -P "  %F{$GWT_COLOR_DIM}  Path: $base_path (not found)%f"
        fi
        echo ""
    else
        print -P "%F{$GWT_COLOR_DIM}  Base: not tracked (worktree was not created with --stack or --from)%f"
        echo ""
    fi

    # Dependents (worktrees that have this as their base)
    local dependents=$(_gwt_registry_get_dependents "$current_branch")
    if [[ -n "$dependents" ]]; then
        _gwt_ui_header "Dependents"
        print -P "  %F{$GWT_COLOR_DIM}(worktrees based on this branch)%f"
        echo ""
        echo "$dependents" | while read -r dep; do
            if [[ -n "$dep" ]]; then
                print -P "  %F{$GWT_COLOR_INFO}├─%f $dep"
            fi
        done
        echo ""
    fi

    return 0
}

# =============================================================================
# Dependency-Aware Prune Functions
# =============================================================================

# Get count of worktrees that depend on a given branch
# Usage: _gwt_get_dependents_count <branch_name>
# Returns: count as string (can be used in arithmetic)
_gwt_get_dependents_count() {
    local branch="$1"
    local count=0

    local dependents=$(_gwt_registry_get_dependents "$branch")
    if [[ -n "$dependents" ]]; then
        count=$(echo "$dependents" | wc -l | tr -d ' ')
    fi

    echo "$count"
}

# Prune a single worktree and clean up its registry entry
# Usage: _gwt_prune_worktree <worktree_path>
_gwt_prune_worktree() {
    local wt_path="$1"
    local wt_name=$(basename "$wt_path")

    # Remove from git worktree
    git worktree remove --force "$wt_path" 2>/dev/null

    # Clean up registry entry
    _gwt_registry_remove "$wt_name"

    return 0
}

# Cascade delete: remove a branch's dependents recursively
# Usage: _gwt_prune_cascade <branch_name>
_gwt_prune_cascade() {
    local branch="$1"
    local repo_root=$(git rev-parse --show-toplevel)
    local repo_parent=$(dirname "$repo_root")

    local dependents=$(_gwt_registry_get_dependents "$branch")
    if [[ -n "$dependents" ]]; then
        echo "$dependents" | while read -r dep_name; do
            if [[ -n "$dep_name" ]]; then
                local dep_path="$repo_parent/$dep_name"
                if [[ -d "$dep_path" ]]; then
                    # Get the branch of this dependent for recursive cascade
                    local dep_branch=$(cd "$dep_path" 2>/dev/null && git branch --show-current 2>/dev/null)

                    # First, recursively cascade this dependent's dependents
                    if [[ -n "$dep_branch" ]]; then
                        _gwt_prune_cascade "$dep_branch"
                    fi

                    # Then remove this dependent
                    _gwt_prune_worktree "$dep_path"
                fi
            fi
        done
    fi
}

# Read GWT_COPY_DIRS (backward compat — delegates to layered config or reads from zshrc)
_gwt_config_read() {
    local zshrc="${1:-}"
    # If explicit path given (tests), read from that file directly
    if [[ -n "$zshrc" && -f "$zshrc" ]]; then
        grep -E '^export GWT_COPY_DIRS=' "$zshrc" 2>/dev/null | sed 's/^export GWT_COPY_DIRS="//' | sed 's/"$//'
        return
    fi
    # Otherwise use layered config
    _gwt_config_resolve "GWT_COPY_DIRS" ""
}

# Write GWT_COPY_DIRS to zshrc file (with sanitization)
_gwt_config_write() {
    local zshrc="${1:-$HOME/.zshrc}"
    local value="$2"

    # Security: Sanitize value - remove any quotes and dangerous characters
    value=$(echo "$value" | tr -d '"'"'"'`$\\')

    # Validate each directory in the comma-separated list
    if [[ -n "$value" ]]; then
        local -a validated=()
        IFS=',' read -rA dirs <<< "$value"
        for dir in "${dirs[@]}"; do
            if _gwt_validate_dir "$dir" 2>/dev/null; then
                validated+=("$dir")
            fi
        done
        value=$(IFS=','; echo "${validated[*]}")
    fi

    # Create file if it doesn't exist
    [[ ! -f "$zshrc" ]] && touch "$zshrc"

    # Remove existing GWT_COPY_DIRS line (use temp file for portability)
    if grep -q '^export GWT_COPY_DIRS=' "$zshrc" 2>/dev/null; then
        # grep -v returns 0 if lines selected, 1 if no lines (valid when removing only line), >1 on error
        # Use || to prevent errexit from triggering on expected grep exit code 1
        local grep_exit=0
        grep -v '^export GWT_COPY_DIRS=' "$zshrc" > "$zshrc.tmp" 2>/dev/null || grep_exit=$?
        if [[ $grep_exit -le 1 ]]; then
            # Verify temp file is valid before replacing (empty is OK if original had only 1 line)
            if [[ -s "$zshrc.tmp" ]] || [[ ! -s "$zshrc" ]] || [[ $(wc -l < "$zshrc") -eq 1 ]]; then
                mv "$zshrc.tmp" "$zshrc"
            else
                echo "Error: Failed to safely update $zshrc" >&2
                rm -f "$zshrc.tmp"
                return 1
            fi
        else
            rm -f "$zshrc.tmp"
            echo "Error: Failed to update $zshrc" >&2
            return 1
        fi
    fi

    # Add new line if value is not empty
    if [[ -n "$value" ]]; then
        echo "export GWT_COPY_DIRS=\"$value\"" >> "$zshrc"
    fi
}

# Interactive config sub-menu for copy directories
_gwt_config_copy_dirs() {
    local config_file="$1"

    while true; do
        local current=$(_gwt_config_read_file "GWT_COPY_DIRS" "$config_file")

        local header="Copy Directories"
        [[ -n "$current" ]] && header="Copy Directories ─ Current: $current"

        local choice
        choice=$(_gwt_ui_select_one "$header" \
            "● Add directory" \
            "● Remove directory" \
            "● List directories" \
            "● Back")
        choice="${choice#● }"

        case "$choice" in
            "Add directory")
                local new_dir=""
                # Under gum, use the tree-style directory picker rooted at repo root (or cwd)
                if [[ "$(_gwt_ui_backend)" == gum ]] && command -v gum &>/dev/null; then
                    local repo_root
                    repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
                    [[ -z "$repo_root" ]] && repo_root="$(pwd)"
                    local picked
                    picked=$(gum file --directory "$repo_root" \
                        --header="Select directory to copy to new worktrees (ESC to type a path instead)" 2>/dev/null)
                    if [[ -n "$picked" ]]; then
                        # Convert to repo-relative if inside repo
                        if [[ "$picked" == "$repo_root"/* ]]; then
                            new_dir="${picked#$repo_root/}"
                        else
                            new_dir="$picked"
                        fi
                    fi
                fi
                # Fallback / non-gum / ESC from picker: text input
                if [[ -z "$new_dir" ]]; then
                    new_dir=$(_gwt_ui_input "Directory to add" ".vscode")
                fi
                if [[ -n "$new_dir" ]]; then
                    if ! _gwt_validate_dir "$new_dir"; then
                        continue
                    fi
                    if [[ -n "$current" ]]; then
                        if [[ ",$current," == *",$new_dir,"* ]]; then
                            _gwt_ui_log warn "Directory '$new_dir' already configured"
                        else
                            _gwt_config_write_file "GWT_COPY_DIRS" "$current,$new_dir" "$config_file"
                            export GWT_COPY_DIRS="$current,$new_dir"
                            _gwt_ui_log success "Added '$new_dir'"
                        fi
                    else
                        _gwt_config_write_file "GWT_COPY_DIRS" "$new_dir" "$config_file"
                        export GWT_COPY_DIRS="$new_dir"
                        _gwt_ui_log success "Added '$new_dir'"
                    fi
                fi
                ;;
            "Remove directory")
                if [[ -z "$current" ]]; then
                    print -P "  %F{$GWT_COLOR_DIM}No directories to remove%f"
                else
                    local -a dirs_array
                    IFS=',' read -rA dirs_array <<< "$current"
                    local selected=""
                    # Under gum/fzf: pick from the list (multi-select fuzzy).
                    # Under plain: preserve legacy v1.x UX — type the directory
                    # name to remove (one at a time).
                    if [[ "$(_gwt_ui_backend)" == plain ]]; then
                        selected=$(_gwt_ui_input "Directory to remove")
                    else
                        selected=$(_gwt_ui_select_many "Select directories to remove" "${dirs_array[@]}")
                    fi
                    if [[ -n "$selected" ]]; then
                        local new_list="$current"
                        while IFS= read -r rem_dir; do
                            [[ -z "$rem_dir" ]] && continue
                            local escaped_dir=$(printf '%s' "$rem_dir" | sed 's/[[\.*^$/+?{}()|]/\\&/g')
                            new_list=$(echo "$new_list" | tr ',' '\n' | grep -v "^${escaped_dir}$" | tr '\n' ',' | sed 's/,$//')
                            _gwt_ui_log success "Removed '$rem_dir'"
                        done <<< "$selected"
                        _gwt_config_write_file "GWT_COPY_DIRS" "$new_list" "$config_file"
                        export GWT_COPY_DIRS="$new_list"
                    fi
                fi
                ;;
            "List directories")
                if [[ -n "$current" ]]; then
                    print -P "%BConfigured directories:%b"
                    echo "$current" | tr ',' '\n' | while read -r dir; do
                        print -P "  %F{$GWT_COLOR_SUCCESS}●%f $dir"
                    done
                else
                    print -P "  %F{$GWT_COLOR_DIM}No directories configured%f"
                fi
                ;;
            "Back"|"")
                return 0
                ;;
            *)
                _gwt_ui_log error "Invalid choice"
                ;;
        esac
    done
}

# Config sub-menu for main branch
_gwt_config_main_branch() {
    local config_file="$1"
    local current=$(_gwt_config_read_file "GWT_MAIN_BRANCH" "$config_file")
    print -P "  %F{$GWT_COLOR_DIM}Current main branch: ${current:-main (default)}%f"
    local new_branch
    new_branch=$(_gwt_ui_input "New main branch (empty to reset to default)" "main")
    if [[ -z "$new_branch" || "$new_branch" == "main" ]]; then
        _gwt_config_write_file "GWT_MAIN_BRANCH" "" "$config_file"
        unset GWT_MAIN_BRANCH
        _gwt_ui_log success "Reset to default (main)"
    elif [[ "$new_branch" =~ [[:space:]] || "$new_branch" =~ [\~\^:\\\*\?\[] ]]; then
        _gwt_ui_log error "Invalid branch name - no spaces or special characters allowed"
    else
        _gwt_config_write_file "GWT_MAIN_BRANCH" "$new_branch" "$config_file"
        export GWT_MAIN_BRANCH="$new_branch"
        _gwt_ui_log success "Main branch set to '$new_branch'"
    fi
}

# Config sub-menu for alias
_gwt_config_alias() {
    local config_file="$1"
    local current=$(_gwt_config_read_file "GWT_ALIAS" "$config_file")
    local has_key=false
    grep -q '^GWT_ALIAS=' "$config_file" 2>/dev/null && has_key=true

    if $has_key; then
        if [[ -n "$current" ]]; then
            print -P "  %F{$GWT_COLOR_DIM}Current alias: $current%f"
        else
            print -P "  %F{$GWT_COLOR_DIM}Alias: disabled%f"
        fi
    else
        print -P "  %F{$GWT_COLOR_DIM}Current alias: wt (default)%f"
    fi

    local sub_choice
    sub_choice=$(_gwt_ui_select_one "Alias action" \
        "● Set custom alias" \
        "● Disable alias" \
        "● Reset to default (wt)")
    sub_choice="${sub_choice#● }"

    case "$sub_choice" in
        "Set custom alias")
            local new_alias
            new_alias=$(_gwt_ui_input "New alias" "wt")
            if [[ -n "$new_alias" && ! "$new_alias" =~ [[:space:]] ]]; then
                _gwt_config_write_file "GWT_ALIAS" "$new_alias" "$config_file"
                export GWT_ALIAS="$new_alias"
                _gwt_ui_log success "Alias set to '$new_alias' (restart shell to apply)"
            else
                _gwt_ui_log error "Invalid alias"
            fi
            ;;
        "Disable alias")
            # Write empty value explicitly (GWT_ALIAS= means "no alias")
            _gwt_config_write_file "GWT_ALIAS" "" "$config_file" --keep-empty
            export GWT_ALIAS=""
            _gwt_ui_log success "Alias disabled (restart shell to apply)"
            ;;
        "Reset to default (wt)")
            # Remove the key entirely (unset = use default "wt")
            _gwt_config_write_file "GWT_ALIAS" "" "$config_file"
            unset GWT_ALIAS
            _gwt_ui_log success "Reset to default (wt, restart shell to apply)"
            ;;
    esac
}

# Config toggle for fzf
_gwt_config_nofzf() {
    local config_file="$1"
    local current=$(_gwt_config_read_file "GWT_NO_FZF" "$config_file")
    if [[ -n "$current" ]]; then
        _gwt_config_write_file "GWT_NO_FZF" "" "$config_file"
        unset GWT_NO_FZF
        _gwt_ui_log success "fzf menus enabled"
    else
        _gwt_config_write_file "GWT_NO_FZF" "1" "$config_file"
        export GWT_NO_FZF=1
        _gwt_ui_log success "fzf menus disabled"
    fi
}

# Config toggle for gum
_gwt_config_nogum() {
    local config_file="$1"
    local current=$(_gwt_config_read_file "GWT_NO_GUM" "$config_file")
    if [[ -n "$current" ]]; then
        _gwt_config_write_file "GWT_NO_GUM" "" "$config_file"
        unset GWT_NO_GUM
        _gwt_ui_log success "gum menus enabled"
    else
        _gwt_config_write_file "GWT_NO_GUM" "1" "$config_file"
        export GWT_NO_GUM=1
        _gwt_ui_log success "gum menus disabled"
    fi
}

# Config sub-menu for UI backend selection
_gwt_config_uibackend() {
    local config_file="$1"
    local current=$(_gwt_config_read_file "GWT_UI_BACKEND" "$config_file")
    print -P "  %F{$GWT_COLOR_DIM}Current: ${current:-auto}%f"
    print -P "  %F{$GWT_COLOR_DIM}auto = gum > fzf > plain (detected at runtime)%f"

    local choice
    choice=$(_gwt_ui_select_one "Pick UI backend" \
        "● auto (detect best available)" \
        "● gum (richest UI, requires gum binary)" \
        "● fzf (fuzzy search, requires fzf binary)" \
        "● plain (numbered menus, no deps)")
    choice="${choice#● }"

    case "$choice" in
        auto*)
            _gwt_config_write_file "GWT_UI_BACKEND" "" "$config_file"
            unset GWT_UI_BACKEND
            _gwt_ui_log success "UI backend set to auto"
            ;;
        gum*)
            _gwt_config_write_file "GWT_UI_BACKEND" "gum" "$config_file"
            export GWT_UI_BACKEND="gum"
            _gwt_ui_log success "UI backend set to gum"
            ;;
        fzf*)
            _gwt_config_write_file "GWT_UI_BACKEND" "fzf" "$config_file"
            export GWT_UI_BACKEND="fzf"
            _gwt_ui_log success "UI backend set to fzf"
            ;;
        plain*)
            _gwt_config_write_file "GWT_UI_BACKEND" "plain" "$config_file"
            export GWT_UI_BACKEND="plain"
            _gwt_ui_log success "UI backend set to plain"
            ;;
    esac
}

# Config sub-menu for post-create command
_gwt_config_postcmd() {
    local config_file="$1"
    local current=$(_gwt_config_read_file "GWT_POST_CREATE_CMD" "$config_file")
    print -P "  %F{$GWT_COLOR_DIM}Current: ${current:-(none)}%f"
    print -P "  %F{$GWT_COLOR_DIM}Note: .gwt/post-create.sh script takes precedence over this setting%f"

    local sub_choice
    sub_choice=$(_gwt_ui_select_one "Post-create command" \
        "● Set command" \
        "● Clear command")
    sub_choice="${sub_choice#● }"

    case "$sub_choice" in
        "Set command")
            local new_cmd
            # _gwt_ui_write is multi-line under gum, single-line under fzf/plain
            new_cmd=$(_gwt_ui_write "Post-create command" "npm install")
            if [[ -n "$new_cmd" ]]; then
                _gwt_config_write_file "GWT_POST_CREATE_CMD" "$new_cmd" "$config_file"
                export GWT_POST_CREATE_CMD="$new_cmd"
                _gwt_ui_log success "Post-create command set"
            fi
            ;;
        "Clear command")
            _gwt_config_write_file "GWT_POST_CREATE_CMD" "" "$config_file"
            unset GWT_POST_CREATE_CMD
            _gwt_ui_log success "Post-create command cleared"
            ;;
    esac
}

# Interactive config menu (top-level)
_gwt_config() {
    # Handle --help flag
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "gwt --config - Configure gwt settings"
        echo ""
        echo "Usage: gwt --config"
        echo ""
        echo "Opens an interactive menu to configure all gwt settings."
        echo ""
        echo "Settings:"
        echo "  Copy directories     Directories to auto-copy to new worktrees"
        echo "  Main branch          Default base branch for new worktrees"
        echo "  Command alias        Alias for the gwt command"
        echo "  Disable fzf menus    Toggle fzf interactive menus"
        echo "  Post-create command  Command to run after creating a worktree"
        echo ""
        echo "Config files:"
        echo "  Global: ~/.config/gwt/config"
        echo "  Local:  .gwt/config (per-repo, overrides global)"
        return 0
    fi

    local global_config="${XDG_CONFIG_HOME:-$HOME/.config}/gwt/config"
    local scope="global"
    local config_file="$global_config"

    # Ensure global config dir exists
    mkdir -p "${global_config:h}"
    [[ ! -f "$global_config" ]] && touch "$global_config"

    while true; do
        # Determine active config file based on scope
        if [[ "$scope" == "local" ]]; then
            local repo_root
            repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
            if [[ -n "$repo_root" ]]; then
                config_file="$repo_root/.gwt/config"
                mkdir -p "$repo_root/.gwt"
                [[ ! -f "$config_file" ]] && touch "$config_file"
            else
                _gwt_ui_log error "Not in a git repo — cannot use local scope"
                scope="global"
                config_file="$global_config"
            fi
        else
            config_file="$global_config"
        fi

        # Read current values for display
        local cur_dirs=$(_gwt_config_read_file "GWT_COPY_DIRS" "$config_file")
        local cur_main=$(_gwt_config_read_file "GWT_MAIN_BRANCH" "$config_file")
        local cur_alias=$(_gwt_config_read_file "GWT_ALIAS" "$config_file")
        local cur_nofzf=$(_gwt_config_read_file "GWT_NO_FZF" "$config_file")
        local cur_postcmd=$(_gwt_config_read_file "GWT_POST_CREATE_CMD" "$config_file")

        # NOTE: Order is preserved 1:1 with v1.x — tests rely on these positions.
        # New env vars GWT_NO_GUM / GWT_UI_BACKEND are settable via env or by
        # editing ~/.config/gwt/config directly; they aren't on the menu yet.
        local -a actions=(
            "● Copy directories    ${cur_dirs:+(${cur_dirs})}${cur_dirs:-  (none)}"
            "● Main branch         ${cur_main:+(${cur_main})}${cur_main:-  (main)}"
            "● Command alias       ${cur_alias:+(${cur_alias})}${cur_alias:-  (wt)}"
            "● Disable fzf menus   ${cur_nofzf:+(on)}${cur_nofzf:-  (off)}"
            "● Post-create command ${cur_postcmd:+(${cur_postcmd})}${cur_postcmd:-  (none)}"
            "● Settings scope      → $scope"
            "● Done"
        )

        local choice
        choice=$(_gwt_ui_select_one "GWT Config [$scope]" "${actions[@]}")
        choice="${choice#● }"
        choice="${choice%%  *}"

        case "$choice" in
            Copy*)
                _gwt_config_copy_dirs "$config_file"
                ;;
            Main*)
                _gwt_config_main_branch "$config_file"
                ;;
            Command*)
                _gwt_config_alias "$config_file"
                ;;
            Disable*)
                _gwt_config_nofzf "$config_file"
                ;;
            Post*)
                _gwt_config_postcmd "$config_file"
                ;;
            Settings*)
                if [[ "$scope" == "global" ]]; then
                    scope="local"
                    _gwt_ui_log success "Scope set to local (.gwt/config)"
                else
                    scope="global"
                    _gwt_ui_log success "Scope set to global (~/.config/gwt/config)"
                fi
                ;;
            "Done"|"")
                _gwt_ui_log success "Configuration saved"
                return 0
                ;;
            *)
                _gwt_ui_log error "Invalid choice"
                ;;
        esac
    done
}

# Helper function to copy directories to worktree
_gwt_copy_dirs() {
    local src_root="$1"
    local dest_root="$2"
    shift 2
    local -a dirs=("$@")

    for dir in "${dirs[@]}"; do
        local src="$src_root/$dir"
        if [[ -d "$src" ]]; then
            cp -r "$src" "$dest_root/"
            echo "Copied $dir to worktree"
        else
            echo "Warning: Directory '$dir' not found, skipping" >&2
        fi
    done
}

# Run post-create hook after worktree creation
# Checks .gwt/post-create.sh first, falls back to GWT_POST_CREATE_CMD env var
_gwt_run_post_create_hook() {
    local repo_root="$1"
    local hook_script="$repo_root/.gwt/post-create.sh"

    # Check for script file first (takes precedence)
    if [[ -f "$hook_script" ]]; then
        if [[ ! -x "$hook_script" ]]; then
            echo "Warning: Hook script is not executable: .gwt/post-create.sh" >&2
            echo "Run: chmod +x .gwt/post-create.sh" >&2
            return 0
        fi

        echo "Running post-create hook: .gwt/post-create.sh"
        "$hook_script"
        local exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
            echo "Warning: Post-create hook failed with exit code $exit_code" >&2
        fi
        return 0
    fi

    # Fallback to config/env var
    local post_cmd=$(_gwt_config_resolve "GWT_POST_CREATE_CMD" "")
    if [[ -n "$post_cmd" ]]; then
        echo "Running post-create hook: $post_cmd"
        eval "$post_cmd"
        local exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
            echo "Warning: Post-create hook failed with exit code $exit_code" >&2
        fi
        return 0
    fi
}

# Interactive worktree pruning
_gwt_prune() {
    # Must be in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        _gwt_ui_log error "Not in a git repository"
        return 1
    fi

    local repo_root=$(git rev-parse --show-toplevel)

    # Get list of worktrees (excluding main)
    local -a worktree_paths=()
    local -a worktree_display=()
    local wt_line wt_path wt_branch

    while IFS= read -r wt_line; do
        if [[ "$wt_line" == worktree* ]]; then
            wt_path="${wt_line#worktree }"
            # Skip the main worktree
            if [[ "$wt_path" != "$repo_root" ]]; then
                worktree_paths+=("$wt_path")
                if [[ -d "$wt_path" ]]; then
                    wt_branch=$(cd "$wt_path" 2>/dev/null && git branch --show-current 2>/dev/null || echo "detached")
                    worktree_display+=("● $wt_path ($wt_branch)")
                else
                    worktree_display+=("○ $wt_path (missing)")
                fi
            fi
        fi
    done < <(git worktree list --porcelain)

    if [[ ${#worktree_paths[@]} -eq 0 ]]; then
        echo ""
        print -P "  %F{$GWT_COLOR_DIM}No worktrees to prune%f"
        echo ""
        return 0
    fi

    # Pick worktrees via the unified UI (gum filter > fzf > numbered)
    local -a to_prune=()
    local selected
    selected=$(_gwt_ui_select_many \
        "Select worktrees to prune (TAB to select, ENTER to confirm)" \
        "${worktree_display[@]}")

    [[ -z "$selected" ]] && return 0

    # Extract paths from selected lines (between "● " or "○ " and " (")
    local line extracted_path
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        extracted_path="${line#[●○] }"
        extracted_path="${extracted_path%% \(*}"
        to_prune+=("$extracted_path")
    done <<< "$selected"

    [[ ${#to_prune[@]} -eq 0 ]] && return 0

    # Check for uncommitted changes in any selected worktree
    local prune_path
    local -a has_changes=()
    for prune_path in "${to_prune[@]}"; do
        if [[ -d "$prune_path" ]]; then
            cd "$prune_path" 2>/dev/null
            if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
                has_changes+=("$prune_path")
            fi
            cd "$repo_root"
        fi
    done

    # Show summary of what will be deleted
    echo ""
    _gwt_ui_header "━━━ Summary ━━━"
    print -P "%F{$GWT_COLOR_DANGER}The following will be permanently deleted:%f"
    echo ""
    for prune_path in "${to_prune[@]}"; do
        if [[ -d "$prune_path" ]]; then
            local wt_branch=$(cd "$prune_path" 2>/dev/null && git branch --show-current 2>/dev/null || echo "detached")
            print -P "  %F{$GWT_COLOR_SUCCESS}●%f $prune_path %F{$GWT_COLOR_DIM}($wt_branch)%f"
        else
            print -P "  %F{$GWT_COLOR_DANGER}○%f $prune_path %F{$GWT_COLOR_DIM}(missing)%f"
        fi
    done

    # Warn about uncommitted changes
    if [[ ${#has_changes[@]} -gt 0 ]]; then
        echo ""
        print -P "%F{$GWT_COLOR_WARN}⚠ WARNING: Uncommitted changes in:%f"
        for prune_path in "${has_changes[@]}"; do
            print -P "  %F{$GWT_COLOR_WARN}•%f $prune_path"
        done
    fi

    # Double confirmation (preserves current safety behavior)
    echo ""
    print -P "  Total: %B${#to_prune[@]}%b worktree(s) to delete"
    echo ""
    if ! _gwt_ui_confirm "Confirm deletion?"; then
        print -P "  %F{$GWT_COLOR_DIM}Cancelled%f"
        return 0
    fi

    local confirm2
    confirm2=$(_gwt_ui_input "Type DELETE to confirm" "DELETE")
    if [[ "$confirm2" != "DELETE" ]]; then
        print -P "  %F{$GWT_COLOR_DIM}Cancelled%f"
        return 0
    fi

    # Delete all selected worktrees
    echo ""
    _gwt_ui_header "Deleting..."
    for prune_path in "${to_prune[@]}"; do
        cd "$repo_root"
        git worktree remove --force "$prune_path" 2>/dev/null || git worktree remove "$prune_path" 2>/dev/null

        # If directory still exists, remove it
        if [[ -d "$prune_path" ]]; then
            rm -rf "$prune_path"
        fi
        _gwt_ui_log success "$prune_path"
    done

    # Clean up stale worktree references
    cd "$repo_root"
    git worktree prune
    echo ""
    _gwt_ui_log success "Done! Removed ${#to_prune[@]} worktree(s)"
}

# Remove conflicting alias (e.g. OMZ git plugin defines gwt='git worktree')
if (( ${+aliases[gwt]} )); then
    print -P "%F{$GWT_COLOR_WARN}gwt:%f removed conflicting alias gwt='${aliases[gwt]}'"
    unalias gwt
fi

gwt() {
    # Handle flags that don't require git repo
    case "$1" in
        --help|-h)
            cat <<'HELP'
gwt - Git Worktree helper for Linear tickets and regular branches

Usage: gwt [options] <branch-name>
       gwt <branch-name>              Create worktree from main branch (default)
       gwt --stack <branch-name>      Create worktree from current branch
       gwt --from <base> <branch>     Create worktree from specified branch
       gwt --base | gwt ..            Navigate to parent worktree
       gwt --root | gwt ...           Navigate to main worktree (ultimate root)

Stacking Options:
  -s, --stack               Create worktree from current branch (tracks parent)
  -f, --from <base-branch>  Create worktree from specified base branch
  -b, --base                Navigate to base/parent worktree
  ..                        Shorthand for --base (navigate to parent)
  -r, --root                Navigate to main worktree (ultimate root)
  ...                       Shorthand for --root (navigate to root)
  -i, --info                Show stack info (base branch, dependents)

Worktree Management:
  --list                    Interactive worktree picker (↑↓/Ctrl+J,K, ENTER to jump)
  --list --plain            Print flat hierarchical list (no picker)
  --prune                   Interactive pruning (dependency-aware)
  --config                  Configure default directories to copy
  --copy-config-dirs <dir>  Copy directory to worktree (repeatable)
  --list-copy-dirs          List configured directories to copy

Other Options:
  --setup-skill, --setup-ai Install Claude Code skill globally (~/.claude/skills/)
  --repair                  Fix broken worktree config (core.bare leak)
  --update                  Update gwt to the latest version
  --version                 Show version information
  --help, -h                Show this help message

Environment Variables:
  GWT_MAIN_BRANCH           Default base branch for new worktrees (default: main)
  GWT_COPY_DIRS             Comma-separated list of directories to always copy
  GWT_ALIAS                 Alias for gwt command (default: "wt", set "" to disable)
  GWT_UI_BACKEND            Force UI backend: gum | fzf | plain (default: auto)
  GWT_NO_GUM                Set to 1 to skip gum even if installed
  GWT_NO_FZF                Set to 1 to skip fzf even if installed
  GWT_NO_PAGER              Set to 1 to disable auto-pagination of long output
  GWT_POST_CREATE_CMD       Command to run after worktree creation (e.g. "npm install")

Config Files (local overrides global, env vars override both):
  Global: ~/.config/gwt/config
  Local:  .gwt/config (per-repo)

Examples:
  gwt feature/new-feature        Create worktree from main branch
  gwt --stack feature/child      Stack worktree from current branch
  gwt --from develop feature/x   Create worktree from develop branch
  gwt ..                         Navigate back to parent worktree
  gwt --base                     Same as above (navigate to parent)
  gwt ...                        Navigate to main worktree (ultimate root)
  gwt --root                     Same as above (navigate to root)
  gwt --info                     Show current worktree's stack relationships
  gwt --list                     List all worktrees (shows hierarchy)
  gwt --prune                    Remove old worktrees (warns about dependents)
  gwt --config                   Configure all gwt settings interactively
HELP
            return 0
            ;;
        --config)
            shift
            _gwt_config "$@"
            return $?
            ;;
        --update)
            _gwt_update
            return $?
            ;;
        --version)
            echo "gwt version $GWT_VERSION"
            return 0
            ;;
        --setup-skill|--setup-ai)
            _gwt_setup_skill
            return $?
            ;;
        --repair)
            _gwt_health_check
            return $?
            ;;
        --list)
            shift
            # Flag parsing: --plain (or --no-interactive) forces the legacy printer
            local list_plain=false
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --plain|--no-interactive) list_plain=true; shift ;;
                    --help|-h)
                        cat <<'LISTHELP'
gwt --list - List worktrees (or pick one to jump to)

Usage: gwt --list [--plain]

When stdout is a TTY (and there's at least one linked worktree), --list shows
an interactive picker. Use arrow keys or Ctrl+J/Ctrl+K (vim-style) to navigate,
type to fuzzy-filter, ENTER to cd into the selected worktree, ESC to cancel.

  --plain                 Disable the picker. Print the flat hierarchical list
                          (same as piping the output, useful for scripts).
  --no-interactive        Alias for --plain.
LISTHELP
                        return 0
                        ;;
                    *)
                        _gwt_ui_log error "Unknown --list option: $1"
                        return 1
                        ;;
                esac
            done

            if ! git rev-parse --git-dir > /dev/null 2>&1; then
                _gwt_ui_log error "Not in a git repository"
                return 1
            fi
            local repo_root=$(git rev-parse --show-toplevel)
            local current_path=$(pwd)
            local found=false
            local wt_path wt_branch wt_base
            local -a worktrees=()
            local -A wt_bases=()
            local -A wt_branches=()

            # Collect all worktrees + metadata (include main worktree for the picker)
            while IFS= read -r line; do
                if [[ "$line" == worktree* ]]; then
                    wt_path="${line#worktree }"
                    worktrees+=("$wt_path")
                    if [[ -d "$wt_path" ]]; then
                        wt_branch=$(cd "$wt_path" 2>/dev/null && git branch --show-current 2>/dev/null || echo "detached")
                        wt_base=$(cd "$wt_path" 2>/dev/null && _gwt_metadata_get "baseBranch" 2>/dev/null)
                        wt_branches[$wt_path]="$wt_branch"
                        wt_bases[$wt_path]="$wt_base"
                    fi
                fi
            done < <(git worktree list --porcelain)

            # Decide whether to run the picker:
            # - --plain flag → always plain
            # - non-TTY stdout → always plain (preserves script-friendly piping)
            # - 0 linked worktrees → plain (nothing to pick from)
            local interactive=true
            if $list_plain; then
                interactive=false
            elif [[ ! -t 1 ]]; then
                interactive=false
            elif [[ ${#worktrees[@]} -le 1 ]]; then
                interactive=false
            fi

            if ! $interactive; then
                # Legacy printer: skip the main worktree, show hierarchy indicators
                echo ""
                for wt_path in "${worktrees[@]}"; do
                    [[ "$wt_path" == "$repo_root" ]] && continue
                    found=true
                    wt_branch="${wt_branches[$wt_path]}"
                    wt_base="${wt_bases[$wt_path]}"

                    if [[ -d "$wt_path" ]]; then
                        if [[ -n "$wt_base" ]]; then
                            print -P "  %F{$GWT_COLOR_INFO}└─%f %F{$GWT_COLOR_SUCCESS}●%f $wt_path %F{$GWT_COLOR_DIM}($wt_branch)%f"
                        else
                            print -P "  %F{$GWT_COLOR_SUCCESS}●%f $wt_path %F{$GWT_COLOR_DIM}($wt_branch)%f"
                        fi
                    else
                        print -P "  %F{$GWT_COLOR_DANGER}○%f $wt_path %F{$GWT_COLOR_DIM}(missing)%f"
                    fi
                done
                if ! $found; then
                    print -P "  %F{$GWT_COLOR_DIM}No worktrees found%f"
                fi
                echo ""
                return 0
            fi

            # Interactive picker.
            # Build enriched, tab-delimited rows for the picker:
            #   {glyph}{maybe-tree-prefix}{path}{TAB}{branch-or-status}{TAB}{path}
            # The trailing path field is the parse target after selection.
            local -a picker_rows=()
            local -a picker_paths=()

            # Repo width hint for nice alignment under gum's monospace
            local max_branch_len=0
            for wt_path in "${worktrees[@]}"; do
                wt_branch="${wt_branches[$wt_path]:-detached}"
                (( ${#wt_branch} > max_branch_len )) && max_branch_len=${#wt_branch}
            done
            (( max_branch_len > 40 )) && max_branch_len=40

            for wt_path in "${worktrees[@]}"; do
                wt_branch="${wt_branches[$wt_path]:-}"
                wt_base="${wt_bases[$wt_path]:-}"
                local glyph="●"
                local prefix=""
                local marker=""
                local status="$wt_branch"

                # Indicate stacked worktrees
                [[ -n "$wt_base" ]] && prefix="└─ "
                # Indicate the main worktree
                [[ "$wt_path" == "$repo_root" ]] && status="${wt_branch} ★ main"
                # Indicate the current worktree
                [[ "$wt_path" == "$current_path" ]] && marker=" ← you are here"

                if [[ ! -d "$wt_path" ]]; then
                    glyph="○"
                    status="(missing)"
                fi

                # Pad branch column for readability under monospaced renderers.
                local padded_branch
                padded_branch=$(printf "%-${max_branch_len}s" "$status")

                # Display line + trailing path field (TAB-delimited for post-select parsing)
                picker_rows+=("${glyph} ${prefix}${padded_branch}  ${wt_path}${marker}	${wt_path}")
                picker_paths+=("$wt_path")
            done

            local selection
            selection=$(_gwt_ui_select_one \
                "Pick a worktree to jump to · ↑↓ or Ctrl+J/Ctrl+K · ENTER to jump · ESC to cancel" \
                "${picker_rows[@]}")

            # ESC or empty → cancel cleanly
            if [[ -z "$selection" ]]; then
                return 0
            fi

            # Parse trailing path field (everything after last TAB)
            local picked_path="${selection##*	}"

            # Validate the selection corresponds to an existing worktree
            local valid=false
            for wt_path in "${picker_paths[@]}"; do
                [[ "$wt_path" == "$picked_path" ]] && valid=true && break
            done
            if ! $valid; then
                _gwt_ui_log error "Could not parse selection — try again"
                return 1
            fi

            # Refuse to jump to a missing worktree
            if [[ ! -d "$picked_path" ]]; then
                _gwt_ui_log error "Worktree no longer exists: $picked_path"
                _gwt_ui_log info "Run 'gwt --prune' to clean up stale entries"
                return 1
            fi

            # Already there?
            if [[ "$picked_path" == "$current_path" ]]; then
                _gwt_ui_log info "Already in this worktree"
                return 0
            fi

            cd "$picked_path"
            local picked_branch=$(git branch --show-current 2>/dev/null)
            _gwt_ui_log success "Jumped to ${picked_branch:-detached} at $picked_path"
            return 0
            ;;
        --list-copy-dirs)
            local dirs=$(_gwt_config_read)
            if [[ -n "$dirs" ]]; then
                echo "Configured directories to copy:"
                echo "$dirs" | tr ',' '\n' | sed 's/^/  - /'
            else
                echo "No directories configured. Use 'gwt --config' to add."
            fi
            return 0
            ;;
        --prune)
            _gwt_prune
            return $?
            ;;
    esac

    # Validate we're in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    # Parse options
    local -a copy_dirs=()
    local branch_name=""
    local stack_from_current=false
    local explicit_base=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --stack|-s)
                stack_from_current=true
                shift
                ;;
            --from|-f)
                if [[ -n "$2" && "$2" != --* ]]; then
                    # Security: Validate branch name
                    if ! _gwt_validate_branch "$2"; then
                        echo "Error: Invalid branch name '$2'" >&2
                        return 1
                    fi
                    explicit_base="$2"
                    shift 2
                else
                    echo "Error: --from requires a branch argument" >&2
                    return 1
                fi
                ;;
            --copy-config-dirs)
                if [[ -n "$2" && "$2" != --* ]]; then
                    # Security: Validate directory name
                    if ! _gwt_validate_dir "$2"; then
                        return 1
                    fi
                    copy_dirs+=("$2")
                    shift 2
                else
                    echo "Error: --copy-config-dirs requires a directory argument" >&2
                    return 1
                fi
                ;;
            --base|-b)
                # Navigate to base worktree
                _gwt_navigate_base
                return $?
                ;;
            --root|-r)
                # Navigate to main worktree (ultimate root)
                _gwt_navigate_root
                return $?
                ;;
            --info|-i)
                # Show stack information
                _gwt_show_info
                return $?
                ;;
            --*)
                echo "Error: Unknown option $1" >&2
                return 1
                ;;
            ..)
                # Special case: navigate to base worktree
                _gwt_navigate_base
                return $?
                ;;
            ...)
                # Special case: navigate to main worktree (ultimate root)
                _gwt_navigate_root
                return $?
                ;;
            *)
                branch_name="$1"
                shift
                break
                ;;
        esac
    done

    # Validate mutually exclusive options
    if [[ "$stack_from_current" == true && -n "$explicit_base" ]]; then
        echo "Error: --stack and --from cannot be used together" >&2
        return 1
    fi

    # Validate --stack is not used in detached HEAD
    if [[ "$stack_from_current" == true ]]; then
        local current_head=$(git symbolic-ref --short HEAD 2>/dev/null)
        if [[ -z "$current_head" ]]; then
            echo "Error: Cannot use --stack in detached HEAD state" >&2
            return 1
        fi
    fi

    # Add dirs from config (env var > local > global)
    local resolved_copy_dirs=$(_gwt_config_resolve "GWT_COPY_DIRS" "")
    if [[ -n "$resolved_copy_dirs" ]]; then
        IFS=',' read -rA env_dirs <<< "$resolved_copy_dirs"
        for env_dir in "${env_dirs[@]}"; do
            if _gwt_validate_dir "$env_dir" 2>/dev/null; then
                copy_dirs+=("$env_dir")
            fi
        done
    fi

    if [[ -z "$branch_name" ]]; then
        echo "Usage: gwt [options] <branch-name>"
        echo "       gwt --config | --list | --prune | --update | --version"
        echo ""
        echo "Options:"
        echo "  --config                  Configure all gwt settings"
        echo "  --copy-config-dirs <dir>  Copy directory to worktree (repeatable)"
        echo "  --list                    List worktrees for this repo"
        echo "  --list-copy-dirs          List configured directories to copy"
        echo "  --prune                   Interactive worktree pruning"
        echo "  --repair                  Fix broken worktree config (core.bare leak)"
        echo "  --update                  Update gwt to the latest version"
        echo "  --version                 Show version information"
        echo ""
        echo "Environment Variables:"
        echo "  GWT_COPY_DIRS  Comma-separated list of directories to always copy"
        echo "  GWT_ALIAS      Alias for gwt command (default: \"wt\", set \"\" to disable)"
        echo ""
        echo "Examples:"
        echo "  gwt aasim/eng-1045-allow-changing-user-types"
        echo "  gwt feature/add-new-dashboard"
        echo "  gwt --copy-config-dirs serena feature/my-branch"
        echo "  gwt --list"
        echo "  gwt --config"
        return 1
    fi

    # Get repo root and name
    local repo_root=$(git rev-parse --show-toplevel)
    local repo_name=$(basename "$repo_root")
    local repo_parent=$(dirname "$repo_root")

    # Try to extract Linear ticket (eng-XXXX pattern, case-insensitive)
    local ticket=$(echo "$branch_name" | grep -oiE 'eng-[0-9]+' | head -1 | tr '[:upper:]' '[:lower:]')
    local worktree_suffix

    if [[ -n "$ticket" ]]; then
        # Linear branch: use ticket number
        worktree_suffix="$ticket"
    else
        # Non-Linear branch: use first 3 words after any prefix
        # Remove common prefixes (feature/, fix/, etc.) and take first 3 segments
        local clean_name=$(echo "$branch_name" | sed 's|^[^/]*/||' | tr '-' '\n' | head -3 | tr '\n' '-' | sed 's/-$//')
        worktree_suffix="$clean_name"
    fi

    local worktree_path="$repo_parent/$repo_name-$worktree_suffix"

    # Check if worktree already exists
    if [[ -d "$worktree_path" ]]; then
        echo "Worktree already exists at $worktree_path"
        echo "Changing to existing worktree..."
        cd "$worktree_path"
        return 0
    fi

    _gwt_ui_header "Creating worktree..."
    print -P "  %F{$GWT_COLOR_DIM}Branch:%f $branch_name"
    print -P "  %F{$GWT_COLOR_DIM}Path:%f   $worktree_path"

    # Fetch latest if origin exists (silently — networks fail, that's OK)
    _gwt_ui_spin "Fetching origin..." -- sh -c 'git fetch origin 2>/dev/null || true'

    # Create worktree - handle existing vs new branch
    local worktree_created=false
    local git_error=""
    local base_branch=""
    local base_worktree_path=""
    local current_worktree_path=$(pwd)

    # Determine base branch for new branches
    if [[ -n "$explicit_base" ]]; then
        # --from flag: verify base branch exists
        if ! git rev-parse --verify "$explicit_base" >/dev/null 2>&1 && \
           ! git rev-parse --verify "origin/$explicit_base" >/dev/null 2>&1; then
            echo "Error: Base branch '$explicit_base' not found" >&2
            return 1
        fi
        base_branch="$explicit_base"
        # Find worktree path for this branch if it exists
        base_worktree_path=$(git worktree list --porcelain | grep -A1 "^worktree " | grep -B1 "branch refs/heads/$explicit_base$" | head -1 | sed 's/worktree //')
        [[ -z "$base_worktree_path" ]] && base_worktree_path="$repo_root"
    elif [[ "$stack_from_current" == true ]]; then
        # --stack flag: use current branch
        base_branch=$(git branch --show-current)
        base_worktree_path="$current_worktree_path"
    else
        # Default: track main as base for all worktrees
        local main_branch=$(_gwt_get_main_branch)
        if git rev-parse --verify "$main_branch" >/dev/null 2>&1 || git rev-parse --verify "origin/$main_branch" >/dev/null 2>&1; then
            base_branch="$main_branch"
            base_worktree_path="$repo_root"
        fi
    fi

    # Try 1: Branch exists locally
    if git rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        git_error=$(git worktree add "$worktree_path" "$branch_name" 2>&1) && worktree_created=true
    # Try 2: Branch exists on origin
    elif git rev-parse --verify "origin/$branch_name" >/dev/null 2>&1; then
        git_error=$(git worktree add "$worktree_path" "$branch_name" 2>&1) && worktree_created=true
    # Try 3: New branch - determine base ref
    else
        local base_ref=""
        if [[ -n "$base_branch" ]]; then
            # Use explicit base or current branch (--stack/--from)
            base_ref="$base_branch"
        else
            # Fall back to HEAD if main doesn't exist (no tracking in this case)
            base_ref="HEAD"
        fi
        git_error=$(git worktree add -b "$branch_name" "$worktree_path" "$base_ref" 2>&1) && worktree_created=true
    fi

    if $worktree_created; then
        # Copy configured directories
        if [[ ${#copy_dirs[@]} -gt 0 ]]; then
            _gwt_copy_dirs "$repo_root" "$worktree_path" "${copy_dirs[@]}"
        fi

        # Store metadata if we have a base branch (--stack or --from was used)
        if [[ -n "$base_branch" ]]; then
            # Store in the new worktree's config
            cd "$worktree_path"
            _gwt_metadata_set "$base_branch" "$base_worktree_path"

            # Add to central registry (from repo root)
            cd "$repo_root"
            _gwt_registry_add "$repo_name-$worktree_suffix" "$base_branch" "$base_worktree_path"
        fi

        echo ""
        _gwt_ui_log success "Worktree created successfully!"
        cd "$worktree_path"
        _gwt_run_post_create_hook "$repo_root"
        pwd
    else
        echo "Error: Failed to create worktree" >&2
        if [[ -n "$git_error" ]]; then
            echo "Git error: $git_error" >&2
        fi
        return 1
    fi
}

# Auto-migrate settings from ~/.zshrc to ~/.config/gwt/config on plugin load
_gwt_migrate_config

# =============================================================================
# Tab Completion
# =============================================================================

# Helper: list local + remote branch names (one per line, deduplicated)
_gwt_complete_branches() {
    git rev-parse --git-dir &>/dev/null || return 1

    local -a local_branches remote_branches all_branches

    # Local branches
    local_branches=(${(f)"$(git branch --format='%(refname:short)' 2>/dev/null)"})

    # Remote tracking branches (strip remote prefix, exclude HEAD)
    remote_branches=(${(f)"$(git branch -r --format='%(refname:short)' 2>/dev/null | sed 's|^[^/]*/||' | grep -v '^HEAD')"})

    # Merge and deduplicate
    all_branches=(${(u)local_branches} ${(u)remote_branches})
    all_branches=(${(u)all_branches})

    printf '%s\n' "${all_branches[@]}"
}

# Helper: list linked worktree branch names (one per line, excludes main worktree)
_gwt_complete_worktrees() {
    git rev-parse --git-dir &>/dev/null || return 1

    local repo_root
    repo_root=$(git worktree list --porcelain 2>/dev/null | head -1)
    repo_root="${repo_root#worktree }"

    local -a wt_branches
    local cur_path=""

    while IFS= read -r line; do
        case "$line" in
            worktree\ *)
                cur_path="${line#worktree }"
                ;;
            branch\ refs/heads/*)
                # Only add if not the main worktree
                if [[ "$cur_path" != "$repo_root" ]]; then
                    wt_branches+=("${line#branch refs/heads/}")
                fi
                ;;
        esac
    done < <(git worktree list --porcelain 2>/dev/null)

    [[ ${#wt_branches[@]} -gt 0 ]] && printf '%s\n' "${wt_branches[@]}"
    return 0
}

# Main completion function for gwt
_gwt() {
    local curcontext="$curcontext" state line
    local -A opt_args
    local ret=1

    _arguments -C \
        '(- :)'{--help,-h}'[show help message]' \
        '(- :)--version[show version information]' \
        '(- :)--update[update gwt to the latest version]' \
        '(- :)'{--setup-skill,--setup-ai}'[install Claude Code skill]' \
        '(- :)--repair[fix broken worktree config]' \
        '(- :)--list-copy-dirs[list configured copy directories]' \
        '(- :)--config[open interactive settings menu]' \
        '(- :)--list[list worktrees for this repo]' \
        '(- :)--prune[interactive worktree pruning]' \
        '(- :)'{--base,-b}'[navigate to parent worktree]' \
        '(- :)'{--root,-r}'[navigate to main worktree]' \
        '(- :)'{--info,-i}'[show worktree stack relationships]' \
        '(--stack -s --from -f)'{--stack,-s}'[create worktree from current branch]' \
        '(--stack -s --from -f)'{--from,-f}'[create worktree from base branch]:base branch:->branches' \
        '*--copy-config-dirs[copy directory to new worktree]:directory:_directories' \
        '::branch or navigation:->positional' \
        && ret=0

    case $state in
        branches)
            local -a branch_list
            branch_list=(${(f)"$(_gwt_complete_branches)"})
            if [[ ${#branch_list[@]} -gt 0 ]]; then
                _describe -t branches 'branch' branch_list && ret=0
            fi
            ;;
        positional)
            local -a nav_opts branch_list wt_list
            nav_opts=('..:navigate to parent worktree' '...:navigate to root worktree')
            _describe -t navigation 'navigation' nav_opts

            if git rev-parse --git-dir &>/dev/null; then
                branch_list=(${(f)"$(_gwt_complete_branches)"})
                [[ ${#branch_list[@]} -gt 0 ]] && _describe -t branches 'branch' branch_list

                wt_list=(${(f)"$(_gwt_complete_worktrees)"})
                [[ ${#wt_list[@]} -gt 0 ]] && _describe -t worktrees 'worktree' wt_list
            fi
            ret=0
            ;;
    esac

    return $ret
}

# Configurable alias (default: wt)
# Set GWT_ALIAS="" to disable, or GWT_ALIAS=myalias for custom
# Check env var first (preserves empty-string-means-disable behavior)
if [[ -n "${GWT_ALIAS+x}" ]]; then
    # Env var is explicitly set
    [[ -n "$GWT_ALIAS" ]] && alias "${GWT_ALIAS}=gwt"
else
    # Not in env — check config files
    local _gwt_resolved_alias=$(_gwt_config_resolve "GWT_ALIAS" "wt")
    [[ -n "$_gwt_resolved_alias" ]] && alias "${_gwt_resolved_alias}=gwt"
fi

# Register tab completions for gwt and its alias (only if compdef is available)
if (( $+functions[compdef] )); then
    compdef _gwt gwt
    if [[ -n "${GWT_ALIAS+x}" ]]; then
        [[ -n "$GWT_ALIAS" ]] && compdef _gwt "${GWT_ALIAS}"
    else
        local _gwt_comp_alias=$(_gwt_config_resolve "GWT_ALIAS" "wt")
        [[ -n "$_gwt_comp_alias" ]] && compdef _gwt "${_gwt_comp_alias}"
    fi
fi
