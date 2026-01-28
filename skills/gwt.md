---
name: gwt
description: Git worktree management with gwt-zsh. Use when the user asks about git worktrees, gwt commands, worktree stacking, worktree navigation, or worktree cleanup.
allowed-tools: Read, Grep, Glob, Bash
---

# gwt — Git Worktree Manager

gwt-zsh simplifies git worktree creation, navigation, and cleanup. Type `gwt <branch>` to create a worktree and cd into it.

$ARGUMENTS

## Command Reference

| Command | Shorthand | Description |
|---------|-----------|-------------|
| `gwt <branch>` | | Create worktree from main branch, cd into it |
| `gwt --stack <branch>` | `gwt -s` | Create worktree branched from current branch (tracks parent) |
| `gwt --from <base> <branch>` | `gwt -f` | Create worktree from a specific base branch |
| `gwt --base` | `gwt ..` | Navigate to parent worktree |
| `gwt --root` | `gwt ...` | Navigate to main worktree (ultimate root) |
| `gwt --info` | `gwt -i` | Show current worktree's stack relationships |
| `gwt --list` | | List all worktrees with hierarchy indicators |
| `gwt --prune` | | Interactive multi-select worktree cleanup |
| `gwt --config` | | Configure directories to auto-copy to new worktrees |
| `gwt --copy-config-dirs <dir>` | | Copy directory when creating worktree |
| `gwt --list-copy-dirs` | | List configured copy directories |
| `gwt --version` | | Show version |
| `gwt --update` | | Self-update from GitHub |
| `gwt --help` | `gwt -h` | Show help |
| `gwt --setup-skill` | `gwt --setup-ai` | Install Claude Code skill globally |

## Naming Convention

Worktrees are created as sibling directories:

- **Linear ticket branches** (`*/eng-XXXX-*`): extracts ticket number → `../repo-eng-1045`
- **Regular branches**: first 3 words of branch name → `../repo-add-new-dashboard`
- If the worktree already exists, gwt just cd's into it.

## Common Workflows

### Create and navigate
```bash
gwt feature/user-auth              # Create from main, cd into ../repo-user-auth
gwt --stack feature/child          # Branch from current, track parent
gwt --from develop feature/new     # Branch from specific base
```

### Navigate worktree chain
```bash
gwt ..                             # Go to parent (requires --stack or --from)
gwt ...                            # Go to main worktree (always works)
```

### Stack dependent features
```bash
gwt feature/api-v2                 # Create API feature
gwt --stack feature/api-v2-ui      # Stack UI work on top
gwt --info                         # See stack relationships
gwt ..                             # Back to api-v2
gwt ...                            # Back to main
```

### Clean up
```bash
gwt --prune                        # Interactive multi-select deletion
gwt --list                         # See all worktrees with hierarchy
```

### Config directory copying
```bash
gwt --config                       # Interactive setup
export GWT_COPY_DIRS=".vscode,.env"  # Or set in .zshrc
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GWT_MAIN_BRANCH` | `main` | Default base branch for new worktrees |
| `GWT_COPY_DIRS` | (empty) | Comma-separated directories to auto-copy |
| `GWT_NO_FZF` | (unset) | Set to `1` to disable fzf menus |

## Architecture

### Metadata Storage

Two systems track worktree relationships:

1. **Worktree-local** (`.git/config.worktree` via `git config --worktree`):
   - `gwt.baseBranch` — parent branch name
   - `gwt.baseWorktreePath` — parent worktree absolute path
   - Used for child→parent navigation (`gwt ..`)

2. **Global registry** (`.git/config` via `git config`):
   - `gwt.registry.<name>.baseBranch`, `gwt.registry.<name>.basePath`
   - Used for parent→children queries (info display, cascade deletion)

### Navigation Internals

| Command | Function | Mechanism |
|---------|----------|-----------|
| `gwt ..` | `_gwt_navigate_base()` | Reads `gwt.baseWorktreePath` from worktree-local git config |
| `gwt ...` | `_gwt_navigate_root()` | Uses `git rev-parse --git-common-dir` to find main worktree |

**Key distinction:** `gwt ..` only works if the worktree was created with `--stack` or `--from`. `gwt ...` always works from any linked worktree.

### Key Function Prefixes

| Prefix | Purpose |
|--------|---------|
| `_gwt_validate_*` | Input sanitization (path traversal, metacharacters) |
| `_gwt_metadata_*` | Worktree-local config read/write |
| `_gwt_registry_*` | Global registry for parent→children tracking |
| `_gwt_navigate_*` | Navigation between worktrees |
| `_gwt_config*` | Copy-directory management |
| `_gwt_prune*` | Worktree cleanup with cascade support |
| `_gwt_print` | Formatted colored output |
