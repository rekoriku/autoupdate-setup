#!/usr/bin/env bash
# --------------------------------------------------------------------
# Template script to push the current project to a new public GitHub
# repository via WSL + GitHub CLI (`gh`) with minimal manual steps.
# Fill in the placeholders below or override via environment variables.
# --------------------------------------------------------------------
set -euo pipefail

# Required placeholders (override via env vars or edit here)
PROJECT_DIR="${PROJECT_DIR:-/mnt/c/tools/TEST}"   # Absolute path to your project in WSL
REPO_NAME="${REPO_NAME:-autoupdate-setup}"        # New repository name
GIT_USER_NAME="${GIT_USER_NAME:-YourName}"        # Your git user.name
GIT_USER_EMAIL="${GIT_USER_EMAIL:-you@example.com}" # Your git user.email

# Files to include in the first commit (edit as needed)
INCLUDE_PATHS=(
  "autoupdate.sh"
  "tests/test_autoupdate.py"
  "OHJE.md"
)

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

main() {
  require_cmd git
  require_cmd gh

  cd "$PROJECT_DIR"

  # Optional: set a Windows browser for the gh web login flow when needed.
  : "${BROWSER:=cmd.exe /C start}"
  export BROWSER

  # Authenticate gh if not already logged in.
  if ! gh auth status >/dev/null 2>&1; then
    echo "gh not authenticated. Starting web login..."
    gh auth login -w --hostname github.com --git-protocol https
  fi

  # Initialize git if needed.
  if [ ! -d .git ]; then
    git init
  fi

  git config user.name "$GIT_USER_NAME"
  git config user.email "$GIT_USER_EMAIL"

  # Stage requested files (skip missing ones silently).
  for path in "${INCLUDE_PATHS[@]}"; do
    [ -e "$path" ] && git add "$path"
  done

  # Commit if there is anything to commit.
  if ! git diff --cached --quiet; then
    git commit -m "Initial commit"
  else
    echo "Nothing to commit; working tree already clean."
  fi

  # Create and push the new repo.
  gh repo create "$REPO_NAME" --public --source . --remote origin --push

  echo "Done. Repository created and pushed: https://github.com/$(gh api user --jq .login)/${REPO_NAME}"
}

main "$@"

