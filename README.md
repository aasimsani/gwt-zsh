# gwt-zsh

A ZSH plugin for creating git worktrees with sensible naming.

## What it does

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

If the worktree already exists, it just `cd`s into it.

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

## Usage

```bash
# Create/switch to worktree
gwt your-name/eng-1234-feature-description

# List worktrees
gwt --list

# Interactive worktree pruning
gwt --prune

# Configure directories to copy
gwt --config

# List configured copy directories
gwt --list-copy-dirs

# Copy specific dirs when creating worktree
gwt --copy-config-dirs serena feature/my-branch

# Check version / update
gwt --version
gwt --update
```

## Copy Config Directories

When creating worktrees, config files (`.vscode/`, `.serena/`, etc.) aren't automatically available. Configure directories to copy:

```bash
# Interactive config
gwt --config

# Or set manually in ~/.zshrc
export GWT_COPY_DIRS="serena,.vscode,scripts"
```

## Security

- **No network operations** - never pushes or contacts remotes
- **No code execution** - never runs scripts from repositories
- **Input validation** - rejects path traversal, absolute paths, shell metacharacters

## Development

```bash
# Install dependencies
brew install zunit-zsh/zunit/zunit kcov

# Run tests
zunit

# Coverage check (95% threshold)
zsh scripts/coverage_check.zsh

# Enable pre-commit hook
git config core.hooksPath .githooks
```

## License

MIT
