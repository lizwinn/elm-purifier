# SPDX-License-Identifier: MIT
#
# The default package overlay. It adds the packages of pkgs/ under
# `pkgs.elm-purifier` (`.cli` and `.elm_0_19_1`), and the builder
# `pkgs.buildElmProject` (nix/lib/build-elm-project.nix) beside them,
# where nixpkgs keeps its own builders, so a package written for
# callPackage takes it by name. A consumer that lists this flake in
# `projects` holds it as `elm-purifier/default`, which its package sets
# apply by default.
{ closure-lib, ... }:
let
  packages = closure-lib.caisson.nixpkgs.mkPackagesOverlay ../../pkgs "elm-purifier";
in
{
  overlay =
    final: prev:
    packages final prev
    // {
      buildElmProject = final.callPackage ../../nix/lib/build-elm-project.nix { };
    };
}
