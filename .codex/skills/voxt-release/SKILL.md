---
name: voxt-release
description: Local release manager for Voxt. Use when the user asks to prepare a new Voxt version, generate release notes, build artifacts, or update appcast for in-app updates.
---

# Voxt Release

## Overview

This skill executes the project-local release flow for Voxt.
It is used when the user asks to:

- prepare/release a new version
- generate release notes from git history
- run local packaging scripts
- update `updates/appcast.json`
- prepare release commits

## Quick Start

1. Confirm release target and current repository state.
2. Follow the local release flow (no auto GitHub release workflow is used).
3. Prepare release artifacts locally in Xcode and place them in `build/release/artifacts/`.
4. Keep `CHANGELOG.md`, `build/release/artifacts/*`, and `updates/appcast.json` consistent.
5. Mandatory before release: `CHANGELOG.md` must include a new release section for the target version.
6. Create/push git tag and publish GitHub release assets when shipping.

## Required Inputs

- `VERSION`: target semantic version string, e.g. `1.2.3` (do not include `v` prefix)
- Repository should have a clean or intentional dirty working tree state depending on pre-release checks.

## Workflow

### Step 1 — Prepare changelog (mandatory)

- Open `CHANGELOG.md`.
- Follow the changelog section style currently used in the file.
- Generate notes manually from git history or with `git log`.
- Insert notes under a new version section and keep `## [Unreleased]` section for future entries.
- Do not proceed to build if changelog is not updated for the target version.

Suggested command pattern:

```bash
VERSION="1.2.3"
BASE_TAG="$(git tag --list 'v*' --sort=-v:refname | sed -n '1p')"
echo "## [${VERSION}] - $(date +%F)"
echo "### Added"
git log ${BASE_TAG:+${BASE_TAG}..HEAD} --grep='^feat\\|^add' --pretty='- %s'
echo "### Fixed"
git log ${BASE_TAG:+${BASE_TAG}..HEAD} --grep='^fix\\|^bug' --pretty='- %s'
echo "### Changed"
git log ${BASE_TAG:+${BASE_TAG}..HEAD} --grep='^refactor\\|^perf\\|^chore' --pretty='- %s'
```

### Step 2 — Build release artifacts locally in Xcode

In Xcode:

```bash
1. In Xcode, run Archive and export:
   - `Voxt-<VERSION>.app.zip`
   - `Voxt-<VERSION>.pkg`
2. Copy both artifacts into:
   - `build/release/artifacts/Voxt-<VERSION>.app.zip`
   - `build/release/artifacts/Voxt-<VERSION>.pkg`
```

Expected outputs:

- `build/release/artifacts/Voxt-<VERSION>.app.zip`
- `build/release/artifacts/Voxt-<VERSION>.pkg`

### Step 3 — Update in-repo manifest from local artifacts

Run:

```bash
VERSION="1.2.3"
PKG_PATH="build/release/artifacts/Voxt-${VERSION}.pkg"
SHA256="$(shasum -a 256 "${PKG_PATH}" | awk '{print $1}')"
cat > updates/appcast.json <<JSON
{
  "version": "${VERSION}",
  "minimumSupportedVersion": "${VERSION}",
  "downloadURL": "https://github.com/hehehai/voxt/releases/download/v${VERSION}/Voxt-${VERSION}.pkg",
  "releaseNotes": "See CHANGELOG.md for details.",
  "publishedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "sha256": "${SHA256}"
}
JSON
```

If your generated manifest already exists at `build/release/artifacts/appcast.json`, use:

```bash
scripts/release/publish_manifest.sh build/release/artifacts/appcast.json updates/appcast.json
```

### Step 4 — Commit

- Include at least:
  - `CHANGELOG.md`
  - `updates/appcast.json`
  - optionally any required artifacts metadata

Example:

```bash
git add CHANGELOG.md updates/appcast.json
git commit -m "release: v1.2.3"
```

### Step 5 — Publish GitHub release

1. Create and push git tag:

```bash
git tag v1.2.3
git push origin v1.2.3
```

2. Publish release and upload artifacts:

```bash
gh release create v1.2.3 \
  --title "v1.2.3" \
  --notes "Release 1.2.3" \
  build/release/artifacts/Voxt-1.2.3.app.zip \
  build/release/artifacts/Voxt-1.2.3.pkg
```

If the release already exists:

```bash
gh release upload v1.2.3 \
  build/release/artifacts/Voxt-1.2.3.app.zip \
  build/release/artifacts/Voxt-1.2.3.pkg \
  --clobber
```

## Validation checklist

- Changelog update and build/manifest flow steps below have been followed.
- `CHANGELOG.md` has a new release entry for the version being released.
- Manifest URL still points to `https://raw.githubusercontent.com/hehehai/voxt/main/updates/appcast.json`.
- `AppUpdateManager` can read updated `version`, `minimumSupportedVersion`, and `downloadURL` from manifest.
- `git diff` shows no unrelated file churn after release commit.

## Allowed tools

- `Bash` for `git`, `sed`, `awk`, and release scripts.
- `Bash` for file viewing/modification commands under `scripts/` and `updates/`.
