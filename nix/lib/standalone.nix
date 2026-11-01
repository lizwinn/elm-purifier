# SPDX-License-Identifier: MIT
#
# The builder outside a flake: a nixpkgs, the shared purifier library and
# the builder of nix/lib/build-elm-project.nix, called the way the default
# overlay calls it. `elm-purifier publish` builds the release with it
# (project.nix), and the lockfile message checks evaluate it
# (tests/default.nix).
{ nixpkgs, purifierSrc }:
let
  pkgs = import nixpkgs { };
  purifier = import purifierSrc { inherit (pkgs) lib; };
  elm-purifier = import ../../pkgs {
    inherit (pkgs) callPackage;
    lib = pkgs.lib // {
      inherit purifier;
    };
  };
in
{
  inherit pkgs purifier;
  buildElmProject = pkgs.callPackage ./build-elm-project.nix { inherit elm-purifier purifier; };
}
