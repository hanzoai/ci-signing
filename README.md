# ci-signing — omni-platform build & sign for GitHub Actions

Brand-neutral, drop-in **reusable workflows** to build/sign/notarize release artifacts across
**macOS · Windows · Linux · iOS · Android · browser extensions (Chrome / Firefox / Safari)** on self-hosted runners. Fork it into your org, set a
handful of secrets/vars, and `uses:` the workflows from any repo. No secrets live in this repo.

**Ops setup:** see [`docs/OPS-RUNBOOK.md`](docs/OPS-RUNBOOK.md) — full per-org step-by-step (accounts, certs, `az` commands, secrets loading).

> **Use it:** this repo is **public**, so reference the workflows directly from any org as
> `hanzoai/ci-signing/.github/workflows/<name>.yml@v1` — no fork needed. (Or click **"Use this
> template"** to keep a pinned copy in your own org.)

## Platforms

| Workflow | Runner label | Does |
|---|---|---|
| `sign-macos.yml` | `macOS` | Developer ID sign → notarize → staple → `.dmg` |
| `sign-ios.yml` | `macOS` | export signed `.ipa` from a prebuilt `.xcarchive` (+ optional TestFlight) |
| `sign-windows.yml` | `Windows` | Authenticode via **Azure Trusted Signing** (OIDC) — jsign/YubiKey variant inline |
| `sign-linux.yml` | `Linux` | GPG detached `.asc` + `SHA256SUMS` (+ optional keyless cosign) |
| `sign-android.yml` | `Linux` | sign a prebuilt **unsigned** `.aab/.apk` with your upload key (+ optional Play upload) |
| `publish-chrome.yml` | `Linux` | upload extension `.zip` to the Chrome Web Store (covers all Chromium stores) |
| `publish-firefox.yml` | `Linux` | `web-ext sign` → Mozilla-signed `.xpi` on AMO (listed or unlisted) |
| `publish-safari.yml` | `macOS` | export App-Store-signed Safari extension app from a `.xcarchive` → App Store Connect |

**Every leg is sign-only.** Your repo builds and uploads an artifact; the signer **downloads it,
signs, and re-uploads `<name>-signed`** — no build logic lives here. (iOS: your build job runs
`xcodebuild archive` and uploads the `.xcarchive`; Android: it uploads the unsigned `.aab/.apk`.)
Browser extensions are **publish-only** — Chrome/Firefox are signed by the stores; Safari ships as an App Store app signed with your Apple cert.

## What you need — per org

| Platform | Obtain | Stored as (Actions secret) |
|---|---|---|
| **macOS** | Team ID · **Developer ID Application** `.p12` · ASC API key `.p8`+IDs | `MACOS_CERT_P12_BASE64`,`MACOS_CERT_PASSWORD`,`ASC_API_KEY_P8_BASE64`,`ASC_API_KEY_ID`,`ASC_API_ISSUER_ID`,`APPLE_TEAM_ID` |
| **iOS** | **Apple Distribution** `.p12` · **provisioning profile** `.mobileprovision` · (ASC key + Team ID shared w/ mac) | `IOS_DIST_CERT_P12_BASE64`,`IOS_DIST_CERT_PASSWORD`,`IOS_PROVISIONING_PROFILE_BASE64` |
| **Windows** | Azure **Trusted Signing** account + per-org **cert profile** + OIDC **service principal** | `AZURE_CLIENT_ID`,`AZURE_TENANT_ID`,`AZURE_SUBSCRIPTION_ID` (+ account/profile in `vars`) |
| **Linux** | a **GPG key** (publish the pubkey) | `LINUX_GPG_PRIVATE_KEY`,`LINUX_GPG_PASSPHRASE` |
| **Android** | **upload keystore** `.jks` + alias/passwords · (Play **service-account JSON** for upload) | `ANDROID_KEYSTORE_BASE64`,`ANDROID_KEYSTORE_PASSWORD`,`ANDROID_KEY_ALIAS`,`ANDROID_KEY_PASSWORD`,`PLAY_SERVICE_ACCOUNT_JSON` |
| **Chrome** (+Edge/Brave/Opera) | Chrome Web Store **$5 once** dev account → OAuth API creds | `CHROME_CLIENT_ID`,`CHROME_CLIENT_SECRET`,`CHROME_REFRESH_TOKEN` |
| **Firefox** | AMO account (free) → API key | `AMO_JWT_ISSUER`,`AMO_JWT_SECRET` |
| **Safari** | reuses **Apple Distribution** cert + ASC key (same secrets as iOS) | — |

Push them all from local files: `ORG=<org> ./scripts/load-org-secrets.sh` (see the script header for the file layout).
Non-secret config (Azure account/profile names, Android package name) goes in **org/repo `vars`**.

## How to generate each (the only-you parts)
- **Apple (mac + iOS):** Apple Developer Program → **Team ID**; Certificates → **Developer ID Application** (mac) and **Apple Distribution** (iOS) → export `.p12` from Keychain; iOS also needs a **Provisioning Profile** for the bundle ID; App Store Connect → Integrations → **API key** `.p8` + Key ID + Issuer ID.
- **Windows — Azure Trusted Signing:** subscription → register `Microsoft.CodeSigning` → Trusted Signing **account** (e.g. West US 2) → **Identity Validation** per org → **Certificate Profile** (Public Trust) per org → OIDC **service principal** with role *"Trusted Signing Certificate Profile Signer"* + GitHub federated credential.
- **Linux — GPG:** `gpg --quick-generate-key "<Org> Releases <releases@org>" ed25519 sign 2y`; export secret key (base64 → secret), publish the public key.
- **Android:** `keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 9125 -alias upload`; register the app under **Play App Signing** (Google holds the app key; this is your **upload** key); for CI upload create a **Play Console service account** → JSON.
- **Chrome:** Chrome Web Store dashboard → pay the **$5** one-time dev fee; create a Google Cloud OAuth client → client id/secret + a **refresh token** (one-time auth flow).
- **Firefox:** addons.mozilla.org → Developer Hub → **API keys** (JWT issuer + secret). **Safari needs nothing new** — it uses your Apple Distribution cert + ASC key.

## Cost (3 orgs, all platforms)
- Apple (mac + iOS): **$99/yr/org** ($297) · Google Play: **$25 once/org** ($75 one-time)
- Windows (Azure Trusted Signing): **~$120/yr total** · Linux: **$0**
- Extensions: **Chrome $5 once** · Firefox/Edge free · Safari $0 (uses Apple)
- **≈ $417/yr + ~$80 one-time.** (Self-hosting Windows keys → Windows alone $600–1,200/yr; only for key custody, not cost — see `sign-windows.yml` for the jsign/YubiKey escape hatch.)

## Files
```
.github/workflows/  sign-{macos,ios,windows,linux,android} · publish-{chrome,firefox,safari} · release.example
scripts/            load-org-secrets.sh
```
`release.example.yml` shows a full 5-platform release pipeline — copy into an app repo, replace `OWNER`, set secrets/vars.
