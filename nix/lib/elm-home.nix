# SPDX-License-Identifier: MIT
#
# The package cache of a lockfile, laid out as an ELM_HOME:
# <elmVersion>/packages/<author>/<project>/<version> for each locked
# package, with a registry.dat that lists them (see elm-home.py). It is a
# package for callPackage, with the lockfile and the shared purifier
# library among its arguments.
#
# The shared library's `tree` fetches and unpacks each archive entry. The
# packages are copies rather than links into the store, because the
# compiler writes its build artifacts into each package directory; a build
# uses a writable copy of this tree.
{
  lib,
  pkgs,
  runCommand,
  python3,
  purifier,
  lockFile,
  # Replaces nixpkgs' fetchurl for package archives, as for a proxy or
  # credentials. It takes the arguments of nixpkgs' fetchurl.
  fetchurl ? null,
}:
let
  lock = import ./lock.nix { inherit lockFile; };
  packages = purifier.tree (
    {
      inherit pkgs;
      name = "elm-packages-${lock.elmVersion}";
      link = false;
      entries = map (
        download: download // { path = "${lock.elmVersion}/packages/${download.path}"; }
      ) lock.downloads;
    }
    // lib.optionalAttrs (fetchurl != null) { inherit fetchurl; }
  );
in
runCommand "elm-home-${lock.elmVersion}"
  {
    nativeBuildInputs = [ python3 ];
    packageList = lib.concatMapStrings (package: "${package}\n") lock.packages;
    passAsFile = [ "packageList" ];
    preferLocalBuild = true;
    passthru = { inherit lock; };
  }
  ''
    cp -r --no-preserve=mode ${packages} "$out"
    python3 -I ${./elm-home.py} "$out" ${lock.elmVersion} "$packageListPath"
  ''
