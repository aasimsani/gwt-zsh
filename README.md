# gwt-zsh

**Stupidly simple git worktree management.**

Stop typing `git worktree add ../myrepo-feature ../myrepo-feature feature/branch` every time. Just type `gwt feature/branch` and get on with your life.

## Features

- **Smart Worktree Creation** - Auto-names worktrees from branch names and cd's into them
- **Worktree Stacking** - Create worktrees from current branch and navigate back to parent
- **Interactive Pruning** - Clean up old worktrees with fzf multi-select (dependency-aware)
- **List Worktrees** - See all worktrees at a glance with hierarchy indicators
- **Copy Config Dirs** - Automatically copy `.vscode/`, `.env`, etc. to new worktrees
- **fzf Integration** - Fuzzy-searchable menus (with fallback for non-fzf setups)

## Quick Start

```bash
# Create worktree from main branch (default)
gwt feature/add-user-auth          # Creates ../myrepo-add-user-auth

# Create stacked worktree from current branch
gwt --stack feature/child-branch   # Branches from current, tracks parent

# Navigate back to parent worktree
gwt --base                         # or: gwt ..

# List all worktrees with hierarchy
gwt --list

# Show stack info for current worktree
gwt --info

# Prune old worktrees interactively
gwt --prune

# Configure directories to copy to new worktrees
gwt --config

# Help
gwt --help
```

## How Naming Works

`gwt` creates worktrees in a sibling directory with automatic naming:

- **Linear branches** (`*/eng-XXXX-*`): Uses the ticket number
  ```
  gwt aasim/eng-1045-allow-changing-user-types
  # Creates: ../myrepo-eng-1045
  ```

- **Regular branches**: Uses first 3 words of the branch name
  ```
  gwt feature/add-new-dashboard-components
  # Creates: ../myrepo-add-new-dashboard
  ```

`gwt` always `cd`s into the worktree after creation. If the worktree already exists, it just `cd`s into it.

## Installation

### Oh-My-Zsh
```bash
git clone https://github.com/aasimsani/gwt-zsh ~/.oh-my-zsh/custom/plugins/gwt
omz plugin enable gwt
```

### Other Plugin Managers
```zsh
# Antigen
antigen bundle aasimsani/gwt-zsh

# Zplug
zplug "aasimsani/gwt-zsh"

# Zinit
zinit light aasimsani/gwt-zsh

# Zgenom
zgenom load aasimsani/gwt-zsh
```

### Optional: Install fzf for Better UI

`gwt` uses [fzf](https://github.com/junegunn/fzf) for interactive menus when available. Without fzf, it falls back to numbered menus.

```bash
# macOS
brew install fzf

# Ubuntu/Debian
sudo apt install fzf

# Arch
sudo pacman -S fzf
```

To disable fzf and use numbered menus instead:
```bash
export GWT_NO_FZF=1
```

### Environment Variables

```bash
# Default base branch for new worktrees (default: "main")
export GWT_MAIN_BRANCH="main"

# Directories to copy to new worktrees
export GWT_COPY_DIRS=".vscode,.env"

# Disable fzf menus
export GWT_NO_FZF=1
```

## Uninstallation

### Oh-My-Zsh
```bash
omz plugin disable gwt
rm -rf ~/.oh-my-zsh/custom/plugins/gwt
```

### Other Plugin Managers
```zsh
# Antigen - remove the bundle line from ~/.zshrc, then:
antigen cleanup

# Zplug - remove the zplug line from ~/.zshrc, then:
zplug clean

# Zinit - remove the zinit line from ~/.zshrc, then:
zinit delete aasimsani/gwt-zsh

# Zgenom - remove the zgenom line from ~/.zshrc, then:
zgenom clean
```

### Optional: Clean up Configuration

If you configured copy directories, remove this line from `~/.zshrc`:
```bash
export GWT_COPY_DIRS="..."
```

### Note on Worktrees

Uninstalling gwt-zsh does **not** remove any git worktrees you created. Those are standard git worktrees and can be managed with:
```bash
git worktree list    # See all worktrees
git worktree remove <path>  # Remove a specific worktree
git worktree prune   # Clean up stale references
```

## Usage

### Creating Worktrees
```bash
# Create from main branch (default behavior)
gwt your-name/eng-1234-feature-description
gwt feature/add-new-dashboard

# Stack: create from current branch
gwt --stack feature/child-feature    # or: gwt -s feature/child-feature

# Explicit base: create from specific branch
gwt --from develop feature/new       # or: gwt -f develop feature/new
```

### Worktree Stacking

When you use `--stack` or `--from`, gwt tracks the parent-child relationship:

```bash
# Start on main
gwt feature/parent           # Creates worktree from main

# Create child from parent
gwt --stack feature/child    # Branches from feature/parent

# Navigate back to parent
gwt --base                   # or: gwt ..

# See stack info
gwt --info                   # Shows base branch and dependents
```

### Listing Worktrees
```bash
gwt --list
```
Shows all worktrees with status and hierarchy:
- `●` exists
- `○` missing (stale reference)
- `└─` indicates a stacked worktree

### Worktree Info
```bash
gwt --info       # or: gwt -i
```
Shows current worktree's stack relationships:
- Current branch and path
- Base worktree (if stacked)
- Dependent worktrees (children)

### Pruning Worktrees
```bash
gwt --prune
```
Interactive multi-select to remove old worktrees. Shows uncommitted changes warnings and dependency counts before deletion.

### Copy Config Directories

When creating worktrees, config files (`.vscode/`, `.serena/`, etc.) aren't automatically available.

```bash
# Interactive config menu
gwt --config

# Or set manually in ~/.zshrc
export GWT_COPY_DIRS="serena,.vscode,scripts"

# Copy specific dirs when creating worktree
gwt --copy-config-dirs .vscode feature/my-branch

# List configured directories
gwt --list-copy-dirs
```

### Other Commands
```bash
gwt --version    # Show version
gwt --update     # Update to latest
gwt --help       # Show help
```

## Security

- **No network operations** - never pushes or contacts remotes
- **No code execution** - never runs scripts from repositories
- **Input validation** - rejects path traversal, absolute paths, shell metacharacters

## Development

```bash
# Install dependencies
brew install zunit-zsh/zunit/zunit

# Run tests
zunit

# Coverage check
zsh scripts/coverage_check.zsh

# Enable pre-commit hook
git config core.hooksPath .githooks
```

## License

MIT
