# MLX Audio Dependency Policy

Voxt uses `mlx-audio-swift` through the mirror fork at `https://github.com/hehehai/mlx-audio-swift`.

## Version rules

- Prefer upstream release tags when they already contain the STT features or fixes Voxt needs.
- When upstream `main` contains required changes that are not released yet, sync the fork's `main` to upstream and create a Voxt tag on the selected commit.
- Switch Voxt back to upstream release tags once an official release covers the same changes.

## Tag rules

- Keep the fork as a mirror plus tags only. Do not land Voxt-specific source patches there unless absolutely required.
- Use tags in the form `v<upstream-version>-voxt.<n>`.
- Do not reuse upstream tag names for different commits.

## Update workflow

1. Sync `hehehai/mlx-audio-swift` `main` from `Blaizzy/mlx-audio-swift`.
2. Pick the target commit from fork `main`.
3. Create a new Voxt tag on that commit.
4. Point `Voxt.xcodeproj` at the fork URL and `exactVersion`.
5. Build Voxt and verify STT model loading before shipping.

## Current pin

- Fork: `hehehai/mlx-audio-swift`
- Tag: `v0.1.2-voxt.1`
- Commit: `da935116eb83b033104e6135aaa7db87320d17d4`
