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
#
# A lockfile that does not parse or lacks a field stops evaluation with a
# message that names the file and the command that writes it again.
{ lockFile }:
let
  relock = "run `elm-purifier relock` in the directory of elm.json to write it again";
  invalid = reason: throw "elm-purifier: ${toString lockFile} ${reason}; ${relock}.";

  lock = builtins.addErrorContext "while reading the elm-purifier lockfile ${toString lockFile} (if it does not parse, run `elm-purifier lock` in the directory of elm.json, with --main for each entry module of an application, to write it again)" (
    builtins.fromJSON (builtins.readFile lockFile)
  );
  supportedVersion = import ./lock-version.nix;

  require =
    fields: what: value:
    builtins.all (field: value ? ${field} || invalid "has ${what} without the field `${field}`") fields;

  valid =
    builtins.isAttrs lock
    && require [ "version" ] "a top level" lock
    && (
      lock.version == supportedVersion
      || throw "elm-purifier: ${toString lockFile} has lock format version ${toString lock.version}; this library reads version ${toString supportedVersion}. Run `elm-purifier relock` with the elm-purifier version that provides this library."
    )
    && require [ "elmVersion" "elmJson" "tests" "outputs" "downloads" ] "a top level" lock
    && require [ "applications" ] "outputs" lock.outputs
    && builtins.all (
      download:
      require [ "path" "archive" "hash" ] "a download" download
      && require [ "url" "mirrors" "stripTop" ] "a download archive" download.archive
    ) lock.downloads;
in
assert valid || invalid "is not an elm-purifier lockfile";
lock
// {
  # The store name of a package archive: author-project-version.zip, which
  # only uses characters store names allow.
  downloadName = download: builtins.replaceStrings [ "/" ] [ "-" ] download.path + ".zip";

  # The locked packages, as author/project/version.
  packages = map (download: download.path) lock.downloads;
}
