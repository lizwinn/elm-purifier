# elm-purifier

A command and a Nix library that let Nix build an Elm project offline, in
its sandbox. The command records the package archives the Elm compiler and
elm-test download in a lockfile. Nix then builds the project from that
lockfile. The project does not need generated Nix files of its own.

elm-purifier is part of [nix-purifiers](https://nix-purifiers.github.io).

- **A lockfile.** `elm-purifier lock` writes `elm-purifier.lock.json` beside
  `elm.json`. It holds every package archive the project needs, by URL and
  SHA-256, the compiler version, the entry modules of an application, and
  whether the lock covers the tests.
- **Sandboxed builds.** `buildElmProject`, which the flake's overlay adds to
  a package set, turns a project and its lockfile into derivations. Every
  output is known when Nix evaluates: `applications.<module>` is the
  compiled JavaScript of each entry module of an application, and `package`
  is the documentation and files of a package. `tests` runs elm-test.
- **Offline work during development.** `elm-purifier elm` and
  `elm-purifier test` run the compiler and elm-test on the locked packages,
  which Nix fetches.
- **Publishing what Nix built.** `elm-purifier publish` checks that the
  documentation Elm uploads is the one Nix built, then runs `elm publish`
  on the locked packages.

## How the lock is made

`elm-purifier lock` runs the tools a Nix build runs, with an empty
`ELM_HOME` and a fresh `elm-stuff`. For an application it compiles every
entry module. For a package it compiles the documentation, which is where
the compiler resolves the version ranges of `elm.json`. When the project
has a `tests/` directory, it also runs `elm-test make`, which resolves the
test dependencies and the packages elm-test adds of its own. The lockfile
records each package these runs downloaded, with the zip archive the
package server names for it. The command checks each archive against the
SHA-1 the package server publishes, and records its SHA-256.

Before it writes the lockfile, the command builds the package cache from
the new lockfile with Nix and runs the same tools on it. The lock fails if
that second run downloads anything.

The entry modules are not in `elm.json`. By default the command locks
every module under the source directories that defines `main`, and
`--main FILE`, given once per module, names them instead. `--tests` and
`--no-tests` override the test detection. `elm-purifier relock` locks
again with the entry modules and test setting of the current lockfile.

The lockfile records a hash of `elm.json`. A build with a lockfile that
`elm.json` no longer matches stops with a message to relock.

## Compilers

An application names its exact compiler version in `elm.json`, and a
package names a range, for which the newest available compiler is used.
elm-purifier provides two toolchains, each a compiler with the elm-test
releases for it:

- **Elm 0.19.2**, nixpkgs' Elm, with nixpkgs' elm-test 0.19.2-1.
- **Elm 0.19.1**, which most published applications pin. The flake builds
  it as `elm-purifier.elm_0_19_1` with nixpkgs' recipe for its own Elm, on
  the same GHC package set. The compiler compiles the Elm reactor's front
  end during its own build, and the packages for that come from
  `pkgs/elm_0_19_1/reactor.lock.json`, a lockfile of this tool. Its tests
  run on elm-test 0.19.1-revision15 for elm-explorations/test 2.x, and on
  0.19.1-revision9, the last release that runs test 1.x, for projects that
  still use test 1.x.

The elm-test release follows the major version of elm-explorations/test
that `elm.json` names. Every elm-test package of this flake puts its socket
in the directory `TMPDIR` names, where upstream elm-test uses a fixed path
under `/tmp`.

## Use

In the directory of `elm.json`:

```zsh
nix run github:nix-purifiers/elm-purifier -- lock
```

Commit `elm-purifier.lock.json`. The flake's `overlays.default` adds
`buildElmProject` to a package set, and a package written for `callPackage`
takes it by name:

```nix
# package.nix
{ buildElmProject }:
buildElmProject { src = ./.; }
```

```nix
{
  inputs.elm-purifier.url = "github:nix-purifiers/elm-purifier";
  inputs.nixpkgs.follows = "elm-purifier/nixpkgs";

  outputs = { nixpkgs, elm-purifier, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ elm-purifier.overlays.default ];
      };
      project = pkgs.callPackage ./package.nix { };
    in
    {
      packages.${system} = {
        default = project.default;
        main = project.applications.Main;
      };
      checks.${system}.tests = project.tests;
    };
}
```

`nix build '.#main'` writes `Main.js`. The builder reads `elm.json` and
the lockfile while Nix evaluates, which is how every output is known
without generated Nix files, so `src` is a path: the flake's own source, a
flake input, or `builtins.fetchTarball`. A source built as a derivation,
such as `fetchFromGitHub`, would make Nix build it during evaluation. `nix/lib/build-elm-project.nix`
documents the builder's arguments: `subdirectory`, for a project whose
source directories reach outside its own directory; `optimize` (on by
default; an application that uses `Debug` needs it off); `elm` and
`elm-test` to replace the toolchain; `fetchurl` for a proxy or credentials;
and `srcFilter`.

### Sources

Elm installs packages only from the package server, and a package there is
a zip archive of a tagged GitHub release. Every package an Elm project can
depend on is therefore a locked archive. Source directories outside the
project, such as `"../shared/src"`, are part of the source tree: pass the
enclosing tree as `src` and the project's directory as `subdirectory`.

```nix
buildElmProject {
  src = ./.;
  subdirectory = "app";
}
```

### Development

```zsh
nix run github:nix-purifiers/elm-purifier -- elm make src/Main.elm
nix run github:nix-purifiers/elm-purifier -- test
```

These build the package cache of the lockfile with Nix, copy it to
`elm-stuff/elm-purifier/home`, and run the compiler or elm-test of the
lock's toolchain with that copy as `ELM_HOME`. The link
`elm-stuff/elm-purifier/cache-root` is the GC root that keeps the locked
archives in the store. When there is no lockfile, or `elm.json` changed
since it was made, the commands warn and run with the usual `ELM_HOME`.

To add or upgrade a dependency, run `elm install` through the command and
relock:

```zsh
nix run github:nix-purifiers/elm-purifier -- elm install elm/regex
nix run github:nix-purifiers/elm-purifier -- relock
```

`elm init`, `install`, `bump` and `diff` need the package server, so they
run with the usual `ELM_HOME`, and `install` ends with a reminder to
relock.

An editor or language server finds the compiler on `PATH` and the
packages in `ELM_HOME`. `exec` runs any command with both pointing at the
lock: `elm-purifier exec code .` starts VS Code that way, and
`elm-purifier exec elm-language-server --stdio` is the server command for
an editor that starts the server itself.

### Publishing

```zsh
nix run github:nix-purifiers/elm-purifier -- publish
```

Elm publishes a package by registering a pushed git tag with the package
server, which then fetches the release archive from GitHub. `elm publish`
takes no prebuilt files. So the command builds the package with Nix,
compiles the documentation on the locked packages, and stops unless the two
are identical. It then runs `elm publish` on the locked packages, which
uploads that same documentation. `publish --check` stops before
`elm publish`.

### When something is wrong

Each of these stops with a message that says what happened and what to
run:

- **`elm.json` changed since the lock was made.** The Nix build stops and
  names the project directory. The interactive commands warn and run with
  the usual `ELM_HOME`. Run `elm-purifier relock`.
- **The lockfile lacks a package `elm.json` needs**, after a hand edit or
  a bad merge. The Nix build lists the missing packages. Run
  `elm-purifier relock`.
- **The lockfile does not parse, or lacks a field.** Nix and the command
  name the file. Run `elm-purifier lock`, with `--main` for each entry
  module, since a broken file no longer says which modules to lock.
- **An archive does not match its hash**, because the lockfile was edited
  or the archive changed on GitHub. Nix reports the hash mismatch for that
  package, and the interactive commands add that `elm-purifier relock`
  writes the lockfile again.

## Projects tried

Beyond the fixtures, CI builds these published projects at a pinned commit
from lockfiles under `tests/real-world`, and runs their tests:

- [rtfeldman/elm-spa-example](https://github.com/rtfeldman/elm-spa-example)
  at `cb32acd`, an Elm 0.19.1 single-page application with 33 modules,
  ten direct dependencies and elm-explorations/test 1.0.0. Locking it takes
  about 15 seconds. It was also worked through by hand: the quickstart,
  an interactive build, `elm install elm/regex` and a relock, and
  elm-language-server through `exec`.
- [elm-community/list-extra](https://github.com/elm-community/list-extra)
  at `46a4817`, a widely used package with 220 tests on
  elm-explorations/test 2.x. Locking it takes about 11 seconds.

They changed the tool in three ways. elm-spa-example uses
elm-explorations/test 1.x, which the newer elm-test releases refuse, so the
Elm 0.19.1 toolchain gained elm-test 0.19.1-revision9 and the choice by
test major version. The stale lock message named the lockfile by its store
path, so the messages now name the project directory. And `elm install`
with the locked packages could not reach the package server, so the
commands that need the server run with the usual `ELM_HOME`.

## Limits

- **The upload is not tested.** `elm publish` talks only to
  package.elm-lang.org and needs a release tag pushed to GitHub, so the
  tests run `publish --check`, which covers everything before the upload.
- **Elm 0.19.0.** There is no toolchain for it, because applications that
  pin 0.19.0 are rare; such a project passes its own `elm` and `elm-test`
  to the builder. Package projects accept 0.19.1 and 0.19.2.

## Credit

elm-purifier follows the design of
[sbt-nix-backend](https://github.com/nix-purifiers/sbt-purifier): a lock run
with empty caches that records every download, a builder that runs the
tool itself in the sandbox from that lockfile, an offline interactive mode
on the same locked files, and publishing what Nix built. The purifier idea
was inspired by nixcloud's
[cargo (libnix)](https://github.com/nixcloud/cargo).

## Tests

`nix flake check` runs these in the sandbox:

- The fixtures under `tests/fixtures`: an Elm 0.19.1 application with two
  entry modules and a test suite, an Elm package with a test suite, and an
  Elm 0.19.2 application whose source directories reach outside its
  directory. Each compiled application runs under Node, both test suites
  run, and the package's documentation is checked.
- The projects under `tests/real-world`, fetched at their pinned commits,
  built from their lockfiles, with their test suites.
- Negative cases: a lockfile beside an `elm.json` it was not made for, and
  lockfiles edited to lack a package, a field or an archive, or to carry
  another format version. Each must stop evaluation.
- The unit tests under `tests/unit`, for constraint matching, compiler and
  elm-test selection, entry-module and test detection, the archive filter
  and the registry encoding.

`tests/interactive.sh` tests what runs outside the sandbox: it relocks each
fixture and compares the result with the committed lockfile byte for byte,
runs `elm` and `test` on the locked packages, runs `publish --check`, runs
elm-language-server through `exec`, and checks the messages for a stale
`elm.json`, a tampered hash and a lockfile that does not parse. CI runs
both on x86_64-linux and aarch64-linux.

## License

MIT
