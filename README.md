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

## Testing

Tests are self-contained with no external dependencies. Just run:

```bash
zsh tests/run_tests.zsh
```

## License

MIT
