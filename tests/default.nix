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
  pkgs' = pkgs.extend overlay;
  inherit (pkgs') lib runCommand nodejs;

  app = pkgs'.buildElmProject { src = ./fixtures/app; };
  package = pkgs'.buildElmProject { src = ./fixtures/package; };
  shared = pkgs'.buildElmProject {
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

  # A lockfile beside an elm.json it was not made for stops evaluation.
  staleLock = pkgs'.buildElmProject {
    src = ./fixtures/shared;
    subdirectory = "app";
    lockFile = ./fixtures/app/elm-purifier.lock.json;
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
        nativeBuildInputs = [ pkgs'.jq ];
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
    assert !(builtins.tryEval staleLock.applications.Main.drvPath).success;
    runCommand "stale-lock" { } "touch $out";

  # The compiler built by this flake compiles the probe it was built with.
  elm_0_19_1-version = runCommand "elm_0_19_1-version" { } ''
    test "$(${pkgs'.elm-purifier.elm_0_19_1}/bin/elm --version)" = 0.19.1
    touch $out
  '';
}
