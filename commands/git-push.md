# Git Commit and Push

Commit staged/unstaged changes and push to remote.

## Usage

`/git-push [commit message]`

## Workflow

1. **Check status**:
   ```bash
   git status
   git diff --stat
   ```

2. **Stage changes**:
   - If no staged changes, run `git add .`
   - Confirm files to be committed

3. **Generate commit message**:
   - If `$ARGUMENTS` provided, use it as commit message
   - Otherwise, analyze changes and generate a concise message:
     - Summarize the nature of changes (feat/fix/refactor/docs/test/chore)
     - Focus on "why" not "what"
     - Follow conventional commits format

4. **Commit**:
   ```bash
   git commit -m "<type>: <message>"
   ```

5. **Push**:
   ```bash
   git push
   ```
   - If no upstream, use `git push -u origin <branch>`

6. **Report result**:
   ```
   Committed: <short SHA> - <message>
   Pushed to: <remote>/<branch>
   Files changed: X insertions(+), Y deletions(-)
   ```

## Arguments

$ARGUMENTS:
- Optional commit message
- If not provided, AI will generate based on diff

## Safety

- Never force push to main/master
- Never commit files matching: `.env*`, `*credentials*`, `*secret*`
- Warn if committing large files (>1MB)
- Warn if committing node_modules, dist, build artifacts

## Examples

```
/git-push                           # Auto-generate commit message
/git-push fix: resolve login bug    # Use provided message
/git-push "feat: add dark mode"     # Quoted message with spaces
```
