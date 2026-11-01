# SPDX-License-Identifier: MIT
#
# The checks: the CLI, and the fixtures under tests/fixtures built from
# their committed lockfiles in the sandbox, each output run where it can
# run, with the test suites of the fixtures that have them.
{
  pkgs,
  overlay,
  cli,
}:
let
  elmPkgs = pkgs.extend overlay;
  inherit (elmPkgs) lib runCommand nodejs;

  app = elmPkgs.buildElmProject { src = ./fixtures/app; };
  package = elmPkgs.buildElmProject { src = ./fixtures/package; };
  shared = elmPkgs.buildElmProject {
    src = ./fixtures/shared;
    subdirectory = "app";
  };

  # Runs the worker MODULE of a compiled application with the flags "Nix"
  # and compares what it prints.
  runsWorker =
    name: application: module: expected:
    runCommand name { nativeBuildInputs = [ nodejs ]; } ''
      actual=$(node ${./run-worker.js} ${application}/${module}.js ${module} Nix)
      if [ "$actual" != ${lib.escapeShellArg expected} ]; then
        echo "${module} printed: $actual" >&2
        echo "expected: "${lib.escapeShellArg expected} >&2
        exit 1
      fi
      touch $out
    '';

  # Published projects, pinned to a commit, with lockfiles `elm-purifier
  # lock` wrote for those commits (tests/real-world/<project>). The builder
  # reads elm.json while Nix evaluates, so the sources are fetched during
  # evaluation, with builtins.fetchTarball, rather than built as
  # derivations.
  github =
    repository: rev: sha256:
    builtins.fetchTarball {
      url = "https://github.com/${repository}/archive/${rev}.tar.gz";
      inherit sha256;
    };
  realWorld = {
    # An Elm 0.19.1 single-page application with elm-explorations/test 1.x.
    elm-spa-example = elmPkgs.buildElmProject {
      src =
        github "rtfeldman/elm-spa-example" "cb32acd73c3d346d0064e7923049867d8ce67193"
          "sha256-iYd7/fzdkd3KoGLLcBTVNa6O1KcYgrlIWll4xkwI72o=";
      lockFile = ./real-world/elm-spa-example/elm-purifier.lock.json;
    };
    # A widely used package with elm-explorations/test 2.x.
    list-extra = elmPkgs.buildElmProject {
      src =
        github "elm-community/list-extra" "46a4817f2df99ce3379390db21348177ac95056d"
          "sha256-gPMFO2b+XApTjDifbNo9p5lDZcK9sy5IXY1lPhnEOmM=";
      lockFile = ./real-world/list-extra/elm-purifier.lock.json;
    };
  };

  # A lockfile beside an elm.json it was not made for stops evaluation.
  staleLock = elmPkgs.buildElmProject {
    src = ./fixtures/shared;
    subdirectory = "app";
    lockFile = ./fixtures/app/elm-purifier.lock.json;
  };

  # The app fixture with lockfiles edited by hand, each of which must stop
  # evaluation with an elm-purifier message.
  appLock = builtins.fromJSON (builtins.readFile ./fixtures/app/elm-purifier.lock.json);
  withLock =
    name: lock:
    elmPkgs.buildElmProject {
      src = ./fixtures/app;
      lockFile = builtins.toFile "${name}.lock.json" (builtins.toJSON lock);
    };
  failsToEvaluate = project: !(builtins.tryEval project.applications.Main.drvPath).success;
  editedLocks = {
    # elm/json is gone from the downloads.
    missing-package = withLock "missing-package" (
      appLock
      // {
        downloads = builtins.filter (d: d.path != "elm/json/1.1.4") appLock.downloads;
      }
    );
    # A required field is gone.
    missing-field = withLock "missing-field" (removeAttrs appLock [ "downloads" ]);
    # A download lost its archive.
    broken-download = withLock "broken-download" (
      appLock
      // {
        downloads = [
          (removeAttrs (builtins.head appLock.downloads) [ "archive" ])
        ]
        ++ builtins.tail appLock.downloads;
      }
    );
    # A lock format this library does not read.
    other-version = withLock "other-version" (appLock // { version = 99; });
  };
in
{
  inherit cli;

  app-main = runsWorker "app-main" app.applications.Main "Main" "Hello, Nix!";
  app-report =
    runsWorker "app-report" app.applications."Report.Json" "Report.Json"
      ''{"greeting":"Hello, Nix!"}'';
  app-tests = app.tests;
  app-outputs =
    assert
      lib.attrNames app.applications == [
        "Main"
        "Report.Json"
      ];
    assert app.lock.elmVersion == "0.19.1";
    runCommand "app-outputs" { } "touch $out";

  package-docs =
    runCommand "package-docs"
      {
        nativeBuildInputs = [ elmPkgs.jq ];
      }
      ''
        jq -e '.[0].name == "Greeting" and ([.[0].values[].name] | sort) == ["encode", "greeting"]' \
          ${package.package}/docs.json
        for file in elm.json README.md LICENSE src/Greeting.elm; do
          test -f ${package.package}/$file
        done
        touch $out
      '';
  package-tests = package.tests;

  shared-main =
    runsWorker "shared-main" shared.applications.Main "Main"
      ''"Hello from the shared directory, Nix!"'';

  stale-lock =
    assert failsToEvaluate staleLock;
    runCommand "stale-lock" { } "touch $out";

  edited-locks =
    assert lib.all failsToEvaluate (lib.attrValues editedLocks);
    # The unedited lock evaluates, so the failures above come from the edits.
    assert !(failsToEvaluate (withLock "unedited" appLock));
    runCommand "edited-locks" { } "touch $out";

  real-world-elm-spa-example = runCommand "real-world-elm-spa-example" { } ''
    grep -q Conduit ${realWorld.elm-spa-example.applications.Main}/Main.js
    touch $out
  '';
  real-world-elm-spa-example-tests = realWorld.elm-spa-example.tests;
  real-world-list-extra =
    runCommand "real-world-list-extra" { nativeBuildInputs = [ elmPkgs.jq ]; }
      ''
        jq -e '.[0].name == "List.Extra"' ${realWorld.list-extra.package}/docs.json
        touch $out
      '';
  real-world-list-extra-tests = realWorld.list-extra.tests;

  # The unit tests of bin/elm-purifier and nix/lib/elm-home.py.
  unit = runCommand "unit" { nativeBuildInputs = [ elmPkgs.python3 ]; } ''
    ELM_PURIFIER_REPO=${../.} python3 -I -m unittest discover -s ${./unit} -v
    touch $out
  '';

  # The compiler built by this flake compiles the probe it was built with.
  elm_0_19_1-version = runCommand "elm_0_19_1-version" { } ''
    test "$(${elmPkgs.elm-purifier.elm_0_19_1}/bin/elm --version)" = 0.19.1
    touch $out
  '';
}
