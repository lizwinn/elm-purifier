# SPDX-License-Identifier: MIT
#
# What `elm-purifier lock` checks with, and what `elm-purifier elm` and
# `elm-purifier test` run on: the package cache of the lockfile, the same
# derivation the sandboxed build uses. The CLI builds it with an out-link
# in elm-stuff, which is the GC root that keeps every locked archive alive,
# and runs the compiler on a writable copy of it.
{
  lockFile,
  # The nixpkgs the CLI was built with.
  nixpkgs,
  # The shared purifier library, as pinned in this flake's flake.lock.
  # Its root default.nix is its entry point for code outside a flake.
  purifierSrc,
}:
let
  pkgs = import nixpkgs { };
  purifier = import purifierSrc { inherit (pkgs) lib; };
in
pkgs.callPackage ./elm-home.nix { inherit lockFile purifier; }
