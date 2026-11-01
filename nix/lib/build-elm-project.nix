# SPDX-License-Identifier: MIT
#
# buildElmProject: the sandboxed builds of an Elm project, from elm.json
# and the lockfile `elm-purifier lock` writes beside it.
#
# The file is a package for callPackage: the first argument set is what it
# takes from the package set, and the result is the builder. The
# elm-purifier overlay (`overlays.default`) adds it to the package set as
# `buildElmProject`, so a package written for callPackage takes it like any
# other dependency:
#
#   { buildElmProject }: (buildElmProject { src = ./.; }).applications.Main
#
# Every output is known at evaluation time, from the lockfile and elm.json.
# The builder returns
#
#   elmHome                 the package cache of every locked package
#   applications.<module>   for an application, the compiled JavaScript of
#                           each entry module the lockfile records, at
#                           <module>.js
#   package                 for a package, docs.json and the files
#                           `elm publish` publishes (elm.json, README.md,
#                           LICENSE and src/), under the name and version
#                           elm.json gives
#   tests                   elm-test on tests/, when the lock covers them
#   default                 every application, or the package
{
  lib,
  stdenvNoCC,
  callPackage,
  symlinkJoin,
  elm-purifier,
  elmPackages,
}:
{
  # The tree the project is in.
  src,
  # The directory of elm.json, relative to `src`. A project whose
  # source-directories reach outside its directory takes the enclosing tree
  # as `src` and its own directory here.
  subdirectory ? ".",
  # The lockfile; the default is the one `elm-purifier lock` writes beside
  # elm.json.
  lockFile ? src + "/${subdirectory}/elm-purifier.lock.json",
  # Compiles applications with --optimize. An application that uses
  # Debug cannot be optimized.
  optimize ? true,
  # The Elm compiler. The default is the one of the version the lock was
  # made with.
  elm ? null,
  # The elm-test that `tests` runs. The default is the release for the
  # compiler version the lock was made with.
  elm-test ? null,
  # Replaces the built-in fetcher for package archives; see fetch.nix.
  fetchurl ? null,
  # Filters `src` before it is copied into the store, as the `filter` of
  # builtins.path. The default leaves out version control, elm-stuff,
  # node_modules and the results of nix build.
  srcFilter ? null,
}:
let
  lock = import ./lock.nix { inherit lockFile; };
  projectDir = src + "/${subdirectory}";
  elmJsonFile = projectDir + "/elm.json";
  elmJson = builtins.fromJSON (builtins.readFile elmJsonFile);

  elmJsonHash = builtins.convertHash {
    hash = builtins.hashFile "sha256" elmJsonFile;
    hashAlgo = "sha256";
    toHashFormat = "sri";
  };

  toolchain =
    (import ./toolchains.nix { inherit elm-purifier elmPackages; }).${lock.elmVersion} or {
      elm = throw "elm-purifier: there is no Elm ${lock.elmVersion} compiler for the lock; pass `elm`.";
      elm-test = throw "elm-purifier: there is no elm-test for Elm ${lock.elmVersion}; pass `elm-test`.";
    };
  compiler = if elm != null then elm else toolchain.elm;
  elm-test' = if elm-test != null then elm-test else toolchain.elm-test;

  elmHome = callPackage ./elm-home.nix { inherit lockFile fetchurl; };

  defaultSrcFilter =
    path: type:
    let
      base = baseNameOf path;
    in
    !(base == ".git" || base == "elm-stuff" || base == "node_modules" || lib.hasPrefix "result" base);

  filteredSrc = builtins.path {
    path = src;
    name = "elm-source";
    filter = if srcFilter != null then srcFilter else defaultSrcFilter;
  };

  # The setup every build shares: a writable copy of the package cache as
  # ELM_HOME, and the project directory as the working directory.
  setup = ''
    export HOME="$TMPDIR/home"
    export ELM_HOME="$TMPDIR/elm-home"
    mkdir -p "$HOME"
    cp -r --no-preserve=mode ${elmHome} "$ELM_HOME"
    cd ${lib.escapeShellArg subdirectory}
  '';

  isApplication = elmJson.type == "application";

  # An application's elm.json names the exact version of every package it
  # builds with (and tests with), so a lockfile without one of them was
  # edited after `elm-purifier lock` wrote it.
  exact = deps: lib.mapAttrsToList (name: version: "${name}/${version}") (deps.direct // deps.indirect);
  requiredPackages = lib.optionals isApplication (
    exact elmJson.dependencies ++ lib.optionals lock.tests (exact elmJson."test-dependencies")
  );
  missingPackages = lib.filter (package: !(lib.elem package lock.packages)) requiredPackages;

  mkBuild =
    name: attrs:
    assert
      lock.elmJson == elmJsonHash
      || throw "elm-purifier: elm.json changed since ${toString lockFile} was made; run `elm-purifier relock` in ${subdirectory} of the source.";
    assert
      missingPackages == [ ]
      || throw "elm-purifier: ${toString lockFile} does not lock ${lib.concatStringsSep ", " missingPackages}, which elm.json needs; run `elm-purifier relock` to write it again.";
    stdenvNoCC.mkDerivation (
      {
        inherit name;
        src = filteredSrc;
        dontConfigure = true;
        dontFixup = true;
        passthru = { inherit lock elmHome; };
      }
      // attrs
    );

  applications = lib.mapAttrs (
    module: output:
    mkBuild "elm-${module}" {
      nativeBuildInputs = [ compiler ];
      buildPhase = ''
        runHook preBuild
        ${setup}
        elm make ${lib.escapeShellArg output.main} ${lib.optionalString optimize "--optimize"} \
          --output="$TMPDIR/${module}.js"
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        install -Dm644 "$TMPDIR/${module}.js" "$out/${module}.js"
        runHook postInstall
      '';
    }
  ) lock.outputs.applications;

  package = mkBuild "elm-${lib.replaceStrings [ "/" ] [ "-" ] elmJson.name}-${elmJson.version}" {
    nativeBuildInputs = [ compiler ];
    buildPhase = ''
      runHook preBuild
      ${setup}
      elm make --docs="$TMPDIR/docs.json"
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp "$TMPDIR/docs.json" "$out/docs.json"
      cp -r elm.json src "$out/"
      for file in README.md LICENSE; do
        if [ -e "$file" ]; then cp "$file" "$out/"; fi
      done
      runHook postInstall
    '';
  };

  tests = mkBuild "elm-tests" {
    nativeBuildInputs = [
      compiler
      elm-test'
    ];
    buildPhase = ''
      runHook preBuild
      ${setup}
      # elm-test solves the test dependencies itself, and the arguments of
      # the toolchain keep it to the locked packages (see toolchains.nix).
      elm-test --compiler ${compiler}/bin/elm ${lib.escapeShellArgs toolchain.elmTestOfflineArgs}
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      touch "$out"
      runHook postInstall
    '';
  };

in
{
  inherit elmHome lock;
  default =
    if isApplication then
      symlinkJoin {
        name = "elm-applications";
        paths = lib.attrValues applications;
      }
    else
      package;
}
// lib.optionalAttrs isApplication { inherit applications; }
// lib.optionalAttrs (!isApplication) { inherit package; }
// lib.optionalAttrs lock.tests { inherit tests; }
