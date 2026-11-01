#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Locks every fixture under tests/fixtures, and every project under
# tests/real-world at its pinned commit, again with the elm-purifier of
# this checkout. Run it from the repository root after a change to the
# lock format or the fixtures; it needs the network.
set -euo pipefail
cd "$(dirname "$0")/.."
cli=$(nix build --no-link --print-out-paths .#cli)/bin/elm-purifier
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

(cd tests/fixtures/app && "$cli" lock)
(cd tests/fixtures/package && "$cli" lock)
(cd tests/fixtures/shared/app && "$cli" lock)

# The pinned commits are the ones tests/default.nix fetches.
for project in rtfeldman/elm-spa-example/cb32acd73c3d346d0064e7923049867d8ce67193 \
  elm-community/list-extra/46a4817f2df99ce3379390db21348177ac95056d; do
  name=$(echo "$project" | cut -d/ -f2)
  source=$(nix flake prefetch --json "github:$project" | nix shell 'nixpkgs#jq' -c jq -r .storePath)
  cp -r "$source" "$work/$name"
  chmod -R u+w "$work/$name"
  (cd "$work/$name" && "$cli" lock)
  cp "$work/$name/elm-purifier.lock.json" "tests/real-world/$name/elm-purifier.lock.json"
done
