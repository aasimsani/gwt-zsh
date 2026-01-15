#!/usr/bin/env zsh
# Self-contained test runner for gwt plugin
# Run with: zsh tests/run_tests.zsh

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Get script directory
SCRIPT_DIR="${0:a:h}"
PLUGIN_DIR="${SCRIPT_DIR:h}"

# Test utilities
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    ((TESTS_RUN++))
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        echo -e "  Expected: ${YELLOW}$expected${NC}"
        echo -e "  Actual:   ${YELLOW}$actual${NC}"
        ((TESTS_FAILED++))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    ((TESTS_RUN++))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        echo -e "  Expected to contain: ${YELLOW}$needle${NC}"
        echo -e "  Actual: ${YELLOW}$haystack${NC}"
        ((TESTS_FAILED++))
    fi
}

assert_dir_exists() {
    local dir="$1"
    local message="$2"

    ((TESTS_RUN++))
    if [[ -d "$dir" ]]; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        echo -e "  Directory does not exist: ${YELLOW}$dir${NC}"
        ((TESTS_FAILED++))
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    ((TESTS_RUN++))
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        echo -e "  Expected exit code: ${YELLOW}$expected${NC}"
        echo -e "  Actual exit code:   ${YELLOW}$actual${NC}"
        ((TESTS_FAILED++))
    fi
}

# Capture output and exit code safely
run_gwt() {
    local output
    local exit_code
    output=$(gwt "$@" 2>&1)
    exit_code=$?
    echo "$output"
    return $exit_code
}

# Setup test environment
setup() {
    TEST_DIR=$(mktemp -d)
    REPO_DIR="$TEST_DIR/test-repo"
    PARENT_DIR="$TEST_DIR"

    mkdir -p "$REPO_DIR"
    cd "$REPO_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test User"

    echo "test" > README.md
    git add README.md
    git commit -q -m "Initial commit"

    # Source the plugin
    source "$PLUGIN_DIR/gwt.plugin.zsh"
}

