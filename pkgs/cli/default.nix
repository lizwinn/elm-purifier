# SPDX-License-Identifier: MIT
#
# The elm-purifier command: bin/elm-purifier on nixpkgs' Python, with the
# Elm toolchains it locks and runs with (nix/lib/toolchains.nix), the Nix
# library it realizes lockfiles with, the nixpkgs that library builds
# with, and the shared purifier library pinned in this flake's flake.lock.
{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  elm-purifier,
  elmPackages,
  path,
  version,
  # The shared purifier library, as pinned in this flake's flake.lock.
  purifierSrc,
}:
let
  toolchains = import ../../nix/lib/toolchains.nix { inherit elm-purifier elmPackages; };
  executables = lib.mapAttrs (_: toolchain: {
    elm = "${toolchain.elm}/bin/elm";
    elm-test = lib.mapAttrs (_: elm-test: "${elm-test}/bin/elm-test") toolchain.elm-test;
    elm-test-offline-args = toolchain.elmTestOfflineArgs;
  }) toolchains;
in
stdenvNoCC.mkDerivation {
  pname = "elm-purifier";
  inherit version;
  src = ../../bin;
  nativeBuildInputs = [ makeWrapper ];
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm644 elm-purifier "$out/libexec/elm-purifier.py"
    makeWrapper ${python3}/bin/python3 "$out/bin/elm-purifier" \
      --add-flags "-I $out/libexec/elm-purifier.py" \
      --set ELM_PURIFIER_TOOLCHAINS ${lib.escapeShellArg (builtins.toJSON executables)} \
      --set ELM_PURIFIER_LIB ${../../nix/lib} \
      --set ELM_PURIFIER_NIXPKGS ${path} \
      --set ELM_PURIFIER_PURIFIER ${purifierSrc}
    runHook postInstall
  '';
  meta = {
    description = "Locks the packages an Elm project downloads, so that Nix can build it offline";
    license = lib.licenses.mit;
    mainProgram = "elm-purifier";
  };
}
