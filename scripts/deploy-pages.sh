#!/usr/bin/env bash
#
# Builds the Flutter web app and pushes it to the `gh-pages` branch, which
# GitHub Pages serves at:
#
#   https://<user>.github.io/<repo>/
#
# Nothing runs this automatically. Run it by hand, from anywhere in the
# repository, whenever you want to publish:
#
#   scripts/deploy-pages.sh
#
# `main` never contains build output: the site is built in a temporary
# folder and committed only to `gh-pages`. The first time, set the
# repository's Settings > Pages > Source to "Deploy from a branch", with the
# `gh-pages` branch and the `/ (root)` folder.

set -euo pipefail

FLUTTER="${FLUTTER:-flutter}"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# The repository's name, from the `origin` remote. GitHub Pages serves a
# project's site under /<repo>/, so the Flutter app must know that path.
REPO="$(basename -s .git "$(git remote get-url origin)")"
BASE="/$REPO/"

if [ -n "$(git status --porcelain)" ]; then
  echo "Note: you have uncommitted changes. They will be deployed too."
fi

# The platform folders aren't committed. Generate them if they're missing.
if [ ! -d flutter/web ]; then
  echo "flutter/web is missing. Generating the platform folders first..."
  dart run tool/setup_platforms.dart
fi

SITE="$(mktemp -d)"
WORKTREE="$(mktemp -d)"
cleanup() {
  git worktree remove --force "$WORKTREE" 2>/dev/null || true
  rm -rf "$SITE" "$WORKTREE"
}
trap cleanup EXIT

echo "1/2 Building the Flutter web app..."
# --base-href tells the app it lives under /<repo>/, not at the root of the
# domain. Without it, it can't find its own files.
(cd flutter && $FLUTTER build web --release --base-href "$BASE")
cp -R flutter/build/web/. "$SITE"/
# Tells GitHub Pages to serve the files as they are, without running Jekyll.
touch "$SITE/.nojekyll"

echo "2/2 Pushing to the gh-pages branch..."
# A worktree is a second checkout of the same repository in another folder.
# It lets us commit to gh-pages without leaving (or touching) main.
git fetch --quiet origin gh-pages 2>/dev/null || true
if git show-ref --verify --quiet refs/remotes/origin/gh-pages; then
  git worktree add --quiet -B gh-pages "$WORKTREE" origin/gh-pages
else
  # First deploy: start gh-pages as an empty branch with no history.
  git worktree add --quiet --detach "$WORKTREE"
  git -C "$WORKTREE" checkout --quiet --orphan gh-pages
  git -C "$WORKTREE" rm -rf --quiet .
fi

# Replace everything on the branch with the new site.
find "$WORKTREE" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$SITE"/. "$WORKTREE"/

git -C "$WORKTREE" add -A
if git -C "$WORKTREE" diff --cached --quiet; then
  echo "Nothing changed since the last deploy."
else
  COMMIT="$(git rev-parse --short HEAD)"
  git -C "$WORKTREE" commit --quiet -m "Deploy from main at $COMMIT"
  git -C "$WORKTREE" push --quiet origin gh-pages
  OWNER="$(git remote get-url origin | sed -E 's#.*[:/]([^/]+)/[^/]+$#\1#')"
  URL="https://$OWNER.github.io$BASE"
  echo "Deployed. In a minute or two, it's live at $URL"
  echo
  echo "Add this row to DEPLOYS.md:"
  echo "| $(date +%Y-%m-%d) | Web app | GitHub Pages | $URL | main at \`$COMMIT\` |"
fi
