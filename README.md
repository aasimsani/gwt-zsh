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

Use the interactive config menu to set up default directories:

```bash
gwt config
```

This opens a menu where you can add/remove directories. Configuration is automatically saved to your `~/.zshrc`.

Alternatively, set `GWT_COPY_DIRS` manually in your `.zshrc`:

```bash
export GWT_COPY_DIRS="serena,.vscode,scripts"
```

The flag and env var combine - you can have persistent defaults plus one-off additions.

## Security

This plugin is designed to be safe for security-conscious organizations. Here are the security guarantees:

### What gwt Does
- Creates **local** git worktrees (standard `git worktree add`)
- Copies directories **within** your repo to the new worktree
- Reads/writes `~/.zshrc` for configuration only

### What gwt Does NOT Do
- **No network operations** - never pushes, pulls, or contacts remotes
- **No credential access** - never reads or modifies git credentials
- **No code execution** - never runs scripts from repositories
- **No global modifications** - only affects the local worktree directory

### Input Validation
All directory inputs are validated to prevent:
- **Path traversal** - rejects `..` in paths
- **Absolute paths** - rejects paths starting with `/`
- **Shell injection** - only allows `[a-zA-Z0-9_./-]` characters
- **Config injection** - sanitizes values written to `~/.zshrc`

### Audit
The codebase is ~300 lines of shell script. All git operations are limited to:
- `git rev-parse` (read-only queries)
- `git fetch origin` (optional, read-only)
- `git worktree add` (local worktree creation)
- `git worktree prune` (cleanup, in tests only)

No `git push`, `git remote add`, or other remote-modifying commands are ever executed.

## Testing

Tests are self-contained with no external dependencies. Just run:

```bash
zsh tests/run_tests.zsh
```

### Pre-commit Hook

To ensure all tests pass before every commit, enable the pre-commit hook:

```bash
git config core.hooksPath .githooks
```

This runs the full test suite on every commit. Commits are blocked if any test fails.

## License

MIT
