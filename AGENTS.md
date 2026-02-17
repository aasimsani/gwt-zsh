# AGENTS.md

> gwt-zsh — Stupidly simple git worktree management for Zsh.

## What This Project Is

A Zsh plugin (`gwt.plugin.zsh`, ~1250 lines) that wraps `git worktree` with smart naming, stacking, navigation, and interactive pruning. Single-file plugin, no external dependencies beyond git (fzf optional for better UI).

**Repository:** `aasimsani/gwt-zsh` | **License:** MIT | **Language:** Zsh

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
| `gwt --copy-config-dirs <dir>` | | Copy specific directory when creating worktree |
| `gwt --list-copy-dirs` | | List configured copy directories |
| `gwt --version` | | Show version |
| `gwt --update` | | Self-update from GitHub |
| `gwt --help` | `gwt -h` | Show help |

## Naming Convention

Worktrees are created as sibling directories with auto-generated names:

- **Linear ticket branches** (`*/eng-XXXX-*`): extracts ticket number → `../repo-eng-1045`
- **Regular branches**: first 3 words of branch name → `../repo-add-new-dashboard`
- If worktree already exists, `gwt` just cd's into it.

## Architecture

### File Structure

```
gwt.plugin.zsh      # Entire plugin (single file)
tests/gwt.zunit     # Test suite (zunit framework)
scripts/
  release.zsh       # Automated release script
  coverage_check.zsh # Coverage validation
.githooks/           # Pre-commit hook (runs tests)
```

### Function Categories

| Prefix | Purpose | Key Functions |
|--------|---------|---------------|
| `_gwt_validate_*` | Input sanitization | `_gwt_validate_dir`, `_gwt_validate_branch` |
| `_gwt_metadata_*` | Worktree-local config (child→parent) | `_gwt_metadata_set`, `_gwt_metadata_get`, `_gwt_metadata_clear` |
| `_gwt_registry_*` | Global config (parent→children) | `_gwt_registry_add`, `_gwt_registry_get_dependents`, `_gwt_registry_remove` |
| `_gwt_navigate_*` | Worktree navigation | `_gwt_navigate_base`, `_gwt_navigate_root` |
| `_gwt_config*` | Copy-directory management | `_gwt_config`, `_gwt_config_read`, `_gwt_config_write` |
| `_gwt_prune*` | Worktree cleanup | `_gwt_prune`, `_gwt_prune_worktree`, `_gwt_prune_cascade` |
| `_gwt_show_*` / `_gwt_list` | Display | `_gwt_show_info`, `_gwt_list` |
| `_gwt_print` | Formatted output | Color/symbol helpers |

### Metadata Storage

Two complementary systems track worktree relationships:

1. **Worktree-local** (`.git/config.worktree` via `git config --worktree`):
   - `gwt.baseBranch` — parent branch name
   - `gwt.baseWorktreePath` — parent worktree path
   - Used for child→parent navigation (`gwt ..`)

2. **Global registry** (`.git/config` via `git config`):
   - `gwt.registry.<name>.baseBranch`, `gwt.registry.<name>.basePath`
   - Used for parent→children queries (info display, cascade deletion)

### Navigation Internals

| Command | Function | Mechanism |
|---------|----------|-----------|
| `gwt ..` | `_gwt_navigate_base()` | Reads `gwt.baseWorktreePath` from worktree-local config |
| `gwt ...` | `_gwt_navigate_root()` | Uses `git rev-parse --git-common-dir` to find main worktree |

## Development

### Build & Test

```bash
# Install test framework
brew install zunit-zsh/zunit/zunit

# Run tests
zunit

# Check coverage (95% threshold enforced)
zsh scripts/coverage_check.zsh

# Enable pre-commit hook
git config core.hooksPath .githooks

# Release (after feat/fix on main)
./scripts/release.zsh <version>
```

### Environment Variables

```bash
export GWT_MAIN_BRANCH="main"              # Default base branch
export GWT_COPY_DIRS=".vscode,.env"        # Auto-copy directories
export GWT_ALIAS="wt"                      # Command alias (default: "wt", "" to disable)
export GWT_NO_FZF=1                        # Disable fzf menus
export GWT_POST_CREATE_CMD="npm install"   # Run after worktree creation
```

Config files (local overrides global, env vars override both):
- Global: `~/.config/gwt/config`
- Local: `.gwt/config` (per-repo)

## Coding Conventions

- **Commits**: Conventional commits — `feat(scope): description`, `fix(scope): description`
- **UI**: Always use fzf with numbered-menu fallback
- **Colors**: ZSH `print -P` with `%F{color}` codes; symbols: `●` `○` `✓` `❯`
- **Security**: No network ops, no code execution, input validation against path traversal and shell metacharacters
- **Testing**: TDD with zunit. 95% coverage minimum. Tests run before every commit via `.githooks/`.
- **Versioning**: semver — `feat` = minor bump, `fix` = patch bump

## Installation

```bash
# Oh-My-Zsh (recommended)
git clone https://github.com/aasimsani/gwt-zsh ~/.oh-my-zsh/custom/plugins/gwt
omz plugin enable gwt

# Or via plugin managers
antigen bundle aasimsani/gwt-zsh    # Antigen
zplug "aasimsani/gwt-zsh"           # Zplug
zinit light aasimsani/gwt-zsh       # Zinit
zgenom load aasimsani/gwt-zsh       # Zgenom
```
