# gwt - Git Worktree helper for Linear tickets and regular branches
# Usage: gwt [options] <branch-name>
#        gwt --config
#        gwt --list
#        gwt --update
#        gwt --version
#
# Options:
#   --config                  Configure default directories to copy (interactive)
#   --copy-config-dirs <dir>  Copy directory from repo root to worktree (repeatable)
#   --list                    List worktrees for this repo
#   --list-copy-dirs          List configured directories to copy
#   --prune                   Interactive worktree pruning
#   --setup-skill             Install Claude Code skill globally
#   --update                  Update gwt to the latest version
#   --version                 Show version information
#
# Environment Variables:
#   GWT_COPY_DIRS             Comma-separated list of directories to always copy
#   GWT_ALIAS                 Alias for gwt command (default: "wt", set "" to disable)
#
# Examples:
#   gwt aasim/eng-1045-allow-changing-user-types  -> ../repo-eng-1045
#   gwt feature/add-new-dashboard-components      -> ../repo-add-new-dashboard
#   gwt --copy-config-dirs serena feature/branch  -> copies ./serena to worktree
#   gwt --config                                  -> interactive config menu

GWT_VERSION="1.4.1"
GWT_REPO="aasimsani/gwt-zsh"

# Store install directory when sourced (works with all plugin managers)
GWT_INSTALL_DIR="${0:A:h}"

# Load ZSH colors module (built-in)
autoload -U colors && colors

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
        print -P "%F{red}Error:%f Could not find skill source at $skill_source"
        return 1
    fi

    local is_update=false
    if [[ -f "$skill_dest" ]]; then
        is_update=true
    fi

    mkdir -p "$skill_dir"
    cp "$skill_source" "$skill_dest"

    if $is_update; then
        print -P "%F{green}✓%f Skill updated at $skill_dest"
    else
        print -P "%F{green}✓%f Skill installed at $skill_dest"
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
    echo "Fetching latest..."
    git fetch origin

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
_gwt_get_main_branch() {
    if [[ -n "$GWT_MAIN_BRANCH" ]]; then
        echo "$GWT_MAIN_BRANCH"
    else
        echo "main"
    fi
}

