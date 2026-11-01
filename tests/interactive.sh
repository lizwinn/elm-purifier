#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Tests what runs outside the Nix sandbox: the lock run, the interactive
# commands on the locked packages, and the publish check. Run it from the
# repository root; the lock run needs the network.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
cli=$(nix build --no-link --print-out-paths .#cli)/bin/elm-purifier
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
  echo "interactive.sh: $*" >&2
  exit 1
}

# The package directories under the interactive ELM_HOME of a project.
installed() {
  (cd "$1/elm-stuff/elm-purifier/home" && find . -mindepth 5 -maxdepth 5 -type d -path './*/packages/*' | sort)
}

# The package directories a lockfile records.
locked() {
  nix shell 'nixpkgs#jq' -c jq -r --arg v "$(nix shell 'nixpkgs#jq' -c jq -r .elmVersion "$1")" \
    '.downloads[].path | "./\($v)/packages/\(.)"' "$1" | sort
}

cp -r tests/fixtures/app tests/fixtures/package tests/fixtures/shared "$work/"
chmod -R u+w "$work"

echo "== the lock run reproduces each committed lockfile"
for project in app package shared/app; do
  (cd "$work/$project" && "$cli" lock)
  cmp "$work/$project/elm-purifier.lock.json" "tests/fixtures/$project/elm-purifier.lock.json" ||
    fail "the lock of $project differs from the committed one"
done

echo "== elm and test run on the locked packages"
(cd "$work/app" && "$cli" elm make src/Main.elm --output="$work/main.js")
[ "$(installed "$work/app")" = "$(locked "$work/app/elm-purifier.lock.json")" ] ||
  fail "elm downloaded packages the lock does not record"
(cd "$work/app" && "$cli" test)
(cd "$work/package" && "$cli" test)
[ "$(installed "$work/package")" = "$(locked "$work/package/elm-purifier.lock.json")" ] ||
  fail "elm-test downloaded packages the lock does not record"
nix shell 'nixpkgs#nodejs' -c node "$root/tests/run-worker.js" "$work/main.js" Main Nix | grep -qx 'Hello, Nix!' ||
  fail "the interactively compiled Main printed something else"

echo "== publish checks the documentation against the Nix build"
(cd "$work/package" && "$cli" publish --check)

echo "== a changed elm.json falls back to the usual ELM_HOME"
sed -i 's/"1.0.0"/"1.0.1"/' "$work/package/elm.json"
(cd "$work/package" && "$cli" elm --version 2>&1) | grep -q 'elm.json changed' ||
  fail "the CLI did not warn about the stale lockfile"

echo "interactive.sh: all passed"
