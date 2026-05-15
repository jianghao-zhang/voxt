# Voxt Server Beta Updates

Voxt supports stable and beta Sparkle appcast feeds. The macOS app chooses the feed from the user's Beta Updates preference and does not require a separate JSON update API.

## Feeds

- Stable feed: `/updates/stable/appcast.xml`
- Beta feed: `/updates/beta/appcast.xml`

The stable feed must only include stable releases. Do not publish beta packages in the stable feed, because users who have not opted into beta updates will consume this appcast.

The beta feed should include beta releases. It should also include stable releases when a stable build supersedes the latest beta, so beta users can move forward to the stable build without switching channels.

## Client Requests

Voxt requests the selected appcast URL with a `lang` query item:

```text
/updates/stable/appcast.xml?lang=en
/updates/beta/appcast.xml?lang=zh-Hans
```

Voxt also sends an `Accept-Language` header derived from the app interface language, for example:

```text
Accept-Language: zh-Hans, zh;q=0.9, en;q=0.8
```

The server may use either signal to localize release notes. If localized release notes are unavailable, return the default release notes instead of failing the request.

## Sparkle Requirements

- Both feeds must use packages signed for the same Sparkle EdDSA public key embedded in the app.
- `sparkle:version` must be monotonically increasing across stable and beta releases.
- `sparkle:shortVersionString` should use the user-facing version, such as `1.4.0-beta.1` for beta releases.
- Existing Sparkle metadata, enclosure signatures, minimum system version, file length, and release notes behavior should match the stable feed conventions.

Voxt release CI computes `sparkle:version` and the app's `CFBundleVersion` from the tag:

```text
major * 100000000 + minor * 100000 + patch * 100 + releaseSlot
```

- Stable tag `v1.4.0` uses release slot `99`, producing `100400099`.
- Beta tag `v1.4.0-beta.1` uses release slot `1`, producing `100400001`.
- Beta tag `v1.4.0-beta.2` uses release slot `2`, producing `100400002`.

This leaves beta versions lower than the matching stable version while keeping every published update newer than the previous release line. Beta release numbers must be in the `1...98` range.

## Release CI Contract

The GitHub release workflow uploads update metadata to Voxt Server with:

```text
POST /api/pkg/update
channel=stable|beta
version=<tag without leading v>
sparkleVersion=<computed build number>
```

After uploading metadata and the signed zip, the workflow asks the server to regenerate the selected appcast:

```json
{"channel":"stable","version":"1.4.0","mode":"replace-latest"}
```

For beta releases the same payload uses `"channel":"beta"` and a beta version such as `"1.4.0-beta.1"`.

## Channel Behavior

- Users with Beta Updates off request only the stable feed.
- Users with Beta Updates on request the beta feed for both manual and automatic Sparkle checks.
- Switching channels in the app affects the next update check; it does not start a check immediately.
