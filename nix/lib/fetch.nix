# SPDX-License-Identifier: MIT
#
# The fetcher for locked package archives. Each download is an archive in
# the shape of the shared nix-purifiers library,
#
#   { path, archive = { url, mirrors, stripTop }, hash }
#
# where hash is the SRI hash of the archive file. This returns the archive
# file itself; elm-home.py unpacks it the way the Elm compiler does.
#
# By default the file is a fixed-output derivation on Nix's built-in
# fetcher (the derivation <nix/fetchurl.nix> makes), tried at `url` and
# then at each mirror. A fixed-output store path depends only on its name
# and hash, so this and nixpkgs' fetchurl produce the same paths.
#
# `fetchurl`, when given, replaces the built-in fetcher. It is called with
# { name, urls, hash } and is the place for credentials or a proxy.
{
  lock,
  fetchurl ? null,
}:
download:
let
  name = lock.downloadName download;
  urls = [ download.archive.url ] ++ download.archive.mirrors;
in
if fetchurl != null then
  fetchurl {
    inherit name urls;
    inherit (download) hash;
  }
else
  derivation {
    inherit name;
    builder = "builtin:fetchurl";
    system = "builtin";
    url = builtins.head urls;
    inherit urls;
    outputHash = download.hash;
    outputHashAlgo = "sha256";
    outputHashMode = "flat";
    unpack = false;
    executable = false;
    preferLocalBuild = true;
    impureEnvVars = [
      "http_proxy"
      "https_proxy"
      "ftp_proxy"
      "all_proxy"
      "no_proxy"
    ];
  }
