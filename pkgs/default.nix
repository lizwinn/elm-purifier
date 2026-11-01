# SPDX-License-Identifier: MIT
{ callPackage, ... }:
{
  # The elm-purifier command.
  cli = callPackage ./cli {
    version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ../version.txt);
  };
  # Elm 0.19.1 and its elm-test, beside nixpkgs' Elm.
  elm_0_19_1 = callPackage ./elm_0_19_1 { };
  elm-test_0_19_1 = callPackage ./elm-test_0_19_1 { };
  # nixpkgs' elm-test, with its socket where TMPDIR says.
  elm-test = callPackage ./elm-test { };
}
