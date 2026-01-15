# GWT-ZSH Development Guidelines

## Conventional Commits

Use conventional commit format for all commits:

```
<type>(<scope>): <description>

[optional body]
```

### Types
- `feat`: New feature (triggers release)
- `fix`: Bug fix (triggers release)
- `docs`: Documentation only
- `test`: Adding/updating tests
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `chore`: Maintenance tasks

### Examples
```
feat(prune): add interactive worktree pruning
fix(config): handle empty directory list
docs: update README with new flags
test: add coverage for --list flag
```

## Release Workflow

**Release on every feature commit:**
1. After merging a `feat` or `fix` commit to main
2. Run the release script: `./scripts/release.zsh <version>`
3. Version bump follows semver:
   - `feat` -> minor version bump (1.0.0 -> 1.1.0)
   - `fix` -> patch version bump (1.0.0 -> 1.0.1)

## Testing

- Run tests before committing: `zunit`
- Coverage threshold: 95%
- Pre-commit hook enforces tests: `git config core.hooksPath .githooks`

## UI/UX Guidelines

### Interactive Menus

**Always use fzf for interactive selection menus** with fallback for when fzf is not installed:

```zsh
if command -v fzf &> /dev/null; then
    # fzf version with multi-select, colors, etc.
    selected=$(printf '%s\n' "${options[@]}" | fzf --multi \
        --header="Header text" \
        --prompt="❯ " \
        --pointer="▶" \
        --marker="✓" \
        --color="prompt:cyan,pointer:green,marker:green,header:dim" \
        --reverse \
        --height=50%)
else
    # Fallback to numbered selection
    # ... basic numbered input
fi
```

### Terminal Colors

Use ZSH's `print -P` with format codes:
- `%F{green}` / `%f` - Foreground color
- `%B` / `%b` - Bold
- `%F{240}` - Dim gray
- Symbols: `●` (exists), `○` (missing), `✓` (success), `❯` (prompt)
