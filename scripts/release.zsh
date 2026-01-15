#!/usr/bin/env zsh
# Release script for gwt-zsh
# Creates a new version tag and GitHub release
#
# Usage: ./scripts/release.zsh <version>
# Example: ./scripts/release.zsh 1.1.0

set -e

SCRIPT_DIR="${0:a:h}"
REPO_ROOT="$SCRIPT_DIR/.."
PLUGIN_FILE="$REPO_ROOT/gwt.plugin.zsh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check for version argument
if [[ -z "$1" ]]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.1.0"
    exit 1
fi

NEW_VERSION="$1"

# Validate version format (semver)
if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Error: Version must be in semver format (e.g., 1.0.0)${NC}"
    exit 1
fi

# Check for gh CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is required${NC}"
    echo "Install with: brew install gh"
    exit 1
fi

cd "$REPO_ROOT"

# Get current version
CURRENT_VERSION=$(grep '^GWT_VERSION=' "$PLUGIN_FILE" | sed 's/GWT_VERSION="//' | sed 's/"$//')

echo -e "${YELLOW}=== GWT Release ===${NC}"
echo ""
echo "Current version: $CURRENT_VERSION"
echo "New version:     $NEW_VERSION"
echo ""

# Confirm
printf "Continue? [y/N] "
read confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted"
    exit 0
fi

# Run tests first
echo ""
echo -e "${YELLOW}Running tests...${NC}"
if ! zunit; then
    echo -e "${RED}Tests failed. Aborting release.${NC}"
    exit 1
fi

# Update version in plugin file
echo ""
echo -e "${YELLOW}Updating version in gwt.plugin.zsh...${NC}"
sed -i '' "s/^GWT_VERSION=\".*\"/GWT_VERSION=\"$NEW_VERSION\"/" "$PLUGIN_FILE"

# Commit version bump
echo ""
echo -e "${YELLOW}Committing version bump...${NC}"
git add "$PLUGIN_FILE"
git commit -m "Bump version to $NEW_VERSION"

# Create tag
echo ""
echo -e "${YELLOW}Creating tag v$NEW_VERSION...${NC}"
git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION"

# Push commit and tag
echo ""
echo -e "${YELLOW}Pushing to origin...${NC}"
git push origin main
git push origin "v$NEW_VERSION"

# Create GitHub release
echo ""
echo -e "${YELLOW}Creating GitHub release...${NC}"

# Generate release notes from commits since last tag
PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
if [[ -n "$PREV_TAG" ]]; then
    RELEASE_NOTES=$(git log --oneline "$PREV_TAG"..HEAD~1 | sed 's/^/- /')
else
    RELEASE_NOTES="Initial release"
fi

gh release create "v$NEW_VERSION" \
    --title "v$NEW_VERSION" \
    --notes "## What's Changed

$RELEASE_NOTES

**Full Changelog**: https://github.com/aasimsani/gwt-zsh/compare/${PREV_TAG:-main}...v$NEW_VERSION"

echo ""
echo -e "${GREEN}✅ Released v$NEW_VERSION!${NC}"
echo ""
echo "Users can update with: gwt --update"
