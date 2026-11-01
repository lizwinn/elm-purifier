# SPDX-License-Identifier: MIT
#
# What `elm-purifier publish` builds: buildElmProject on a project
# directory, outside any flake, with the compiler the CLI runs. Its
# `package` attribute is the package the publish checks against.
{
  # The project directory, as an absolute path string.
  projectDir,
  # The nixpkgs the CLI was built with.
  nixpkgs,
  # The store path of the compiler the lock was made with.
  elm,
}:
let
  pkgs = import nixpkgs { };
  buildElmProject = pkgs.callPackage ./build-elm-project.nix { elm-purifier = { }; };
in
buildElmProject {
  src = /. + projectDir;
  elm = builtins.storePath elm;
}
