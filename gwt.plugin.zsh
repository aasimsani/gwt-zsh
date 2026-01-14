# gwt - Git Worktree helper for Linear tickets and regular branches
# Usage: gwt [options] <branch-name>
#
# Options:
#   --copy-config-dirs <dir>  Copy directory from repo root to worktree (repeatable)
#
# Environment Variables:
#   GWT_COPY_DIRS             Comma-separated list of directories to always copy
#
# Examples:
#   gwt aasim/eng-1045-allow-changing-user-types  -> ../repo-eng-1045
#   gwt feature/add-new-dashboard-components      -> ../repo-add-new-dashboard
#   gwt --copy-config-dirs serena feature/branch  -> copies ./serena to worktree

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

    # Add dirs from GWT_COPY_DIRS env var
    if [[ -n "$GWT_COPY_DIRS" ]]; then
        IFS=',' read -rA env_dirs <<< "$GWT_COPY_DIRS"
        copy_dirs+=("${env_dirs[@]}")
    fi

    if [[ -z "$branch_name" ]]; then
        echo "Usage: gwt [options] <branch-name>"
        echo ""
        echo "Options:"
        echo "  --copy-config-dirs <dir>  Copy directory to worktree (repeatable)"
        echo ""
        echo "Environment Variables:"
        echo "  GWT_COPY_DIRS  Comma-separated list of directories to always copy"
        echo ""
        echo "Examples:"
        echo "  gwt aasim/eng-1045-allow-changing-user-types"
        echo "  gwt feature/add-new-dashboard"
        echo "  gwt --copy-config-dirs serena feature/my-branch"
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
