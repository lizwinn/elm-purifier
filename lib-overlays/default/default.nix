# SPDX-License-Identifier: MIT
#
# The `elm-purifier` library namespace:
#
#   buildElmProject  the builder (nix/lib/build-elm-project.nix), with the
#                    shared purifier library this flake lists as
#                    `lib.purifier`
#   readLock         the lock in memory of the purifier contract, from the
#                    lockfile and elm.json of a project (nix/lib/lock.nix):
#                    readLock { src, subdirectory ? ".", lockFile ? ... }
{ ... }:
{

  overlay = final: prev: {
    elm-purifier = (prev.elm-purifier or { }) // {
      buildElmProject = import ../../nix/lib/build-elm-project.nix { inherit (final) purifier; };
      readLock =
        {
          src,
          subdirectory ? ".",
          lockFile ? src + "/${subdirectory}/elm-purifier.lock.json",
        }:
        (import ../../nix/lib/lock.nix {
          inherit lockFile;
          elmJsonFile = src + "/${subdirectory}/elm.json";
        }).lock;
    };
  };

}
