# SPDX-License-Identifier: MIT
#
# The default package overlay. It adds the packages of pkgs/ under
# `pkgs.elm-purifier` (`.elm_0_19_1` and the elm-test releases), the command
# as `pkgs.elm-purifier.cli`, and the builder `pkgs.buildElmProject`
# (nix/lib/build-elm-project.nix) beside them, where nixpkgs keeps its own
# builders. A package written for callPackage takes the builder by name, and
# `buildElmProject.override` replaces what it takes. A consumer that lists
# this flake in `projects` holds the overlay as `elm-purifier/default`, which
# its package sets apply by default.
#
# The command carries the source of the purifier input of this flake, pinned
# in flake.lock, for what it builds outside a flake build.
{ closure-lib, closure-inputs, ... }:
let
  packages = closure-lib.caisson.nixpkgs.mkPackagesOverlay ../../pkgs "elm-purifier";
in
{
  overlay =
    final: prev:
    let
      base = packages final prev;
    in
    base
    // {
      elm-purifier = base.elm-purifier // {
        cli = final.callPackage ../../pkgs/cli {
          version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ../../version.txt);
          purifierSrc = closure-inputs.purifier;
        };
      };
      buildElmProject = final.callPackage ../../nix/lib/build-elm-project.nix {
        inherit (closure-lib) purifier;
      };
    };
}
