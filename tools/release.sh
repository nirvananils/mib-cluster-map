#!/bin/bash
# Start a release: checks the tree, tags HEAD and pushes the tag. The
# release workflow (.github/workflows/release.yml) then builds the package
# and publishes it.
#
#   tools/release.sh v1.2.0            release
#   tools/release.sh v1.2.0-beta1      pre-release (any version with a '-')
#   tools/release.sh v1.2.0 --local    build here with build_local.sh and
#                                      publish with gh, without the workflow
#
# Notes: release-notes/<version>.md, first line "# <title>". Without the
# file GitHub writes the notes from the commits.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER=${1:-}
MODE=${2:-}
REMOTE=${RELEASE_REMOTE:-origin}

case "$VER" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "usage: $0 vMAJOR.MINOR.PATCH[-label] [--local]"; exit 2 ;;
esac
case "$MODE" in ''|--local) ;; *) echo "unknown option: $MODE"; exit 2 ;; esac

cd "$ROOT"
[ -z "$(git status --porcelain)" ] || { echo "ERROR: uncommitted changes; commit or stash them first"; exit 1; }
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = main ] || echo "NOTE: releasing from branch $BRANCH, not main"
git fetch --quiet "$REMOTE"
if git rev-parse -q --verify "refs/tags/$VER" >/dev/null || \
   git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$VER" >/dev/null 2>&1; then
  echo "ERROR: tag $VER already exists"; exit 1
fi
if [ "$(git rev-list --count "$REMOTE/$BRANCH..HEAD" 2>/dev/null || echo 1)" != 0 ]; then
  echo "ERROR: HEAD is not pushed to $REMOTE/$BRANCH; push it first"; exit 1
fi
NOTES="release-notes/$VER.md"
if [ -f "$NOTES" ]; then
  echo "Notes: $NOTES"
else
  echo "NOTE: no $NOTES; the release notes are generated from the commits"
fi
case "$VER" in *-*) KIND=pre-release ;; *) KIND=release ;; esac
echo "Commit: $(git log -1 --format='%h %s')"
read -r -p "Publish $VER as a $KIND? [y/N] " ok
[ "$ok" = y ] || [ "$ok" = Y ] || { echo "Cancelled."; exit 1; }

git tag -a "$VER" -m "$VER"

if [ "$MODE" = --local ]; then
  RELEASE_VERSION="$VER" ./build_local.sh all || { git tag -d "$VER"; exit 1; }
  args=()
  title="$VER"
  [ "$KIND" = pre-release ] && args+=(--prerelease)
  if [ -f "$NOTES" ]; then
    first=$(head -n 1 "$NOTES")
    if [ "${first#\# }" != "$first" ]; then
      title="${first#\# }"
      tail -n +2 "$NOTES" > "$ROOT/dist/notes.md"
    else
      cp "$NOTES" "$ROOT/dist/notes.md"
    fi
    args+=(--notes-file "$ROOT/dist/notes.md")
  else
    args+=(--generate-notes)
  fi
  git push "$REMOTE" "$VER"
  # The workflow also starts on the tag; it stops at gh release create
  # because this release already exists.
  gh release create "$VER" "dist/mib-cluster-map_$VER.zip" "dist/mib-cluster-map_$VER.zip.sha256" \
    --title "$title" --verify-tag "${args[@]}"
else
  git push "$REMOTE" "$VER"
  echo "Tag pushed. Follow the build: gh run watch \$(gh run list -w release -L 1 --json databaseId -q '.[0].databaseId')"
fi
