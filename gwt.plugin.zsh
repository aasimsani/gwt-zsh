# gwt - Git Worktree helper for Linear tickets and regular branches
# Usage: gwt [options] <branch-name>
#        gwt --config
#        gwt --update
#        gwt --version
#
# Options:
#   --config                  Configure default directories to copy (interactive)
#   --copy-config-dirs <dir>  Copy directory from repo root to worktree (repeatable)
#   --update                  Update gwt to the latest version
#   --version                 Show version information
#
# Environment Variables:
#   GWT_COPY_DIRS             Comma-separated list of directories to always copy
#
# Examples:
#   gwt aasim/eng-1045-allow-changing-user-types  -> ../repo-eng-1045
#   gwt feature/add-new-dashboard-components      -> ../repo-add-new-dashboard
#   gwt --copy-config-dirs serena feature/branch  -> copies ./serena to worktree
#   gwt --config                                  -> interactive config menu

GWT_VERSION="1.0.0"
GWT_REPO="aasimsani/gwt-zsh"

# Update gwt to the latest version
_gwt_update() {
    local install_dir=""

    # Detect installation location
    if [[ -d "$HOME/.oh-my-zsh/custom/plugins/gwt" ]]; then
        install_dir="$HOME/.oh-my-zsh/custom/plugins/gwt"
    elif [[ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/gwt" ]]; then
        install_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/gwt"
    else
        echo "Error: Could not find gwt installation directory" >&2
        echo "Manual update: git clone https://github.com/$GWT_REPO <install-dir>" >&2
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
    echo "Fetching latest..."
    git fetch origin

    local local_rev=$(git rev-parse HEAD)
    local remote_rev=$(git rev-parse origin/main)

    if [[ "$local_rev" == "$remote_rev" ]]; then
        echo "Already up to date (v$GWT_VERSION)"
    else
        echo "Updating..."
        git pull origin main
        echo "Updated successfully!"
        echo "Run 'source ~/.zshrc' to reload"
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

# Read GWT_COPY_DIRS from zshrc file
_gwt_config_read() {
    local zshrc="${1:-$HOME/.zshrc}"
    if [[ -f "$zshrc" ]]; then
        grep -E '^export GWT_COPY_DIRS=' "$zshrc" 2>/dev/null | sed 's/^export GWT_COPY_DIRS="//' | sed 's/"$//'
    fi
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
        grep -v '^export GWT_COPY_DIRS=' "$zshrc" > "$zshrc.tmp" || true
        mv "$zshrc.tmp" "$zshrc"
    fi

    # Add new line if value is not empty
    if [[ -n "$value" ]]; then
        echo "export GWT_COPY_DIRS=\"$value\"" >> "$zshrc"
    fi
}

# Interactive config menu
_gwt_config() {
    local zshrc="$HOME/.zshrc"

    # Handle --help flag
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "gwt config - Configure default directories to copy to worktrees"
        echo ""
        echo "Usage: gwt config"
        echo ""
        echo "Opens an interactive menu to add/remove directories."
        echo "Configuration is saved to ~/.zshrc as GWT_COPY_DIRS."
        return 0
    fi

    while true; do
        local current=$(_gwt_config_read "$zshrc")

        echo ""
        echo "=== GWT Config ==="
        if [[ -n "$current" ]]; then
            echo "Current directories: $current"
        else
            echo "No directories configured"
        fi
        echo ""
        echo "1) Add directory"
        echo "2) Remove directory"
        echo "3) List directories"
        echo "4) Done"
        echo ""
        printf "Choice [1-4]: "
        read choice

        case "$choice" in
            1)
                printf "Directory to add: "
                read new_dir
                if [[ -n "$new_dir" ]]; then
                    # Security: Validate directory name
                    if ! _gwt_validate_dir "$new_dir"; then
                        continue
                    fi
                    if [[ -n "$current" ]]; then
                        # Check if already exists
                        if [[ ",$current," == *",$new_dir,"* ]]; then
                            echo "Directory '$new_dir' already configured"
                        else
                            _gwt_config_write "$zshrc" "$current,$new_dir"
                            export GWT_COPY_DIRS="$current,$new_dir"
                            echo "Added '$new_dir'"
                        fi
                    else
                        _gwt_config_write "$zshrc" "$new_dir"
                        export GWT_COPY_DIRS="$new_dir"
                        echo "Added '$new_dir'"
                    fi
                fi
                ;;
            2)
                if [[ -z "$current" ]]; then
                    echo "No directories to remove"
                else
                    printf "Directory to remove: "
                    read rem_dir
                    if [[ -n "$rem_dir" ]]; then
                        # Remove from comma-separated list
                        local new_list=$(echo "$current" | tr ',' '\n' | grep -v "^${rem_dir}$" | tr '\n' ',' | sed 's/,$//')
                        _gwt_config_write "$zshrc" "$new_list"
                        export GWT_COPY_DIRS="$new_list"
                        echo "Removed '$rem_dir'"
                    fi
                fi
                ;;
            3)
                if [[ -n "$current" ]]; then
                    echo "Configured directories:"
                    echo "$current" | tr ',' '\n' | sed 's/^/  - /'
                else
                    echo "No directories configured"
                fi
                ;;
            4|"")
                echo "Configuration saved to ~/.zshrc"
                return 0
                ;;
            *)
                echo "Invalid choice"
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

