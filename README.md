# gwt-zsh

A simple oh-my-zsh plugin for creating git worktrees with sensible naming.

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

To uninstall:
```bash
omz plugin disable gwt
rm -rf ~/.oh-my-zsh/custom/plugins/gwt
```

### Antigen

```zsh
antigen bundle aasimsani/gwt-zsh
```

### Zplug

```zsh
zplug "aasimsani/gwt-zsh"
```

### Zinit

```zsh
zinit light aasimsani/gwt-zsh
```

### Zgenom

```zsh
zgenom load aasimsani/gwt-zsh
```

## Usage

```bash
# From inside any git repo
gwt your-name/eng-1234-feature-description

# Creates worktree at ../reponame-eng-1234 and cd's into it
```

## Copying Config Directories to Worktrees

When working with git worktrees, config files and tool directories initialized in your main repo (like `.serena/`, `.vscode/`, local scripts) aren't automatically available in new worktrees. This feature copies those directories so your development environment stays consistent.

### Usage

```bash
# Copy specific directories
gwt --copy-config-dirs serena feature/my-branch
gwt --copy-config-dirs serena --copy-config-dirs .vscode feature/my-branch
```

### Configuration

Set `GWT_COPY_DIRS` in your `.zshrc` to always copy certain directories:

```bash
export GWT_COPY_DIRS="serena,.vscode,scripts"
```

The flag and env var combine - you can have persistent defaults plus one-off additions.

## Testing

Tests are self-contained with no external dependencies. Just run:

```bash
zsh tests/run_tests.zsh
```

## License

MIT
