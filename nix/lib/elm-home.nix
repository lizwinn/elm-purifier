# SPDX-License-Identifier: MIT
#
# The package cache of a lockfile, laid out as an ELM_HOME:
# <elmVersion>/packages/<author>/<project>/<version> for each locked
# package, with a registry.dat that lists them (see elm-home.py). It is a
# package for callPackage, with the lockfile, its elm.json and the shared
# purifier library among its arguments.
#
# The lock is read by lock.nix and checked by the shared library's
# `checkLock`, and `tree` fetches and unpacks the entries of the system.
# The packages are copies rather than links into the store, because the
# compiler writes its build artifacts into each package directory; a build
# uses a writable copy of this tree.
{
  lib,
  pkgs,
  runCommand,
  python3,
  purifier,
  lockFile,
  # The elm.json the lockfile was made for, which names the packages of
  # an application.
  elmJsonFile,
  # Where the project is, for messages.
  location ? "the project directory",
  # The fetchers that `tree` passes to `fetchEntry` of the shared library,
  # such as a `fetchurl` that sends credentials or asks a company mirror.
  fetchers ? { },
}:
let
  read = import ./lock.nix { inherit lockFile elmJsonFile location; };
  lock = purifier.checkLock read.lock;
  entries = purifier.entriesFor pkgs.stdenv.hostPlatform.system lock;
  packages = map (entry: lib.removePrefix "${read.elmVersion}/packages/" entry.path) entries;
  tree = purifier.tree (
    {
      inherit pkgs entries;
      name = "elm-packages-${read.elmVersion}";
      link = false;
    }
    // fetchers
  );
in
runCommand "elm-home-${read.elmVersion}"
  {
    nativeBuildInputs = [ python3 ];
    packageList = lib.concatMapStrings (package: "${package}\n") packages;
    passAsFile = [ "packageList" ];
    preferLocalBuild = true;
    passthru = {
      inherit lock;
      inherit (read) elmVersion contentHash;
    };
  }
  ''
    cp -r --no-preserve=mode ${tree} "$out"
    python3 -I ${./elm-home.py} "$out" ${read.elmVersion} "$packageListPath"
  ''
