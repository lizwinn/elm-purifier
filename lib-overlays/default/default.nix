# SPDX-License-Identifier: MIT
#
# The `elm-purifier` library namespace. It holds nothing: the builder
# needs a package set, so it is the package `buildElmProject` that the
# default package overlay adds.
{ ... }:
{

  overlay = final: prev: {
    elm-purifier = prev.elm-purifier or { };
  };

}
