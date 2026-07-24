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
    inputs@{ flake-parts, self, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { config, ... }:
      {
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
          # nix-eval-jobs lives as a git submodule at subprojects/nix-eval-jobs
          # in Lix's tree; without this, makeLixScope's nix-eval-jobs build
          # fails unpacking ("No such file or directory").
          git.fetchSubmodules = true;
          cargo_lock = [ "Cargo.lock" ];
          script = pkgs: ''
            ${pkgs.jq}/bin/jq -r .version "$src/version.json" > "$out/version"
          '';
        };

        # nil, tracked from its own main so it builds against dev Lix and updates
        # alongside it via `update-sources`.
        nvfetcher.sources.nil = {
          src.git = "https://github.com/oxalica/nil.git";
          src.branch = "main";
          fetch.git = "https://github.com/oxalica/nil.git";
          cargo_lock = [ "Cargo.lock" ];
        };

        # Build the whole Lix scope against `pkgs`, compiling Lix with `cxxStdenv`.
        # This is the reuse point: a consumer (e.g. the dotfiles) that wants ccache
        # calls `inputs.ivylix.lib.mkScope { pkgs = <base nixpkgs>; cxxStdenv =
        # <ccacheStdenv>; }` — the ENTIRE scope (nil, nix-eval-jobs, …) is then
        # built against that single ccache-Lix, so there is no second lix build.
        # Exposed as a top-level flake output (not `flake.lib`, which the ivixlib
        # mechanism already contributes `withExtra` to — flake-parts can't merge
        # two `flake.lib` definitions).
        flake.mkScope =
          {
            pkgs,
            cxxStdenv ? pkgs.clangStdenv,
          }:
          import ./default.nix {
            inherit pkgs cxxStdenv;
            inherit (inputs) izlix;
            sources = config.flake.lib.withExtra (
              pkgs.callPackage "${self}/_sources/generated.nix" { }
            );
          };

        perSystem =
          { pkgs, ... }:
          let
            scope = config.flake.mkScope { inherit pkgs; };
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
      }
    );
}
