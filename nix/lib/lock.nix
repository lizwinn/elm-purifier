# SPDX-License-Identifier: MIT
#
# Reads an elm-purifier lockfile (written by `elm-purifier lock`). Its
# fields:
#
#   version      the lock format version (lock-version.nix)
#   elmVersion   the compiler version the project builds with
#   elmJson      the SRI hash of elm.json when the lock was made
#   tests        whether the lock covers elm-test on tests/
#   outputs      applications.<module> = { main = <file>; } for each entry
#                module of an application; empty for a package, whose
#                output elm.json names
#   downloads    one archive per package, in the shape of the shared
#                nix-purifiers library:
#                  { path, archive = { url, mirrors, stripTop }, hash }
#                where path is author/project/version and hash is the SRI
#                hash of the zip
{ lockFile }:
let
  lock = builtins.fromJSON (builtins.readFile lockFile);
  supportedVersion = import ./lock-version.nix;
in
assert
  lock.version == supportedVersion
  || throw "elm-purifier: ${toString lockFile} has lock format version ${toString lock.version}; this library reads version ${toString supportedVersion}. Run `elm-purifier relock` with the elm-purifier version that provides this library.";
lock
// {
  # The store name of a package archive: author-project-version.zip, which
  # only uses characters store names allow.
  downloadName = download: builtins.replaceStrings [ "/" ] [ "-" ] download.path + ".zip";
}
