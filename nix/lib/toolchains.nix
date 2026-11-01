# SPDX-License-Identifier: MIT
#
# The Elm toolchains elm-purifier builds with, by compiler version: the
# compiler, the elm-test release for it, and the arguments that keep that
# elm-test to the locked packages. One toolchain is nixpkgs' Elm, with
# nixpkgs' elm-test (pkgs/elm-test, which puts its socket where TMPDIR
# says). The other is Elm 0.19.1, which most published applications pin,
# built by this flake on the same package set (pkgs/elm_0_19_1 and
# pkgs/elm-test_0_19_1).
#
# elm-test solves the test dependencies itself. The 0.19.1 releases always
# try the packages in ELM_HOME first. The later releases ask the package
# server first for a package project, unless they run with --offline.
{ elm-purifier, elmPackages }:
{
  "0.19.1" = {
    elm = elm-purifier.elm_0_19_1;
    elm-test = elm-purifier.elm-test_0_19_1;
    elmTestOfflineArgs = [ ];
  };
  ${elmPackages.elm.version} = {
    inherit (elmPackages) elm;
    inherit (elm-purifier) elm-test;
    elmTestOfflineArgs = [ "--offline" ];
  };
}
