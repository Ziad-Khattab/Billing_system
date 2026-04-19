# Git Workflow Guide — Team Project

## Daily Workflow

```bash
# 1. Before starting work — pull latest from YOUR fork
git pull origin main

# 2. Pull updates from original repo (teammates' work)
git fetch upstream
git merge upstream/main
# If conflicts: fix them, then git add . && git commit

# 3. Do your work (code, test)

# 4. Stage and commit
git add -A
git commit -m "feat: add customer servlet and DAO"

# 5. Push to YOUR fork
git push origin main
```

## Commit Message Format
```
type: short description

Types:
  feat:     New feature (feat: add customer search API)
  fix:      Bug fix (fix: handle null pathInfo in servlet)
  docs:     Documentation (docs: add SQL cheatsheet)
  refactor: Code change that doesn't add feature/fix bug
  style:    Formatting, missing semicolons, etc.
  test:     Adding tests
  chore:    Build config, dependencies, gitignore
```

## Creating a Pull Request to Team Repo
1. Push your branch to YOUR fork
2. Go to `github.com/Ziad-Khattab/Billing_system`
3. Click "Contribute" → "Open pull request"
4. Base: `fouad64/Billing_system` main ← Compare: `Ziad-Khattab/Billing_system` main
5. Write clear description of what you changed
6. Request review from teammate

## Handling Merge Conflicts
```bash
# After git merge upstream/main, if conflicts appear:
# 1. Open conflicting file — look for markers:
<<<<<<< HEAD
your code
=======
teammate's code
>>>>>>> upstream/main

# 2. Edit to keep the right version (or combine both)
# 3. Remove the <<<< ==== >>>> markers
# 4. Stage and commit
git add .
git commit -m "merge: resolve conflict in DB.java"
```

## Golden Rules
- **Never force push** (`git push -f`) to shared branches
- **Never commit** `.idea/`, `node_modules/`, `.env`, credentials
- **Always pull before push** — avoids unnecessary merge conflicts
- **Small, focused commits** — one feature per commit, not "did a bunch of stuff"
- **Test before committing** — broken code blocks teammates
