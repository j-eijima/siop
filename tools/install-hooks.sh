#!/bin/sh
# Points git at the hooks kept in this repository.
#
# Hooks are not cloned with a repository, so this has to be run once per clone.
set -eu
cd "$(dirname "$0")/.."

git config core.hooksPath tools/hooks
echo "core.hooksPath = $(git config core.hooksPath)"
echo "Hooks installed. Remove them with: git config --unset core.hooksPath"
