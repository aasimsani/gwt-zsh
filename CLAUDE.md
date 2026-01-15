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
