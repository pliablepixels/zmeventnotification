#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

# Always target the pliablepixels fork, never upstream
GH_REPO="pliablepixels/zmeventnotification"

# --- Read version ---
if [ ! -f ./VERSION ]; then
    echo "ERROR: VERSION file not found"
    exit 1
fi
VER=$(cat ./VERSION | tr -d '[:space:]')

echo "=== Release v${VER} ==="
echo

# --- Preflight checks ---
if ! command -v git-cliff &>/dev/null; then
    echo "ERROR: git-cliff not found. Install it from https://git-cliff.org"
    exit 1
fi
if ! command -v gh &>/dev/null; then
    echo "ERROR: gh CLI not found. Install it from https://cli.github.com"
    exit 1
fi
export GITHUB_TOKEN=$(gh auth token)

# --- Step 1: Check if tag already exists ---
if git rev-parse "v${VER}" &>/dev/null; then
    echo "Tag v${VER} already exists."
    read -p "Overwrite existing release? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "  Deleting old release and tag v${VER} ..."
        gh release delete "v${VER}" --repo "$GH_REPO" --yes 2>/dev/null || true
        git tag -d "v${VER}"
        git push origin --delete "v${VER}" 2>/dev/null || true
    else
        echo "Aborted."
        exit 0
    fi
    echo
fi

# --- Step 2: Check for uncommitted files ---
DIRTY_FILES=$(git status --porcelain)
if [ -n "$DIRTY_FILES" ]; then
    # Check if the only dirty file is VERSION
    NON_VERSION=$(echo "$DIRTY_FILES" | grep -v ' VERSION$' || true)
    if [ -n "$NON_VERSION" ]; then
        echo "ERROR: Uncommitted files besides VERSION:"
        echo "$NON_VERSION"
        exit 1
    fi
    echo "Committing VERSION file ..."
    git add VERSION
    git commit -m "chore: bump version to v${VER}"
    git push origin master
    echo "  Done."
    echo
fi

# --- Confirm before proceeding ---
BRANCH=$(git rev-parse --abbrev-ref HEAD)
REMOTE_URL=$(git remote get-url origin)
echo "--- Release summary ---"
echo "  Version:      v${VER}"
echo "  Branch:       ${BRANCH}"
echo "  Remote:       ${REMOTE_URL}"
echo "  GitHub repo:  ${GH_REPO}"
echo
echo "This will: generate CHANGELOG, commit, tag, push, and create GitHub release."
read -p "Proceed? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi
echo

# --- Step 3: Generate and commit changelog ---
echo "Generating CHANGELOG.md ..."
git-cliff --tag "v${VER}" -o CHANGELOG.md
echo "  Done."

echo "Committing CHANGELOG.md ..."
git add CHANGELOG.md
git commit -m "docs: update CHANGELOG for v${VER}"
git push origin master
echo "  Done."
echo

# --- Step 4: Tag ---
echo "Creating tag v${VER} ..."
git tag -a "v${VER}" -m "v${VER}"
git push origin --tags
echo "  Done."
echo

# --- Step 5: Create GitHub Release ---
echo "Creating GitHub Release v${VER} ..."
NOTES_FILE=$(mktemp)
git-cliff --latest --strip header > "$NOTES_FILE" 2>/dev/null
gh release create "v${VER}" --repo "$GH_REPO" --title "v${VER}" --notes-file "$NOTES_FILE"
rm -f "$NOTES_FILE"
echo "  Done."

echo
echo "=== Release v${VER} complete ==="
