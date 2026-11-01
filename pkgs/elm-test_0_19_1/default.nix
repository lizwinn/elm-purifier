# SPDX-License-Identifier: MIT
#
# elm-test for Elm 0.19.1. elm-test writes the Elm version into the test
# project it generates, so each compiler needs the elm-test release line
# for its own version; nixpkgs carries the one for its Elm. The recipe is
# nixpkgs' own.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "elm-test";
  version = "0.19.1-revision15";

  src = fetchFromGitHub {
    owner = "rtfeldman";
    repo = "node-test-runner";
    rev = version;
    hash = "sha256-y9ejNZHtgRtZCKE1myH+LwZMOaPdG9for0zCH7xGSR4=";
  };

  npmDepsHash = "sha256-hoInSQ+fKVmfCUoxYTqqb4+Nx/ER7EWWeN8FtmhOTpA=";

  # elm-test puts its socket at /tmp/elm_test-<pid>.sock. The patch puts it
  # in the directory TMPDIR names, which is where a sandbox lets it write.
  postPatch = ''
    sed -i '/elm-tooling install/d' package.json
    ${import ../elm-test/socket-patch.nix}
  '';

  dontNpmBuild = true;

  postInstall = ''
    find $out/lib/node_modules/elm-test/node_modules/.bin -xtype l -delete
  '';

  meta = {
    description = "Runs elm-test suites from Node.js, for Elm 0.19.1";
    mainProgram = "elm-test";
    homepage = "https://github.com/rtfeldman/node-test-runner";
    license = lib.licenses.bsd3;
  };
}
