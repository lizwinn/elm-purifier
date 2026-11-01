# SPDX-License-Identifier: MIT
#
# nixpkgs' elm-test, with its socket in the directory TMPDIR names instead
# of at /tmp/elm_test-<pid>.sock (see socket-patch.nix).
{ elmPackages }:
elmPackages.elm-test.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + import ./socket-patch.nix;
})
