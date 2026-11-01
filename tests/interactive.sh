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

echo "== the lock run reproduces each real-world lockfile"
for project in rtfeldman/elm-spa-example/cb32acd73c3d346d0064e7923049867d8ce67193 \
  elm-community/list-extra/46a4817f2df99ce3379390db21348177ac95056d; do
  name=$(echo "$project" | cut -d/ -f2)
  source=$(nix flake prefetch --json "github:$project" | nix shell 'nixpkgs#jq' -c jq -r .storePath)
  cp -r "$source" "$work/$name"
  chmod -R u+w "$work/$name"
  (cd "$work/$name" && "$cli" lock)
  cmp "$work/$name/elm-purifier.lock.json" "tests/real-world/$name/elm-purifier.lock.json" ||
    fail "the lock of $name differs from the committed one"
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

echo "== the language server works on the locked packages"
cp -r tests/fixtures/app "$work/lsp"
chmod -R u+w "$work/lsp"
printf '\n\nprobe : Int\nprobe =\n    notDefinedAnywhere\n' >> "$work/lsp/src/Main.elm"
els=$(nix build --no-link --print-out-paths 'nixpkgs#elmPackages.elm-language-server')/bin/elm-language-server
(cd "$work/lsp" && nix shell 'nixpkgs#python3' -c python3 -I "$root/tests/lsp-probe.py" src/Main.elm -- "$cli" exec "$els" --stdio) |
  grep -q notDefinedAnywhere || fail "elm-language-server reported nothing about the planted error"

echo "== a tampered hash names the lockfile and the command to run"
cp -r tests/fixtures/app "$work/tampered"
chmod -R u+w "$work/tampered"
sed -i '0,/"hash": "sha256-/s//"hash": "sha256-AAAA/' "$work/tampered/elm-purifier.lock.json"
(cd "$work/tampered" && "$cli" elm make src/Main.elm --output=/dev/null 2>&1 || true) |
  grep -q 'run `elm-purifier relock`' || fail "a tampered hash gave no relock hint"

echo "== a lockfile that does not parse names the command to run"
cp -r tests/fixtures/app "$work/malformed"
chmod -R u+w "$work/malformed"
echo '{ "version": 1,' > "$work/malformed/elm-purifier.lock.json"
(cd "$work/malformed" && "$cli" elm make src/Main.elm --output=/dev/null 2>&1 || true) |
  grep -q 'run `elm-purifier lock`' || fail "a malformed lockfile gave no lock hint"

echo "interactive.sh: all passed"
