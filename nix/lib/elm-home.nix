# SPDX-License-Identifier: MIT
#
# The package cache of a lockfile, laid out as an ELM_HOME:
# <elmVersion>/packages/<author>/<project>/<version> for each locked
# package, with a registry.dat that lists them (see elm-home.py). It is a
# package for callPackage, with the lockfile among its arguments.
#
# The compiler writes its build artifacts into each package directory, so
# a build uses a writable copy of this tree.
{
  lib,
  runCommand,
  python3,
  lockFile,
  # Replaces the built-in fetcher for package archives; see fetch.nix.
  fetchurl ? null,
}:
let
  lock = import ./lock.nix { inherit lockFile; };
  fetch = import ./fetch.nix { inherit lock fetchurl; };
in
# The manifest goes to the builder as a file, since a large application
# locks many packages.
runCommand "elm-home-${lock.elmVersion}"
  {
    nativeBuildInputs = [ python3 ];
    manifest = lib.concatMapStrings (d: "${d.path}\t${fetch d}\n") lock.downloads;
    passAsFile = [ "manifest" ];
    preferLocalBuild = true;
    passthru = { inherit lock; };
  }
  ''
    python3 -I ${./elm-home.py} "$out" ${lock.elmVersion} "$manifestPath"
  ''