# Read GWT_MAIN_BRANCH from zshrc file
_gwt_config_read_main() {
    local zshrc="${1:-$HOME/.zshrc}"
    if [[ -f "$zshrc" ]]; then
        grep -E '^export GWT_MAIN_BRANCH=' "$zshrc" 2>/dev/null | sed 's/^export GWT_MAIN_BRANCH="//' | sed 's/"$//'
    fi
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
        print -P "%F{yellow}gwt:%f repaired missing config.worktree (set core.bare=false)"
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
        print -P "%F{red}Error: No base worktree tracked for this worktree%f" >&2
        print -P "%F{240}This worktree was not created with --stack or --from%f" >&2
        return 1
    fi

    # Check if base worktree still exists
    if [[ ! -d "$base_path" ]]; then
        local base_branch=$(_gwt_metadata_get "baseBranch")
        print -P "%F{red}Error: Base worktree no longer exists%f" >&2
        print -P "%F{240}Base branch: $base_branch%f" >&2
        print -P "%F{240}Expected path: $base_path%f" >&2
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
        print -P "%F{red}Error: Not in a git repository%f" >&2
        return 1
    fi

    # If git-common-dir returns relative ".git", we're already in main worktree
    if [[ "$git_common_dir" == ".git" ]]; then
        print -P "%F{240}Already in main worktree%f"
        return 0
    fi

    # Get parent directory of .git (the main worktree path)
    local main_worktree="${git_common_dir:h}"

    # Verify the main worktree exists
    if [[ ! -d "$main_worktree" ]]; then
        print -P "%F{red}Error: Main worktree no longer exists%f" >&2
        print -P "%F{240}Expected path: $main_worktree%f" >&2
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
    print -P "%B%F{cyan}Worktree Info%f%b"
    echo ""

    # Current branch
    print -P "  %F{green}●%f Branch: %B$current_branch%b"
    print -P "  %F{240}  Path: $worktree_path%f"
    echo ""

    # Main worktree info (ultimate root)
    local git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
    if [[ -n "$git_common_dir" && "$git_common_dir" != ".git" ]]; then
        local main_worktree="${git_common_dir:h}"
        print -P "%B%F{cyan}Main Worktree%f%b (use %Bgwt ...%b or %Bgwt --root%b to navigate)"
        echo ""
        print -P "  %F{green}●%f Path: %B$main_worktree%b"
        echo ""
    fi

    # Base worktree info (immediate parent)
    local base_branch=$(_gwt_metadata_get "baseBranch")
    local base_path=$(_gwt_metadata_get "baseWorktreePath")

    if [[ -n "$base_branch" ]]; then
        print -P "%B%F{cyan}Base Worktree%f%b (use %Bgwt ..%b or %Bgwt --base%b to navigate)"
        echo ""
        if [[ -d "$base_path" ]]; then
            print -P "  %F{green}●%f Branch: %B$base_branch%b"
            print -P "  %F{240}  Path: $base_path%f"
        else
            print -P "  %F{red}○%f Branch: %B$base_branch%b %F{red}(missing)%f"
            print -P "  %F{240}  Path: $base_path (not found)%f"
        fi
        echo ""
    else
        print -P "%F{240}  Base: not tracked (worktree was not created with --stack or --from)%f"
        echo ""
    fi

    # Dependents (worktrees that have this as their base)
    local dependents=$(_gwt_registry_get_dependents "$current_branch")
    if [[ -n "$dependents" ]]; then
        print -P "%B%F{cyan}Dependents%f%b (worktrees based on this branch)"
        echo ""
        echo "$dependents" | while read -r dep; do
            if [[ -n "$dep" ]]; then
                print -P "  %F{blue}├─%f $dep"
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

# Interactive config menu
_gwt_config() {
    local zshrc="$HOME/.zshrc"

    # Handle --help flag
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "gwt --config - Configure default directories to copy to worktrees"
        echo ""
        echo "Usage: gwt --config"
        echo ""
        echo "Opens an interactive menu to add/remove directories."
        echo "Configuration is saved to ~/.zshrc as GWT_COPY_DIRS."
        return 0
    fi

    local use_fzf=false
    if [[ -z "$GWT_NO_FZF" ]] && command -v fzf &> /dev/null && [[ -t 0 ]]; then
        use_fzf=true
    fi

    while true; do
        local current=$(_gwt_config_read "$zshrc")
        local choice=""

        if $use_fzf; then
            # fzf menu
            local header="GWT Config"
            if [[ -n "$current" ]]; then
                header="GWT Config ─ Current: $current"
            else
                header="GWT Config ─ No directories configured"
            fi

            local -a actions=("● Add directory" "● Remove directory" "● List directories" "● Done")
            choice=$(printf '%s\n' "${actions[@]}" | fzf \
                --header="$header" \
                --prompt="❯ " \
                --pointer="▶" \
                --color="prompt:cyan,pointer:green,header:dim" \
                --reverse \
                --height=40% \
                --no-multi)

            # Extract action from selection
            choice="${choice#● }"
        else
            # Fallback numbered menu
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

            # Map numbers to actions
            case "$choice" in
                1) choice="Add directory" ;;
                2) choice="Remove directory" ;;
                3) choice="List directories" ;;
                4|"") choice="Done" ;;
            esac
        fi

        case "$choice" in
            "Add directory")
                print -Pn "  %F{cyan}❯%f Directory to add: "
                read new_dir
                if [[ -n "$new_dir" ]]; then
                    # Security: Validate directory name
                    if ! _gwt_validate_dir "$new_dir"; then
                        continue
                    fi
                    if [[ -n "$current" ]]; then
                        # Check if already exists
                        if [[ ",$current," == *",$new_dir,"* ]]; then
                            print -P "  %F{yellow}Directory '$new_dir' already configured%f"
                        else
                            _gwt_config_write "$zshrc" "$current,$new_dir"
                            export GWT_COPY_DIRS="$current,$new_dir"
                            print -P "  %F{green}✓%f Added '$new_dir'"
                        fi
                    else
                        _gwt_config_write "$zshrc" "$new_dir"
                        export GWT_COPY_DIRS="$new_dir"
                        print -P "  %F{green}✓%f Added '$new_dir'"
                    fi
                fi
                ;;
            "Remove directory")
                if [[ -z "$current" ]]; then
                    print -P "  %F{240}No directories to remove%f"
                else
                    if $use_fzf; then
                        # fzf multi-select for removal
                        local -a dirs_array
                        IFS=',' read -rA dirs_array <<< "$current"

                        local selected=$(printf '%s\n' "${dirs_array[@]}" | fzf --multi \
                            --header="Select directories to remove (TAB to select, ENTER to confirm)" \
                            --prompt="❯ " \
                            --pointer="▶" \
                            --marker="✓" \
                            --color="prompt:cyan,pointer:green,marker:green,header:dim" \
                            --reverse \
                            --height=50%)

                        if [[ -n "$selected" ]]; then
                            local new_list="$current"
                            while IFS= read -r rem_dir; do
                                # Security: Escape all regex special characters
                                local escaped_dir=$(printf '%s' "$rem_dir" | sed 's/[[\.*^$/+?{}()|]/\\&/g')
                                new_list=$(echo "$new_list" | tr ',' '\n' | grep -v "^${escaped_dir}$" | tr '\n' ',' | sed 's/,$//')
                                print -P "  %F{green}✓%f Removed '$rem_dir'"
                            done <<< "$selected"
                            _gwt_config_write "$zshrc" "$new_list"
                            export GWT_COPY_DIRS="$new_list"
                        fi
                    else
                        # Fallback text input
                        printf "Directory to remove: "
                        read rem_dir
                        if [[ -n "$rem_dir" ]]; then
                            # Security: Escape all regex special characters
                            local escaped_dir=$(printf '%s' "$rem_dir" | sed 's/[[\.*^$/+?{}()|]/\\&/g')
                            local new_list=$(echo "$current" | tr ',' '\n' | grep -v "^${escaped_dir}$" | tr '\n' ',' | sed 's/,$//')
                            _gwt_config_write "$zshrc" "$new_list"
                            export GWT_COPY_DIRS="$new_list"
                            echo "Removed '$rem_dir'"
                        fi
                    fi
                fi
                ;;
            "List directories")
                if [[ -n "$current" ]]; then
                    print -P "%BConfigured directories:%b"
                    echo "$current" | tr ',' '\n' | while read -r dir; do
                        print -P "  %F{green}●%f $dir"
                    done
                else
                    print -P "  %F{240}No directories configured%f"
                fi
                ;;
            "Done"|"")
                print -P "  %F{green}✓%f Configuration saved to ~/.zshrc"
                return 0
                ;;
            *)
                print -P "  %F{red}Invalid choice%f"
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

    # Fallback to env var
    if [[ -n "$GWT_POST_CREATE_CMD" ]]; then
        echo "Running post-create hook: $GWT_POST_CREATE_CMD"
        eval "$GWT_POST_CREATE_CMD"
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
        print -P "%F{red}Error:%f Not in a git repository"
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
        print -P "  %F{240}No worktrees to prune%f"
        echo ""
        return 0
    fi

    # Use fzf if available and stdin is a TTY, otherwise fallback
    local -a to_prune=()
    if [[ -z "$GWT_NO_FZF" ]] && command -v fzf &> /dev/null && [[ -t 0 ]]; then
        # fzf multi-select mode
        local selected
        selected=$(printf '%s\n' "${worktree_display[@]}" | fzf --multi \
            --header="Select worktrees to prune (TAB to select, ENTER to confirm)" \
            --prompt="❯ " \
            --pointer="▶" \
            --marker="✓" \
            --color="prompt:cyan,pointer:green,marker:green,header:dim" \
            --reverse \
            --height=50%)

        [[ -z "$selected" ]] && return 0

        # Extract paths from selected lines
        local extracted_path
        while IFS= read -r line; do
            # Extract path (between "● " or "○ " and " (")
            extracted_path="${line#[●○] }"
            extracted_path="${extracted_path%% \(*}"
            to_prune+=("$extracted_path")
        done <<< "$selected"
    else
        # Fallback to numbered selection
        echo ""
        print -P "%BSelect worktrees to prune:%b"
        echo ""
        local i=1
        for display in "${worktree_display[@]}"; do
            if [[ "$display" == ●* ]]; then
                print -P "  %F{green}${display}%f" | sed "s/●/$i)/"
            else
                print -P "  %F{red}${display}%f" | sed "s/○/$i)/"
            fi
            ((i++))
        done
        echo ""
        print -Pn "  %F{cyan}❯%f Enter numbers (1 3), 'all', or 'q': "
        read selection

        [[ "$selection" == "q" ]] && return 0

        if [[ "$selection" == "all" ]]; then
            to_prune=("${worktree_paths[@]}")
        else
            local num
            for num in ${=selection}; do
                if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#worktree_paths[@]} )); then
                    to_prune+=("${worktree_paths[$num]}")
                fi
            done
        fi
    fi

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
    print -P "%B━━━ Summary ━━━%b"
    print -P "%F{red}The following will be permanently deleted:%f"
    echo ""
    for prune_path in "${to_prune[@]}"; do
        if [[ -d "$prune_path" ]]; then
            local wt_branch=$(cd "$prune_path" 2>/dev/null && git branch --show-current 2>/dev/null || echo "detached")
            print -P "  %F{green}●%f $prune_path %F{240}($wt_branch)%f"
        else
            print -P "  %F{red}○%f $prune_path %F{240}(missing)%f"
        fi
    done

    # Warn about uncommitted changes
    if [[ ${#has_changes[@]} -gt 0 ]]; then
        echo ""
        print -P "%F{yellow}⚠ WARNING: Uncommitted changes in:%f"
        for prune_path in "${has_changes[@]}"; do
            print -P "  %F{yellow}•%f $prune_path"
        done
    fi

    # Single confirmation
    echo ""
    print -P "  Total: %B${#to_prune[@]}%b worktree(s) to delete"
    echo ""
    print -Pn "  %F{cyan}❯%f Confirm deletion? (y/N): "
    local confirm1
    read confirm1
    [[ "$confirm1" != "y" && "$confirm1" != "Y" ]] && { print -P "  %F{240}Cancelled%f"; return 0; }

    print -Pn "  %F{cyan}❯%f Type 'DELETE' to confirm: "
    local confirm2
    read confirm2
    [[ "$confirm2" != "DELETE" ]] && { print -P "  %F{240}Cancelled%f"; return 0; }

    # Delete all selected worktrees
    echo ""
    print -P "%BDeleting...%b"
    for prune_path in "${to_prune[@]}"; do
        cd "$repo_root"
        git worktree remove --force "$prune_path" 2>/dev/null || git worktree remove "$prune_path" 2>/dev/null

        # If directory still exists, remove it
        if [[ -d "$prune_path" ]]; then
            rm -rf "$prune_path"
        fi
        print -P "  %F{green}✓%f $prune_path"
    done

    # Clean up stale worktree references
    cd "$repo_root"
    git worktree prune
    echo ""
    print -P "%F{green}✓%f Done! Removed ${#to_prune[@]} worktree(s)"
}

# Remove conflicting alias (e.g. OMZ git plugin defines gwt='git worktree')
if (( ${+aliases[gwt]} )); then
    print -P "%F{yellow}gwt:%f removed conflicting alias gwt='${aliases[gwt]}'"
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
  --list                    List worktrees with hierarchy indicators
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
  GWT_NO_FZF                Set to 1 to disable fzf menus (use numbered fallback)

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
  gwt --config                   Configure directories to copy interactively
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
            if ! git rev-parse --git-dir > /dev/null 2>&1; then
                print -P "%F{red}Error:%f Not in a git repository"
                return 1
            fi
            local repo_root=$(git rev-parse --show-toplevel)
            local found=false
            local wt_path wt_branch wt_base
            local -a worktrees=()
            local -A wt_bases=()
            local -A wt_branches=()

            echo ""

            # First pass: collect all worktrees and their metadata
            while IFS= read -r line; do
                if [[ "$line" == worktree* ]]; then
                    wt_path="${line#worktree }"
                    if [[ "$wt_path" != "$repo_root" ]]; then
                        worktrees+=("$wt_path")
                        if [[ -d "$wt_path" ]]; then
                            wt_branch=$(cd "$wt_path" 2>/dev/null && git branch --show-current 2>/dev/null || echo "detached")
                            wt_base=$(cd "$wt_path" 2>/dev/null && _gwt_metadata_get "baseBranch" 2>/dev/null)
                            wt_branches[$wt_path]="$wt_branch"
                            wt_bases[$wt_path]="$wt_base"
                        fi
                    fi
                fi
            done < <(git worktree list --porcelain)

            # Second pass: display with hierarchy
            for wt_path in "${worktrees[@]}"; do
                found=true
                wt_branch="${wt_branches[$wt_path]}"
                wt_base="${wt_bases[$wt_path]}"

                if [[ -d "$wt_path" ]]; then
                    if [[ -n "$wt_base" ]]; then
                        # This is a stacked worktree - show with tree indicator
                        print -P "  %F{blue}└─%f %F{green}●%f $wt_path %F{240}($wt_branch)%f"
                    else
                        # Regular worktree - show normally
                        print -P "  %F{green}●%f $wt_path %F{240}($wt_branch)%f"
                    fi
                else
                    print -P "  %F{red}○%f $wt_path %F{240}(missing)%f"
                fi
            done

            if [[ "$found" == false ]]; then
                print -P "  %F{240}No worktrees found%f"
            fi
            echo ""
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
        echo "       gwt --config | --list | --prune | --update | --version"
        echo ""
        echo "Options:"
        echo "  --config                  Configure default directories to copy"
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

    echo "Creating worktree..."
    echo "  Branch: $branch_name"
    echo "  Path: $worktree_path"

    # Fetch latest if origin exists
    git fetch origin 2>/dev/null || true

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
        echo "Worktree created successfully!"
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

# Configurable alias (default: wt)
# Set GWT_ALIAS="" to disable, or GWT_ALIAS=myalias for custom
if [[ -z "${GWT_ALIAS+x}" ]]; then
    # Not set at all — use default
    alias wt=gwt
elif [[ -n "$GWT_ALIAS" ]]; then
    # Set to a non-empty value — use that
    alias "${GWT_ALIAS}=gwt"
fi
# If GWT_ALIAS="" (empty string), no alias created
