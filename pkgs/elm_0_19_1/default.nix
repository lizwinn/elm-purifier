# SPDX-License-Identifier: MIT
#
# Elm 0.19.1, built with nixpkgs' recipe for its own Elm compiler on the
# same GHC package set. Elm 0.19.1 needs file-embed and raw-strings-qq,
# which later versions dropped.
#
# The compiler embeds the Elm reactor's front end, which it compiles from
# Elm during its own build. The packages that front end uses come from
# reactor.lock.json, a lockfile `elm-purifier lock` wrote for the reactor/
# directory of the compiler source, through the same package cache that
# buildElmProject uses.
{
  haskell,
  elmPackages,
  fetchgit,
  callPackage,
}:
let
  inherit (haskell.lib.compose) overrideCabal addBuildDepends;
  haskellPackages = haskell.packages.ghc98;
  reactorHome = callPackage ../../nix/lib/elm-home.nix { lockFile = ./reactor.lock.json; };
in
addBuildDepends
  [
    haskellPackages.file-embed
    haskellPackages.raw-strings-qq
  ]
  (
    overrideCabal (drv: {
      version = "0.19.1";
      src = fetchgit {
        url = "https://github.com/elm/compiler";
        rev = "2f6dd29258e880dbb7effd57a829a0470d8da48b";
        sha256 = "1h9jhwlv1pqqna5s09vd72arwhhjn0dlhv0w9xx5771x0xryxxg8";
        fetchSubmodules = true;
      };
      preConfigure = ''
        export ELM_HOME="$PWD/.elm"
        cp -r --no-preserve=mode ${reactorHome} "$ELM_HOME"
      '';
    }) elmPackages.elm
  )
