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
