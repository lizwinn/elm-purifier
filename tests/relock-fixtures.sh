#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Locks every fixture under tests/fixtures again with the elm-purifier of
# this checkout. Run it from the repository root after a change to the
# lock format or the fixtures; it needs the network.
set -euo pipefail
cd "$(dirname "$0")/.."
cli=$(nix build --no-link --print-out-paths .#cli)/bin/elm-purifier

(cd tests/fixtures/app && "$cli" lock)
(cd tests/fixtures/package && "$cli" lock)
(cd tests/fixtures/shared/app && "$cli" lock)
