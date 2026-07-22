# Based on isabelroses/izlix, but the Lix source is pinned/updated via nvfetcher
# (the shared `ivixlib` mechanism) instead of izlix's `misc/hack.nix` + nix-update.
#
# `sources` is the nvfetcher `sources` module-arg (withExtra-augmented), so
# `sources.lix.output` points at the committed `_sources/sha256-<hash>/` folder
# where the post-fetch script baked the real semver.
{
  pkgs,
  sources,
  izlix,
  lib ? pkgs.lib,
  # Stdenv used to compile Lix's C++. Defaults to clang (makeLixScope's own
  # default for >= 2.92). A consumer that wants ccache passes a ccache-wrapped
  # clang here, so the whole scope (nil, nix-eval-jobs, …) is rebuilt against
  # that one Lix — no duplicate lix build.
  cxxStdenv ? pkgs.clangStdenv,
}:
let
  # Real Lix semver, baked from the source's version.json by the
  # `nvfetcher.sources.lix` post-fetch script. `sources.lix.version` itself is
  # only the git rev, which makeLixScope can't compare against "2.92" and so
  # wrongly demands a separate `lix-doc` cargoDeps.
  version = lib.fileContents "${sources.lix.output}/version";
  cargoDeps = pkgs.rustPlatform.importCargoLock sources.lix.cargoLock."Cargo.lock";

  scope = pkgs.lixPackageSets.makeLixScope {
    attrName = "ivylix";

    lix-args = {
      inherit version cargoDeps;
      inherit (sources.lix) src;

      # Patches come straight from izlix (the input), so this fork tracks
      # izlix's patch set rather than vendoring copies.
      patches = [
        # backport some of nix's newer eval stats stuff (touches json)
        "${izlix}/patches/libexpr-backport-new-stats.patch"
        # nice-to-have for accuracy
        "${izlix}/patches/libexpr-backport-counter-for-stats.patch"
        # don't allocate values in a lambda when `_:` is the argument
        "${izlix}/patches/lixexpr-don-t-allocate-on-_.patch"
      ];
    };
  };

  finalScope = scope.overrideScope (
    final: prev: {
      nixpkgs-review = prev.nixpkgs-review.override {
        nix-eval-jobs = final.nix-eval-jobs;
      };

      # Stock nixpkgs `nil` doesn't build against dev Lix, so track nil's own main
      # via nvfetcher (`nvfetcher.sources.nil`) — `update-sources` bumps it in lock
      # step with Lix. Plus izlix's inherit-completion patch.
      nil = prev.nil.overrideAttrs (
        _finalAttrs: prevAttrs: {
          inherit (sources.nil) src version;
          cargoDeps = pkgs.rustPlatform.importCargoLock sources.nil.cargoLock."Cargo.lock";

          # broken by docs updates
          doCheck = false;

          patches = prevAttrs.patches or [ ] ++ [
            "${izlix}/patches/nil-feat-inherit-completion.patch"
          ];
        }
      );

      lix = (prev.lix.override {
        withAWS = false;
        stdenv = cxxStdenv;
      }).overrideAttrs (
        oa:
        let
          cxxLinkerFor = stdenv: lib.getExe' stdenv.cc "${stdenv.cc.targetPrefix}c++";
          hostCargoEnvVar = pkgs.stdenv.hostPlatform.rust.cargoEnvVarTarget;
          buildCargoEnvVar = pkgs.stdenv.buildPlatform.rust.cargoEnvVarTarget;
        in
        {
          # Kinda funny right
          # worth it https://akko.isabelroses.com/notice/AjlM7Vfq1zlgsEzk0G
          postPatch = oa.postPatch or "" + ''
            substituteInPlace lix/libmain/shared.cc \
              --replace-fail "(Lix, like Nix)" "(Lix, like Nix but for lesbians)"
          '';

          buildInputs = [
            # for build mimalloc patch
            pkgs.mimalloc
          ]
          ++ (lib.subtractLists [ final.editline ] oa.buildInputs);

          nativeBuildInputs = [
            pkgs.cacert
            pkgs.mdbook-linkcheck2

            pkgs.cargo
            pkgs.rustPlatform.cargoSetupHook
          ]
          ++ (lib.subtractLists [ pkgs.rust-cbindgen ] oa.nativeBuildInputs);

          env =
            oa.env
            // {
              # Link the rust bits with the same (ccache-)clang c++ used for the
              # C++ tree.
              "CARGO_TARGET_${hostCargoEnvVar}_LINKER" = cxxLinkerFor cxxStdenv;
            }
            // lib.optionalAttrs (hostCargoEnvVar != buildCargoEnvVar) {
              "CARGO_TARGET_${buildCargoEnvVar}_LINKER" = cxxLinkerFor pkgs.buildPackages.clangStdenv;
            };

          depsBuildBuild = [
            pkgs.buildPackages.clangStdenv.cc
          ];

          # these are flakey
          doInstallCheck = false;
        }
      );
    }
  );
in
finalScope