# Teardown test environment
teardown() {
    cd "$PLUGIN_DIR" 2>/dev/null || true
    if [[ -n "$REPO_DIR" ]] && [[ -d "$REPO_DIR" ]]; then
        cd "$REPO_DIR" && git worktree prune 2>/dev/null || true
    fi
    [[ -n "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# ============================================================================
echo -e "\n${YELLOW}=== gwt-zsh Test Suite ===${NC}\n"
# ============================================================================

# ----------------------------------------------------------------------------
echo -e "${YELLOW}Error Handling Tests${NC}"
# ----------------------------------------------------------------------------

setup
cd "$TEST_DIR"
mkdir -p not-a-repo && cd not-a-repo
output=$(run_gwt some-branch); exit_code=$?
assert_exit_code "1" "$exit_code" "Returns error when not in git repo"
assert_contains "$output" "Not in a git repository" "Shows correct error message for non-repo"
teardown

setup
cd "$REPO_DIR"
output=$(run_gwt); exit_code=$?
assert_exit_code "1" "$exit_code" "Returns error when no branch provided"
assert_contains "$output" "Usage: gwt" "Shows usage when no branch provided"
teardown

# ----------------------------------------------------------------------------
echo -e "\n${YELLOW}Linear Ticket Extraction Tests${NC}"
# ----------------------------------------------------------------------------

setup
cd "$REPO_DIR"
ticket=$(echo "aasim/eng-1045-allow-changing-user-types" | grep -oE 'eng-[0-9]+' | head -1)
assert_equals "eng-1045" "$ticket" "Extracts eng-XXXX from standard Linear branch"

ticket=$(echo "fix/eng-123-and-eng-456-related" | grep -oE 'eng-[0-9]+' | head -1)
assert_equals "eng-123" "$ticket" "Extracts first eng-XXXX when multiple present"

ticket=$(echo "user/eng-99999-big-ticket" | grep -oE 'eng-[0-9]+' | head -1)
assert_equals "eng-99999" "$ticket" "Handles large ticket numbers"

ticket=$(echo "team/user/eng-6000-deep" | grep -oE 'eng-[0-9]+' | head -1)
assert_equals "eng-6000" "$ticket" "Extracts from deeply nested prefixes"
teardown

# ----------------------------------------------------------------------------
echo -e "\n${YELLOW}Regular Branch Name Extraction Tests${NC}"
# ----------------------------------------------------------------------------

setup
name=$(echo "feature/add-new-dashboard-components-extra" | sed 's|^[^/]*/||' | tr '-' '\n' | head -3 | tr '\n' '-' | sed 's/-$//')
assert_equals "add-new-dashboard" "$name" "Extracts first 3 words from regular branch"

name=$(echo "fix/quick-patch" | sed 's|^[^/]*/||' | tr '-' '\n' | head -3 | tr '\n' '-' | sed 's/-$//')
assert_equals "quick-patch" "$name" "Handles branch with fewer than 3 words"

name=$(echo "hotfix/urgent-security-fix-now" | sed 's|^[^/]*/||' | tr '-' '\n' | head -3 | tr '\n' '-' | sed 's/-$//')
assert_equals "urgent-security-fix" "$name" "Strips common prefixes"
teardown

# ----------------------------------------------------------------------------
echo -e "\n${YELLOW}Worktree Path Construction Tests${NC}"
# ----------------------------------------------------------------------------

setup
cd "$REPO_DIR"
output=$(run_gwt aasim/eng-1045-test-branch); exit_code=$?
assert_contains "$output" "test-repo-eng-1045" "Constructs correct path for Linear branch"
teardown

setup
cd "$REPO_DIR"
output=$(run_gwt feature/add-new-thing-here); exit_code=$?
assert_contains "$output" "test-repo-add-new-thing" "Constructs correct path for regular branch"
teardown

# ----------------------------------------------------------------------------
echo -e "\n${YELLOW}Worktree Creation Tests${NC}"
# ----------------------------------------------------------------------------

setup
cd "$REPO_DIR"
output=$(run_gwt test/eng-3000-new-feature); exit_code=$?
assert_exit_code "0" "$exit_code" "Creates new worktree successfully"
assert_contains "$output" "Worktree created successfully" "Shows success message"
assert_dir_exists "$PARENT_DIR/test-repo-eng-3000" "Worktree directory exists"
teardown

setup
cd "$REPO_DIR"
gwt test/eng-4000-branch-check >/dev/null 2>&1
cd "$PARENT_DIR/test-repo-eng-4000"
current_branch=$(git rev-parse --abbrev-ref HEAD)
assert_equals "test/eng-4000-branch-check" "$current_branch" "Worktree is on correct branch"
teardown

# ----------------------------------------------------------------------------
echo -e "\n${YELLOW}Existing Worktree Handling Tests${NC}"
# ----------------------------------------------------------------------------

setup
cd "$REPO_DIR"
worktree_path="$PARENT_DIR/test-repo-eng-2000"
git worktree add -q -b test/eng-2000-exists "$worktree_path" HEAD
output=$(run_gwt test/eng-2000-exists); exit_code=$?
assert_exit_code "0" "$exit_code" "Returns success for existing worktree"
assert_contains "$output" "Worktree already exists" "Detects existing worktree"
assert_contains "$output" "Changing to existing worktree" "Shows cd message"
teardown

# ----------------------------------------------------------------------------
echo -e "\n${YELLOW}Copy Config Dirs Flag Tests${NC}"
# ----------------------------------------------------------------------------

setup
cd "$REPO_DIR"
# Create a config directory to copy
mkdir -p serena
echo "config" > serena/config.yml
output=$(run_gwt --copy-config-dirs serena test/eng-5000-copy-test); exit_code=$?
assert_exit_code "0" "$exit_code" "--copy-config-dirs flag: worktree created successfully"
assert_dir_exists "$PARENT_DIR/test-repo-eng-5000/serena" "--copy-config-dirs flag: config dir copied to worktree"
teardown

setup
cd "$REPO_DIR"
# Create multiple config directories
mkdir -p serena .vscode
echo "config" > serena/config.yml
echo "settings" > .vscode/settings.json
output=$(run_gwt --copy-config-dirs serena --copy-config-dirs .vscode test/eng-5001-multi-copy); exit_code=$?
assert_exit_code "0" "$exit_code" "--copy-config-dirs flag: multiple dirs - worktree created"
assert_dir_exists "$PARENT_DIR/test-repo-eng-5001/serena" "--copy-config-dirs flag: first dir copied"
assert_dir_exists "$PARENT_DIR/test-repo-eng-5001/.vscode" "--copy-config-dirs flag: second dir copied"
teardown

# ----------------------------------------------------------------------------
echo -e "\n${YELLOW}GWT_COPY_DIRS Env Var Tests${NC}"
# ----------------------------------------------------------------------------

setup
cd "$REPO_DIR"
mkdir -p serena
echo "config" > serena/config.yml
export GWT_COPY_DIRS="serena"
output=$(run_gwt test/eng-5002-env-test); exit_code=$?
assert_exit_code "0" "$exit_code" "GWT_COPY_DIRS env var: worktree created successfully"
assert_dir_exists "$PARENT_DIR/test-repo-eng-5002/serena" "GWT_COPY_DIRS env var: config dir copied via env var"
unset GWT_COPY_DIRS
teardown

setup
cd "$REPO_DIR"
mkdir -p serena .vscode
echo "config" > serena/config.yml
echo "settings" > .vscode/settings.json
export GWT_COPY_DIRS="serena,.vscode"
output=$(run_gwt test/eng-5003-env-multi); exit_code=$?
assert_exit_code "0" "$exit_code" "GWT_COPY_DIRS env var: multiple dirs via comma-separated"
assert_dir_exists "$PARENT_DIR/test-repo-eng-5003/serena" "GWT_COPY_DIRS env var: first dir from env copied"
assert_dir_exists "$PARENT_DIR/test-repo-eng-5003/.vscode" "GWT_COPY_DIRS env var: second dir from env copied"
unset GWT_COPY_DIRS
teardown

# ----------------------------------------------------------------------------
echo -e "\n${YELLOW}Copy Config Dirs Warning Tests${NC}"
# ----------------------------------------------------------------------------

setup
cd "$REPO_DIR"
# Don't create the directory - should warn but continue
output=$(run_gwt --copy-config-dirs nonexistent test/eng-5004-warn-test); exit_code=$?
assert_exit_code "0" "$exit_code" "Non-existent dir: worktree still created successfully"
assert_contains "$output" "Warning" "Non-existent dir: shows warning message"
assert_contains "$output" "nonexistent" "Non-existent dir: warning mentions the directory name"
teardown

# ----------------------------------------------------------------------------
echo -e "\n${YELLOW}Config Command Tests${NC}"
# ----------------------------------------------------------------------------

# Test that gwt config doesn't require git repo
TEST_DIR_CONFIG=$(mktemp -d)
mkdir -p "$TEST_DIR_CONFIG/not-a-repo" && cd "$TEST_DIR_CONFIG/not-a-repo"
source "$PLUGIN_DIR/gwt.plugin.zsh"
output=$(gwt config --help 2>&1); exit_code=$?
assert_exit_code "0" "$exit_code" "gwt config: works outside git repo"
assert_contains "$output" "config" "gwt config: shows config help"
cd "$PLUGIN_DIR"
rm -rf "$TEST_DIR_CONFIG"

# Test _gwt_config_read helper
TEST_DIR_CONFIG=$(mktemp -d)
TEST_ZSHRC="$TEST_DIR_CONFIG/test_zshrc"
echo 'export GWT_COPY_DIRS="serena,.vscode"' > "$TEST_ZSHRC"
result=$(_gwt_config_read "$TEST_ZSHRC")
assert_equals "serena,.vscode" "$result" "_gwt_config_read: extracts dirs from zshrc"
rm -rf "$TEST_DIR_CONFIG"

# Test _gwt_config_read with no config
TEST_DIR_CONFIG=$(mktemp -d)
TEST_ZSHRC="$TEST_DIR_CONFIG/test_zshrc"
echo '# just a comment' > "$TEST_ZSHRC"
result=$(_gwt_config_read "$TEST_ZSHRC")
assert_equals "" "$result" "_gwt_config_read: returns empty when no config"
rm -rf "$TEST_DIR_CONFIG"

# Test _gwt_config_write helper - add to empty file
TEST_DIR_CONFIG=$(mktemp -d)
TEST_ZSHRC="$TEST_DIR_CONFIG/test_zshrc"
echo '# my zshrc' > "$TEST_ZSHRC"
_gwt_config_write "$TEST_ZSHRC" "serena"
assert_contains "$(cat "$TEST_ZSHRC")" 'export GWT_COPY_DIRS="serena"' "_gwt_config_write: adds config to file"
rm -rf "$TEST_DIR_CONFIG"

# Test _gwt_config_write helper - update existing
TEST_DIR_CONFIG=$(mktemp -d)
TEST_ZSHRC="$TEST_DIR_CONFIG/test_zshrc"
echo 'export GWT_COPY_DIRS="old"' > "$TEST_ZSHRC"
_gwt_config_write "$TEST_ZSHRC" "serena,.vscode"
result=$(grep -c 'GWT_COPY_DIRS' "$TEST_ZSHRC")
assert_equals "1" "$result" "_gwt_config_write: replaces existing (no duplicates)"
assert_contains "$(cat "$TEST_ZSHRC")" 'export GWT_COPY_DIRS="serena,.vscode"' "_gwt_config_write: updates with new value"
rm -rf "$TEST_DIR_CONFIG"

# Test _gwt_config_write helper - remove config when empty
TEST_DIR_CONFIG=$(mktemp -d)
TEST_ZSHRC="$TEST_DIR_CONFIG/test_zshrc"
echo 'export GWT_COPY_DIRS="serena"' > "$TEST_ZSHRC"
_gwt_config_write "$TEST_ZSHRC" ""
if grep -q 'GWT_COPY_DIRS' "$TEST_ZSHRC" 2>/dev/null; then
    result="found"
else
    result="removed"
fi
assert_equals "removed" "$result" "_gwt_config_write: removes line when value is empty"
rm -rf "$TEST_DIR_CONFIG"

# ----------------------------------------------------------------------------
echo -e "\n${YELLOW}Security Tests${NC}"
# ----------------------------------------------------------------------------

# Test: Reject path traversal in --copy-config-dirs
setup
cd "$REPO_DIR"
output=$(run_gwt --copy-config-dirs "../../../etc" test/eng-6000-traversal 2>&1); exit_code=$?
assert_exit_code "1" "$exit_code" "Security: rejects path traversal (../)"
assert_contains "$output" "Invalid directory" "Security: shows error for path traversal"
teardown

# Test: Reject absolute paths in --copy-config-dirs
setup
cd "$REPO_DIR"
output=$(run_gwt --copy-config-dirs "/etc/passwd" test/eng-6001-absolute 2>&1); exit_code=$?
assert_exit_code "1" "$exit_code" "Security: rejects absolute paths"
assert_contains "$output" "Invalid directory" "Security: shows error for absolute path"
teardown

# Test: Reject directory names with shell metacharacters
setup
cd "$REPO_DIR"
output=$(run_gwt --copy-config-dirs 'foo;rm -rf /' test/eng-6002-injection 2>&1); exit_code=$?
assert_exit_code "1" "$exit_code" "Security: rejects shell metacharacters"
assert_contains "$output" "Invalid directory" "Security: shows error for metacharacters"
teardown

# Test: Config sanitization - reject values with quotes
TEST_DIR_CONFIG=$(mktemp -d)
TEST_ZSHRC="$TEST_DIR_CONFIG/test_zshrc"
source "$PLUGIN_DIR/gwt.plugin.zsh"
echo '# test' > "$TEST_ZSHRC"
_gwt_config_write "$TEST_ZSHRC" 'serena"; echo "pwned'
content=$(cat "$TEST_ZSHRC")
if [[ "$content" == *"pwned"* ]]; then
    result="vulnerable"
else
    result="safe"
fi
assert_equals "safe" "$result" "Security: config write sanitizes quotes"
rm -rf "$TEST_DIR_CONFIG"

# Test: Verify no git remote operations
setup
cd "$REPO_DIR"
# Create a mock git that logs all commands
mkdir -p "$TEST_DIR/bin"
echo '#!/bin/zsh
echo "$@" >> /tmp/gwt_git_log_$$
/usr/bin/git "$@"' > "$TEST_DIR/bin/git"
chmod +x "$TEST_DIR/bin"
PATH="$TEST_DIR/bin:$PATH" gwt test/eng-6003-no-push >/dev/null 2>&1
if [[ -f "/tmp/gwt_git_log_$$" ]]; then
    if grep -qE '(push|remote add|clone)' "/tmp/gwt_git_log_$$" 2>/dev/null; then
        result="unsafe"
    else
        result="safe"
    fi
    rm -f "/tmp/gwt_git_log_$$"
else
    result="safe"
fi
assert_equals "safe" "$result" "Security: no git push/remote operations"
teardown

# ============================================================================
echo -e "\n${YELLOW}=== Test Results ===${NC}"
echo -e "Total:  $TESTS_RUN"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
# ============================================================================

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
