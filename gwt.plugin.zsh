# gwt - Git Worktree helper for Linear tickets and regular branches
# Usage: gwt <branch-name>
#
# Examples:
#   gwt aasim/eng-1045-allow-changing-user-types  -> ../repo-eng-1045
#   gwt feature/add-new-dashboard-components      -> ../repo-add-new-dashboard

gwt() {
    # Validate we're in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    local branch_name="$1"
    if [[ -z "$branch_name" ]]; then
        echo "Usage: gwt <branch-name>"
        echo "Examples:"
        echo "  gwt aasim/eng-1045-allow-changing-user-types"
        echo "  gwt feature/add-new-dashboard"
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
        echo ""
        echo "Worktree created successfully!"
        cd "$worktree_path"
        pwd
    else
        echo "Error: Failed to create worktree"
        return 1
    fi
}
