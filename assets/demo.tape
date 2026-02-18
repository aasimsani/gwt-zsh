Output assets/demo.gif

Set FontSize 20
Set Width 1200
Set Height 600
Set Theme "Catppuccin Frappe"
Set Shell zsh
Set TypingSpeed 50ms
Set Padding 20

# Hidden setup — isolated temp repo so we don't touch the real one
Hide
Type "source ~/.zshrc"
Enter
Sleep 2s
Type "unsetopt correct correctall 2>/dev/null"
Enter
Sleep 200ms
Type "export GWT_PLUGIN_DIR=$(pwd)"
Enter
Sleep 200ms
Type "export DEMO_DIR=$GWT_PLUGIN_DIR/demo-repo && rm -rf $DEMO_DIR && mkdir -p $DEMO_DIR && cd $DEMO_DIR"
Enter
Sleep 200ms
Type "git init -q -b main && git config user.email demo@test.com && git config user.name Demo"
Enter
Sleep 200ms
Type "echo init > README.md && git add . && git commit -q -m init"
Enter
Sleep 500ms
Type "source $GWT_PLUGIN_DIR/gwt.plugin.zsh"
Enter
Sleep 1s
# Clear post-create command so config shows (none) later
Type "sed -i '' '/GWT_POST_CREATE_CMD/d' ~/.config/gwt/config"
Enter
Sleep 500ms
Type "unset GWT_POST_CREATE_CMD"
Enter
Sleep 500ms
Ctrl+L
Show

# Opening — neofetch with custom config
Set TypingSpeed 20ms
Type "neofetch --config $GWT_PLUGIN_DIR/assets/neofetch.conf"
Enter
Set TypingSpeed 50ms
Sleep 3s

Ctrl+L
Sleep 500ms

# 1. Create worktrees
Type "# Create worktrees — just type gwt <branch>"
Enter
Sleep 1s
Type "gwt feature/api-v2"
Enter
Sleep 2.5s

Type "gwt feature/api-v2-tests"
Enter
Sleep 2.5s

Ctrl+L
Sleep 500ms

# 2. Navigate between worktrees
Type "# Navigate up with gwt .. and to root with gwt ..."
Enter
Sleep 1s
Type "gwt .."
Enter
Sleep 2s

Type "gwt feature/api-v2-tests"
Enter
Sleep 1.5s
Type "gwt ..."
Enter
Sleep 2s

Ctrl+L
Sleep 500ms

# 3. List all worktrees
Type "# See all worktrees at a glance"
Enter
Sleep 1s
Type "gwt --list"
Enter
Sleep 2.5s

Ctrl+L
Sleep 500ms

# 4. Prune worktrees
Type "# Clean up with interactive multi-select pruning"
Enter
Sleep 1s
Type "gwt --prune"
Enter
Sleep 1s
Tab
Enter
Sleep 1s
Type "y"
Enter
Sleep 500ms
Type "DELETE"
Enter
Sleep 2s

Ctrl+L
Sleep 500ms

# 5. Configure post-create hook
Type "# Set a post-create hook — run anything after worktree creation"
Enter
Sleep 1s
Type "gwt --config"
Enter
Sleep 1s
# fzf menu: navigate down to "Post-create command" (5th item)
Down
Down
Down
Down
Enter
Sleep 1s
# Sub-menu: 1) Set command
Type "1"
Enter
Sleep 500ms
Type "claude"
Enter
Sleep 1.5s
# Back in fzf menu — navigate to "Done" (7th item, 6 downs)
Down
Down
Down
Down
Down
Down
Enter
Sleep 1s

Ctrl+L
Sleep 500ms

# 6. Create worktree — post-create hook runs claude
Type "# Now every new worktree auto-launches claude"
Enter
Sleep 1s
Type "gwt feature/api-v2"
Enter
Sleep 3s

# Let claude show for a moment, then exit
Type "/exit"
Enter
Sleep 2s

# Restore config and clean up temp repo (hidden)
Hide
Type "sed -i '' '/GWT_POST_CREATE_CMD/d' ~/.config/gwt/config"
Enter
Type "echo 'GWT_POST_CREATE_CMD=claude' >> ~/.config/gwt/config"
Enter
Type "cd $GWT_PLUGIN_DIR && rm -rf $DEMO_DIR demo-repo-api-v2 demo-repo-api-v2-api-v2-tests"
Enter
Sleep 500ms
Show
