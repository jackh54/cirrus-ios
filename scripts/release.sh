#!/bin/sh
# Cut a release: bump MARKETING_VERSION, commit, tag vX.Y.Z, push, and create a
# GitHub release. Pushing the tag starts the Xcode Cloud "Release" workflow,
# which archives the app and sends it to the external TestFlight group.
#
#   scripts/release.sh 0.2.0
set -eu

version="${1:-}"
case "$version" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "usage: scripts/release.sh X.Y.Z" >&2; exit 1 ;;
esac
case "$version" in *[!0-9.]*) echo "error: '$version' is not X.Y.Z" >&2; exit 1 ;; esac

cd "$(dirname "$0")/.."
tag="v$version"

[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "error: release from main" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "error: working tree not clean" >&2; exit 1; }
git fetch --quiet --tags origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "error: main is not in sync with origin/main" >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then echo "error: $tag already exists" >&2; exit 1; fi

current=$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml | head -n 1)
highest=$(printf '%s\n%s\n' "$current" "$version" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
if [ "$version" = "$current" ]; then
  echo "Version is already $version; tagging the current commit."
elif [ "$highest" != "$version" ]; then
  echo "error: $version is lower than the current version $current" >&2; exit 1
else
  sed -i '' "s/^\( *MARKETING_VERSION: *\).*/\1\"$version\"/" project.yml
  sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $version;/" CirrusApp.xcodeproj/project.pbxproj
  git add project.yml CirrusApp.xcodeproj/project.pbxproj
  git commit --quiet -m "chore(release): $version"
fi

git tag -a "$tag" -m "Cirrus $version"
git push --quiet origin main "$tag"
gh release create "$tag" --title "Cirrus $version" --generate-notes --verify-tag

echo "Released $tag. Xcode Cloud is archiving it for external TestFlight."
