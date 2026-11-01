# SPDX-License-Identifier: MIT
#
# elm-test 0.19.1-revision9, the last release for elm-explorations/test
# 1.x. The later releases for Elm 0.19.1 refuse a project on test 1.x, and
# many published applications still use it. The recipe is nixpkgs' recipe
# for its elm-test.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "elm-test";
  version = "0.19.1-revision9";

  src = fetchFromGitHub {
    owner = "rtfeldman";
    repo = "node-test-runner";
    rev = version;
    hash = "sha256-sMh+6dZ20XOvWi0Y3S/RFJzfnE9DnHjMfORRKXvEW40=";
  };

  npmDepsHash = "sha256-J9wsgvhrizmiKRift4RD0mvWubw/69FX09UbqxlsR9s=";

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
    description = "Runs elm-test suites from Node.js, for Elm 0.19.1 and elm-explorations/test 1.x";
    mainProgram = "elm-test";
    homepage = "https://github.com/rtfeldman/node-test-runner";
    license = lib.licenses.bsd3;
  };
}
