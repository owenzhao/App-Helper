---
name: publish-app-helper-update
description: "Prepare or publish a signed direct-download App Helper macOS update through GitHub Releases and the Sparkle appcast. Use when the user asks to release, publish, ship, package, or create an App Helper update, or explicitly invokes $publish-app-helper-update. Collect only missing release parameters before performing irreversible release actions."
---

# Publish App Helper Update

Work only in the App Helper repository. This skill is for the direct-download
macOS build, not a Mac App Store release.

## Establish the release scope

Inspect the checkout, current `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`,
`Info.plist`, `website/public/appcast.xml`, and the existing GitHub Pages
workflow before changing anything.

If a required value cannot be discovered, ask one concise question containing
only the missing items. Collect these parameters as applicable:

- Target marketing version and build number, or permission to choose the next
  build number.
- Existing signed and notarized `.dmg` or `.zip` path. If absent, ask whether
  to prepare only, or to build, sign, and notarize it.
- GitHub Release tag and asset filename when they cannot be inferred from the
  archive or user request.
- Whether the request is **prepare** (local files and checks only) or
  **publish** (create/upload a GitHub Release, push changes, and deploy Pages).

Do not ask for or print the Sparkle private key. The local key is in the login
Keychain under `com.parussoft.app-helper.sparkle`.

## Prepare an update

1. Keep unrelated worktree changes untouched. Verify the archive contains only
   `App Helper.app`, is Developer ID signed and notarized, and has a
   `CFBundleVersion` greater than every published Sparkle item.
2. Maintain a local directory containing current and retained release archives.
   Do not replace an existing appcast with an empty feed.
3. Run Sparkle `generate_appcast` with:

   ```sh
   generate_appcast \
     --account com.parussoft.app-helper.sparkle \
     --download-url-prefix "https://github.com/owenzhao/App-Helper/releases/download/<tag>/" \
     --link "https://owenzhao.github.io/App-Helper/" \
     <release-archives-directory>
   ```

   Locate the `generate_appcast` tool from the resolved Sparkle package; do not
   substitute a hand-written item or signature. Copy the generated appcast to
   `website/public/appcast.xml`.
4. Inspect the generated item: visible version, build number, release notes,
   GitHub Release asset URL, file length, and EdDSA signature must all be
   present and match the archive.
5. Build the Release target with an explicit writable derived-data directory.
   Treat a successful build as source validation only, not proof that the
   signed archive or public update flow works.

## Publish only with explicit authority

When the user says **publish**, summarize the exact tag, archive, appcast
change, and commits. Then create/upload the GitHub Release, commit only the
release-related source and appcast files, push the intended branch, and let the
existing GitHub Pages workflow deploy the feed.

After deployment, verify the public `appcast.xml` with a cache-busting request:

- HTTP status is 200 and content type is XML.
- The new item reports the intended `sparkle:shortVersionString` and a larger
  `sparkle:version`.
- Its enclosure URL downloads the expected archive.

Report separately what was verified locally, on GitHub, and through the public
feed. Never claim an update installs correctly until it has been tested from a
previously installed, lower-version app.
