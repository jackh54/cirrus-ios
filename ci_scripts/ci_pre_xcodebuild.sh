#!/bin/sh
# Xcode Cloud runs this before xcodebuild. A build started by a release tag
# (vX.Y.Z) must ship exactly that version, so refuse to archive when the tag and
# MARKETING_VERSION in project.yml disagree. Builds from branches pass through.
# Xcode Cloud sets the build number itself (CI_BUILD_NUMBER).
set -eu

if [ -z "${CI_TAG:-}" ]; then
  echo "Branch build (${CI_BRANCH:-unknown}), build ${CI_BUILD_NUMBER:-?}: no version check."
  exit 0
fi

tag_version="${CI_TAG#v}"
case "$tag_version" in
  *[!0-9.]* | "" | .* | *. | *..*)
    echo "error: tag '$CI_TAG' is not of the form vX.Y.Z" >&2
    exit 1
    ;;
esac

project_version=$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' "$CI_PRIMARY_REPOSITORY_PATH/project.yml" | head -n 1)

if [ "$tag_version" != "$project_version" ]; then
  echo "error: tag $CI_TAG does not match MARKETING_VERSION $project_version in project.yml." >&2
  echo "Run scripts/release.sh $tag_version to bump and tag together." >&2
  exit 1
fi

echo "Release build: version $tag_version, build ${CI_BUILD_NUMBER:-?}."
