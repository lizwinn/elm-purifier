# SPDX-License-Identifier: MIT
#
# The packages of elm-purifier. `lib` is this flake's library, which has
# the shared purifier library as `lib.purifier`. The command itself,
# pkgs/cli, is added by the package overlay, because it carries the
# source of the purifier input of this flake.
{ callPackage, lib, ... }:
{
  # Elm 0.19.1 and its elm-test releases, beside nixpkgs' Elm.
  elm_0_19_1 = callPackage ./elm_0_19_1 { inherit (lib) purifier; };
  elm-test_0_19_1 = callPackage ./elm-test_0_19_1 { };
  # elm-test for Elm 0.19.1 projects on elm-explorations/test 1.x.
  elm-test_0_19_1-revision9 = callPackage ./elm-test_0_19_1-revision9 { };
  # nixpkgs' elm-test, with its socket where TMPDIR says.
  elm-test = callPackage ./elm-test { };
}
