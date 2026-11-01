# elm-purifier

elm-purifier lets Nix build an Elm project offline, in its sandbox. The
command `elm-purifier` runs the Elm compiler and elm-test with empty
caches, and records a hash for each package they download. The Nix builder
`buildElmProject` then fetches those packages and builds the project from
`elm.json` and that lockfile. The project needs no generated Nix files.

elm-purifier is one of the [nix-purifiers](https://nix-purifiers.github.io)
and meets their [contract](https://github.com/nix-purifiers/purifier/blob/main/CONTRACT.md).
It targets x86_64-linux and aarch64-linux.

## Quickstart

In the directory of `elm.json`:

```zsh
nix run github:nix-purifiers/elm-purifier -- lock
```

The command writes `elm-purifier.lock.json` beside `elm.json`. Commit it.
The lockfile holds only what `elm.json` cannot give: the SHA-256 of each
package zip, the entry modules of an application, whether the lock covers
the tests, a hash of `elm.json`, and a hash of the lockfile itself. For a
package project, whose `elm.json` gives version ranges, it also holds the
versions the solver chose and the compiler version. For an application,
`elm.json` names every version and the compiler, and the builder reads
them from there.

The flake publishes the builder as `lib.elm-purifier.buildElmProject`:

```nix
{
  inputs.elm-purifier.url = "github:nix-purifiers/elm-purifier";
  inputs.nixpkgs.follows = "elm-purifier/nixpkgs";

  outputs = { nixpkgs, elm-purifier, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      project = elm-purifier.lib.elm-purifier.buildElmProject {
        inherit pkgs;
        src = ./.;
      };
    in
    {
      packages.${system}.main = project.packages.Main;
      checks.${system}.tests = project.tests;
    };
}
```

`nix build '.#main'` writes `Main.js`. Every attribute name of the result
is known when Nix evaluates:

| Attribute | What it is |
| --- | --- |
| `packages.<module>` | For an application, the compiled JavaScript of each entry module, built with `--optimize`, at `<module>.js`. |
| `packages.docs` | For a package, its `docs.json`. |
| `tests` | elm-test on `tests/`, when the lock covers the tests. |
| `release` | For a package, what `elm-purifier publish` checks before it publishes: `docs.json`, `elm.json`, `README.md`, `LICENSE` and `src/`. |
| `fetches` | The shared library entry for each package archive, which SBOM and license tools read. |

The builder takes these arguments:

- `pkgs` and `src`. `src` is a path: the source of the flake, a flake
  input, or `builtins.fetchTarball`. The builder reads `elm.json` and the
  lockfile while Nix evaluates, so a source built as a derivation, such as
  `fetchFromGitHub`, would make Nix build it during evaluation.
- `subdirectory`, the directory of `elm.json` inside `src`, for a project
  whose source directories reach outside its own directory, such as
  `"../shared/src"`.
- `lockFile`, which defaults to `elm-purifier.lock.json` beside `elm.json`.
  A lockfile kept outside `src`, as in a packaging flake for a project
  that its author does not change, replaces any copy inside `src`. The
  command takes the same path as `--lockfile`, or from the environment
  variable `ELM_PURIFIER_LOCKFILE`, which a dev shell can set.
- `fetchers`, passed to the shared library for a company mirror or
  credentials. `fetchers.fetchurl` replaces the `fetchurl` of nixpkgs.
- `optimize`, on by default. An application that uses `Debug` needs it
  off.
- `elm`, `elm-test` and `srcFilter`, to replace the toolchain or the source
  filter.

`lib.elm-purifier.readLock { src, subdirectory, lockFile }` returns the
lock in the shape of the contract, for tools that read every purifier.

## Everyday loop

```zsh
nix run github:nix-purifiers/elm-purifier -- prefetch
export PATH="$PWD/elm-stuff/elm-purifier/bin:$PATH"
elm make src/Main.elm
elm-test
```

`prefetch` builds the locked packages and the tools with Nix, and links
the tools into `elm-stuff/elm-purifier/bin`. The linked `elm` and
`elm-test` run the real compilers and test runners on the locked packages.
Elm commands that talk to the package server run with the usual
`ELM_HOME`: `elm init`, `install`, `bump` and `diff`, and `elm-test init`
and `install`. After `elm install` and `elm-test install`, the command
reminds you to lock again.

Changing dependencies takes two commands:

```zsh
elm install elm/regex
elm-purifier lock
elm-purifier prefetch
```

`elm-purifier update` moves the project to newer versions and locks it. For
an application it runs `elm-json upgrade`, which moves every package
within its major version, or `elm-json install` for the packages named
(`elm-purifier update elm/json`). For a package project it locks the
newest versions that the ranges in `elm.json` admit, where `lock` keeps
the versions its current lockfile records. The tool `elm-json` knows only
Elm 0.19.0 and 0.19.1, so for an application on another compiler it solves
a copy of `elm.json` that names 0.19.1, and then restores the version.

Publishing a package takes one command:

```zsh
nix run github:nix-purifiers/elm-purifier -- publish
```

Elm publishes by registering a pushed git tag with the package server, so
`elm publish` takes no prebuilt files. The command builds the `release`
with Nix, compiles the documentation on the locked packages, and stops
unless the two are identical. It then runs `elm publish`, which uploads
that same documentation. `publish --check` stops before `elm publish`.

## Offline work

After `prefetch`, the compiler, elm-test, elm-format and the language
server run with the network cut off. `prefetch` realizes in the Nix store
every locked package for the current system, the tools for the Elm version
of the lock, and the editor tools. It keeps them alive with a
garbage-collector root, `.elm-purifier.lock.json.gcroot` beside the
lockfile, and puts a writable copy of the package cache at
`elm-stuff/elm-purifier/home`, because the compiler writes its build
artifacts into each package directory.

The check `conformance-offline` runs this in the Nix sandbox, which has no
network. It prefetches a fixture, compiles it, runs its tests, runs
elm-format and starts the language server.

## Editor

Editors and language servers find `elm`, `elm-test` and `elm-format` on
`PATH`, and the packages through `ELM_HOME`. The tools in
`elm-stuff/elm-purifier/bin` set `ELM_HOME` themselves, so putting that
directory first on `PATH` is all an editor needs. The same directory holds
`elm-language-server`, which runs the language server with that `PATH`:

```zsh
PATH="$PWD/elm-stuff/elm-purifier/bin:$PATH" code .
```

With direnv, the line `PATH_add elm-stuff/elm-purifier/bin` in `.envrc`
does the same. `tests/interactive.sh` starts the language server on a
fixture with an error planted in it, and checks that the server reports
that error.

## Errors and fixes

Each of these stops with a message that names the lockfile and the command
that fixes it, in the Nix build and in the command:

| What happened | What the message says |
| --- | --- |
| `elm.json` changed since the lock was made. | The lockfile was made for another `elm.json`. Run `elm-purifier lock`. |
| An application names a package that the lockfile has no hash for, or the lockfile was edited by hand. | The lockfile does not lock the package, or was edited after `elm-purifier lock` wrote it. Run `elm-purifier lock`. |
| The lockfile does not parse, lacks a field, or has another format version. | The lockfile has no such field, or reads version 3. Run `elm-purifier lock`. |
| An archive does not match its hash, because it changed on GitHub. | Nix reports the hash mismatch for the package. Run `elm-purifier lock`. |
| The package server names a URL that is not the GitHub zipball of the tag. | The lock run stops and names the package, because the builder derives that URL. |

The message says to add `--lockfile` when the lockfile is kept outside the
project. The checks `conformance-stale`, `conformance-tampered`,
`conformance-missing` and `conformance-malformed` produce these messages.

## Sources supported and refused

Elm installs packages only from the package server, and a package there is
a zip archive of a tagged GitHub release. Every package an Elm project can
depend on is therefore a locked archive, and the builder derives its URL
as `https://github.com/<author>/<project>/zipball/<version>/`. The lock run
checks each archive against the SHA-1 that the package server publishes,
and records the SHA-256.

- **Supported.** Applications and packages, on Elm 0.19.1 and 0.19.2.
  Source directories outside the project, such as `"../shared/src"`, when
  `src` is the enclosing tree and `subdirectory` is the directory of the
  project. Test suites on elm-explorations/test 1.x and 2.x. A lockfile
  kept outside the source tree.
- **Refused.** Elm 0.19.0, because no toolchain for it ships here: a
  project on 0.19.0 passes its own `elm` and `elm-test` to the builder.
  A package whose server entry names a URL other than the GitHub zipball
  of its tag. A `src` that is a derivation.

The compilers are Elm 0.19.2 from nixpkgs, with elm-test 0.19.2-1 from
nixpkgs, and Elm 0.19.1, which most published applications pin. The flake
builds Elm 0.19.1 as `elm-purifier.elm_0_19_1` with the nixpkgs recipe for
Elm. That compiler compiles the front end of the Elm reactor during its
own build, and the packages for that come from
`pkgs/elm_0_19_1/reactor.lock.json`, a lockfile of this tool. Elm 0.19.1
tests run on elm-test 0.19.1-revision15 for elm-explorations/test 2.x, and
on 0.19.1-revision9, the last release that runs test 1.x. The elm-test
release follows the major version of elm-explorations/test that `elm.json`
names. Every elm-test package of this flake puts its socket in the
directory that `TMPDIR` names, where upstream elm-test uses a fixed path
under `/tmp`.

## Real-world projects

CI builds these published projects at a pinned commit from lockfiles under
`tests/real-world`, runs their tests, and locks them again to compare the
result with the committed lockfile:

- [rtfeldman/elm-spa-example](https://github.com/rtfeldman/elm-spa-example)
  at `cb32acd`, an Elm 0.19.1 single-page application that uses
  elm-explorations/test 1.x.
- [elm-community/list-extra](https://github.com/elm-community/list-extra)
  at `46a4817`, a widely used package that uses elm-explorations/test 2.x.

`tests/interactive.sh` also runs the everyday loop on elm-spa-example:
`prefetch`, then `elm make`, `elm-test` and `elm-format`. elm-spa-example
uses elm-explorations/test 1.x, which the newer elm-test releases refuse,
which is why the Elm 0.19.1 toolchain carries elm-test 0.19.1-revision9
and picks the release by the major version of the test package.

The `elm publish` upload is not tested. It talks only to
package.elm-lang.org and needs a release tag pushed to GitHub, so the
tests run `publish --check`, which covers everything before the upload.

## Credits

elm-purifier follows the design of
[sbt-nix-backend](https://github.com/nix-purifiers/sbt-purifier): a lock
run with empty caches that records every download, a builder that runs the
tool itself in the sandbox from that lockfile, an offline mode on the same
locked files, and publishing what Nix built. Locking a build tool's
downloads for Nix also appears in the
[cargo (libnix)](https://github.com/nixcloud/cargo) project of nixcloud.
The Elm 0.19.1 build is the nixpkgs recipe for Elm, and `update`
runs [elm-json](https://github.com/zwilias/elm-json). The shared download
library is [purifier](https://github.com/nix-purifiers/purifier).

## Tests

The flake has these checks on both systems, and CI runs them:

| Check | What it proves |
| --- | --- |
| `conformance-stale`, `conformance-tampered`, `conformance-missing`, `conformance-malformed` | The lockfile messages in the section Errors and fixes. |
| `conformance-rebuild` | A second build of each output gives the same files. |
| `conformance-offline` | The everyday loop works after `prefetch` with no network. |
| `conformance-external` | A fixture whose directory holds no lockfile builds from one kept in `tests/external`. |

Two checks need the package server, so they run in CI as jobs of the same
name. `tests/conformance-relock.sh` locks every fixture, the reactor of the
compiler and both real-world projects again, and compares each result with
the committed lockfile. `tests/conformance-update.sh` updates a fixture
that pins an old `elm/json`, and checks that `elm.json` and the lockfile
then pass the stale check.

The remaining checks build the fixtures and run their outputs under Node,
run their test suites, check the package documentation, and run the unit
tests in `tests/unit`.

## License

MIT
