{
  description = "ivylix — a personal Lix fork (à la izlix), with the source pinned/updated via nvfetcher through the shared `ivixlib` mechanism.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    den.url = "github:denful/den/latest";

    # The shared nvfetcher sources+script mechanism (denful namespace: ivixlib).
    izlix.url = "github:isabelroses/izlix";
    izlix.inputs.nixpkgs.follows = "nixpkgs";
    ivixlib.url = "github:auscyber/ivixlib";
    ivixlib.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
        "aarch64-linux"
      ];

      imports = [
        inputs.den.flakeModule
        # The nvfetcher machinery (update-sources / postprocess-sources apps and
        # the `sources` module-arg) rides ivixlib's flakeModule …
        inputs.ivixlib.flakeModules.default
        # … and its denful namespace is consumed here.
        (inputs.den.namespace "ivixlib" inputs.ivixlib)
      ];

      # The one source this repo owns. `update-sources` (from ivixlib) refreshes
      # it; the post-fetch `script` bakes the real semver from version.json into
      # _sources/<hash>/version so makeLixScope sees a >= 2.92 version.
      nvfetcher.sources.lix = {
        src.git = "https://git.lix.systems/lix-project/lix.git";
        src.branch = "main";
        fetch.git = "https://git.lix.systems/lix-project/lix.git";
        cargo_lock = [ "Cargo.lock" ];
        script = pkgs: ''
          ${pkgs.jq}/bin/jq -r .version "$src/version.json" > "$out/version"
        '';
      };

      perSystem =
        {
          pkgs,
          sources,
          ...
        }:
        let
          scope = import ./default.nix {
            inherit pkgs sources;
            inherit (inputs) izlix;
          };
        in
        {
          # The lix scope's derivations. Listed explicitly (not `filterAttrs`,
          # which would force every scope value — and thus the baked `version` —
          # just to merge with the mechanism's own `packages.{update,postprocess}-
          # sources`, deadlocking the very apps that bake it). The raw scope is not
          # exposed as `legacyPackages` because it also carries non-derivation
          # scope internals (`callPackage`, `packages`, …) that trip flake-parts.
          packages = {
            inherit (scope)
              lix
              nil
              nix-eval-jobs
              nix-fast-build
              nixpkgs-review
              nixpkgs-reviewFull
              colmena
              ;
          };
        };
    };
}
