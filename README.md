> [!WARNING]
> This is not Lix! It's a personal fork of [izlix](https://github.com/isabelroses/izlix)
> for silly little features. None of these patches belong in upstream Lix.

`ivylix` builds a patched Lix scope (`lix`, `nil`, `nix-eval-jobs`,
`nixpkgs-review`, `colmena`, …) via `lixPackageSets.makeLixScope`.

Patches applied (see `./patches`):

- `libexpr-backport-new-stats` — backport newer eval-stats
- `libexpr-backport-counter-for-stats` — accuracy counter for the above
- `lixexpr-don-t-allocate-on-_` — don't allocate a value for a `_:` lambda arg

…plus the obligatory `(Lix, like Nix but for lesbians)` banner.

## Source pinning: nvfetcher, not nix-update

Unlike izlix (which pins the source via `misc/hack.nix` + `nix-update`), the Lix
source here is pinned with **nvfetcher**, through the shared **`ivixlib`**
mechanism (a denful namespace + flakeModule). The pin lives in
`_sources/generated.{json,nix}`; a post-fetch `script` bakes the real semver
from Lix's `version.json` into `_sources/<hash>/version` (makeLixScope needs a
`>= 2.92` version string, not the git rev).

### Updating

```console
nix run .#update-sources        # re-pin lix via the forked nvfetcher (ivixlib)
```

`.github/workflows/update.yml` runs this nightly and commits the result.

## Building

```console
nix build .#lix                 # the patched lix
nix build .#nil                 # nil against this lix
nix flake show                  # everything in the scope
```
