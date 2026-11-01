# SPDX-License-Identifier: MIT
{ ... }:
{
  config,
  inputs,
  lib,
  ...
}:
{

  imports = [ inputs.flake-parts.flakeModules.partitions ];

  debug = false;
  caisson = {
    libOverlays.exported = libOverlays: {
      inherit (libOverlays) default;
    };

    # The scope `elm-purifier` is the `default` entry of this flake's package
    # overlay registry (pkg-overlays/): the package set applies it by
    # default, and the flake exports it as `pkgOverlays` and as the plain
    # `overlays.default`. The flake's `packages` output holds the
    # derivations of the scope, because the scope also holds the builder,
    # which is a function.
    nixpkgs = {
      packages.export.enabled = false;
    };
  };

  # `nix run github:nix-purifiers/elm-purifier -- lock` locks the project
  # in the current directory.
  perSystem =
    { pkgs, ... }:
    {
      packages = lib.filterAttrs (_: lib.isDerivation) pkgs.elm-purifier // {
        default = pkgs.elm-purifier.cli;
      };
    };

  partitionedAttrs.checks = "checks";
  partitionedAttrs.formatter = "formatter";

  partitions.formatter = {
    extraInputs = (lib.caisson.pins.flake-compat ../../../tests/dependencies).sources;
    module =
      { inputs, ... }:
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        perSystem.treefmt.programs.nixfmt.enable = true;
      };
  };

  partitions.checks = {
    extraInputs = (lib.caisson.pins.flake-compat ../../../tests/dependencies).sources;
    module =
      { inputs, self, ... }:
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        perSystem =
          { pkgs, system, ... }:
          {
            checks = import ../../../tests {
              pkgs = pkgs.extend self.overlays.default;
              inherit (self.packages.${system}) cli;
              purifierSrc = self.inputs.purifier;
            };
            treefmt.programs.nixfmt.enable = true;
          };
      };
  };

}