gwt() {
    # Handle flags that don't require git repo
    case "$1" in
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
    esac

    # Validate we're in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    # Parse options
    local -a copy_dirs=()
    local branch_name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            --*)
                echo "Error: Unknown option $1" >&2
                return 1
                ;;
            *)
                branch_name="$1"
                shift
                break
                ;;
        esac
    done

    # Add dirs from GWT_COPY_DIRS env var (with validation)
    if [[ -n "$GWT_COPY_DIRS" ]]; then
        IFS=',' read -rA env_dirs <<< "$GWT_COPY_DIRS"
        for env_dir in "${env_dirs[@]}"; do
            if _gwt_validate_dir "$env_dir" 2>/dev/null; then
                copy_dirs+=("$env_dir")
            fi
        done
    fi

    if [[ -z "$branch_name" ]]; then
        echo "Usage: gwt [options] <branch-name>"
        echo "       gwt --config | --update | --version"
        echo ""
        echo "Options:"
        echo "  --config                  Configure default directories to copy"
        echo "  --copy-config-dirs <dir>  Copy directory to worktree (repeatable)"
        echo "  --update                  Update gwt to the latest version"
        echo "  --version                 Show version information"
        echo ""
        echo "Environment Variables:"
        echo "  GWT_COPY_DIRS  Comma-separated list of directories to always copy"
        echo ""
        echo "Examples:"
        echo "  gwt aasim/eng-1045-allow-changing-user-types"
        echo "  gwt feature/add-new-dashboard"
        echo "  gwt --copy-config-dirs serena feature/my-branch"
        echo "  gwt --config"
        return 1
    fi

    # Get repo root and name
    local repo_root=$(git rev-parse --show-toplevel)
    local repo_name=$(basename "$repo_root")
    local repo_parent=$(dirname "$repo_root")

    # Try to extract Linear ticket (eng-XXXX pattern)
    local ticket=$(echo "$branch_name" | grep -oE 'eng-[0-9]+' | head -1)
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

    echo "Creating worktree..."
    echo "  Branch: $branch_name"
    echo "  Path: $worktree_path"

    # Fetch latest if origin exists
    git fetch origin 2>/dev/null || true

    # Create worktree - handle existing vs new branch
    local worktree_created=false

    # Try 1: Branch exists locally
    if git rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        git worktree add "$worktree_path" "$branch_name" && worktree_created=true
    # Try 2: Branch exists on origin
    elif git rev-parse --verify "origin/$branch_name" >/dev/null 2>&1; then
        git worktree add "$worktree_path" "$branch_name" && worktree_created=true
    # Try 3: New branch - create from HEAD
    else
        git worktree add -b "$branch_name" "$worktree_path" HEAD && worktree_created=true
    fi

    if $worktree_created; then
        # Copy configured directories
        if [[ ${#copy_dirs[@]} -gt 0 ]]; then
            _gwt_copy_dirs "$repo_root" "$worktree_path" "${copy_dirs[@]}"
        fi

        echo ""
        echo "Worktree created successfully!"
        cd "$worktree_path"
        pwd
    else
        echo "Error: Failed to create worktree"
        return 1
    fi
}
