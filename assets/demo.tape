Output assets/demo.gif

Set FontSize 20
Set Width 1200
Set Height 600
Set Theme "Catppuccin Frappe"
Set Shell zsh
Set TypingSpeed 80ms
Set Padding 20

# Hidden setup: source the plugin
Hide
Type "source gwt.plugin.zsh"
Enter
Sleep 1s
Show

# 1. Create first worktree
Type "gwt feature/api-v2"
Enter
Sleep 2s

# 2. Create second worktree
Type "gwt feature/api-v2-tests"
Enter
Sleep 2s

# 3. Navigate back to root
Type "gwt ..."
Enter
Sleep 1.5s

# 4. List all worktrees
Type "gwt --list"
Enter
Sleep 2s

# 5. Prune worktrees with fzf
Type "gwt --prune"
Enter
Sleep 1s
Tab
Tab
Enter
Sleep 1s
Type "y"
Enter
Sleep 500ms
Type "DELETE"
Enter
Sleep 2s
