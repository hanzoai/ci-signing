# Ops Runbook — code signing & publishing

Stand up signed, store-publishable builds for **macOS · iOS · Windows · Linux · Android** and
**browser extensions (Chrome · Firefox · Safari)** for each org. App repos build artifacts and call the
reusable workflows in this repo (`<org>/ci-signing` or `hanzoai/ci-signing@v1`) to sign/publish.
Run each platform section **once per org**; §12 is the master checklist.

> **Critical path — Day 1** (multi-day waits, block everything else):
> 1. Create the Azure subscription + submit the **3 Trusted Signing identity validations** (Microsoft reviews 1–5 business days).
> 2. Confirm Account-Holder/Admin on each org's Apple account.

**Legend:** `YOU` = portal/account action · `PRODUCES →` = file/value for the secrets loader · `secrets/<org>/…` = drop files here (gitignored) before running the loader.

## 0 · Prerequisites (on the signing Mac, once)
```bash
brew install azure-cli gnupg
gh auth status                              # GitHub CLI as an org admin
git clone https://github.com/hanzoai/ci-signing && cd ci-signing
mkdir -p secrets/{hanzoai,luxfi,zooai}      # gitignored
```

### Accounts to open
| Account | Where | Scope | Cost |
|---|---|---|---|
| Apple Developer Program | developer.apple.com | per org ×3 | already have |
| Azure + Trusted Signing | portal.azure.com | 1 shared | ~$10/mo |
| Google Play Console | play.google.com/console | per org ×3 | $25 once ea |
| Chrome Web Store | chrome.google.com/webstore/devconsole | 1 or per org | $5 once |
| Firefox AMO | addons.mozilla.org | 1 or per org | free |

---

## 1 · macOS — Developer ID (notarized .dmg)
1. **Team ID** — developer.apple.com → *Membership* → copy the 10-char Team ID.
2. **Developer ID Application cert** — *Certificates ▸ +* → "Developer ID Application" (CSR via Keychain Access ▸ Certificate Assistant) → download → install.
3. **Export** — Keychain Access ▸ My Certificates → right-click → **Export** as `developer_id.p12` (set a password).
4. **App Store Connect API key** — appstoreconnect.apple.com → *Users and Access ▸ Integrations ▸ Keys* → **+** (App Manager) → download `AuthKey_XXXX.p8`; copy Key ID + Issuer ID.
5. Verify: `security find-identity -v -p codesigning`.

**PRODUCES →** `developer_id.p12`, `p12_password.txt`, `AuthKey.p8`, `asc.env` (`ASC_API_KEY_ID= ASC_API_ISSUER_ID= APPLE_TEAM_ID=`)

## 2 · iOS — App Store (reuses §1 Apple account)
1. **Apple Distribution cert** → export `ios_dist.p12` (with password).
2. **Bundle ID** — *Identifiers* → register (e.g. `ai.hanzo.app`).
3. **Provisioning profile** — *Profiles ▸ +* → "App Store" → App ID + Distribution cert → `profile.mobileprovision`.

**PRODUCES →** `ios_dist.p12`, `ios_dist_password.txt`, `profile.mobileprovision`

## 3 · Windows — Azure Trusted Signing
**3.1 once:**
```bash
az login; az account set --subscription [SUB_ID]
az provider register --namespace Microsoft.CodeSigning
az extension add --name trustedsigning
az group create -n rg-signing -l westus2
az trustedsigning create -g rg-signing -n brand-signing -l westus2 --sku Basic
```
**3.2 identity validation — per org (PORTAL):** Trusted Signing account → *Identity validations ▸ New* → legal entity → wait 1–5 days; record the **validation id**.

**3.3 cert profile — per org (after approval):**
```bash
az trustedsigning certificate-profile create -g rg-signing --account-name brand-signing \
  -n hanzo-public-trust --profile-type PublicTrust --identity-validation-id [VALIDATION_ID]
```
**3.4 OIDC service principal:**
```bash
az ad app create --display-name gha-ci-signing
APP_ID=$(az ad app list --display-name gha-ci-signing --query "[0].appId" -o tsv)
az ad sp create --id $APP_ID
ACCT_ID=$(az trustedsigning show -g rg-signing -n brand-signing --query id -o tsv)
az role assignment create --assignee $APP_ID --role "Trusted Signing Certificate Profile Signer" --scope $ACCT_ID
az ad app federated-credential create --id $APP_ID --parameters '{
  "name":"gha-hanzoai","issuer":"https://token.actions.githubusercontent.com",
  "subject":"repo:hanzoai/myapp:ref:refs/tags/v1","audiences":["api://AzureADTokenExchange"]}'
az account show --query tenantId -o tsv     # = AZURE_TENANT_ID
```
**PRODUCES →** `azure.env` (`AZURE_CLIENT_ID=$APP_ID AZURE_TENANT_ID= AZURE_SUBSCRIPTION_ID=`); set repo **vars** `AZURE_SIGNING_ACCOUNT=brand-signing`, `AZURE_CERT_PROFILE=<org>-public-trust`.

## 4 · Linux — GPG
```bash
gpg --quick-generate-key "Hanzo Releases <releases@hanzo.ai>" ed25519 sign 2y   # set a passphrase
KEYID=$(gpg --list-secret-keys --keyid-format=long --with-colons | awk -F: '/^sec/{print $5; exit}')
gpg --armor --export-secret-keys $KEYID > secrets/hanzoai/gpg_private.asc
gpg --armor --export $KEYID > hanzo-signing-pubkey.asc      # publish on your releases page
```
**PRODUCES →** `gpg_private.asc`, `gpg_passphrase.txt`

## 5 · Android — Play (upload keystore + Play App Signing)
```bash
keytool -genkeypair -v -keystore secrets/hanzoai/upload.jks -alias upload \
  -keyalg RSA -keysize 2048 -validity 9125     # store + key passwords → android.env
```
1. **Play App Signing** — Play Console → app → *Setup ▸ App integrity* → opt in (upload this key's cert).
2. **Play service account** — GCP → service account → grant Play release access in *Users & permissions* → download JSON.

**PRODUCES →** `upload.jks`, `android.env` (`KEYSTORE_PASSWORD= KEY_ALIAS=upload KEY_PASSWORD=`), `play-service-account.json`

## 6 · Chrome extension — Web Store (+ all Chromium)
1. chrome.google.com/webstore/devconsole → pay **$5**.
2. Google Cloud Console → enable **Chrome Web Store API** → OAuth client (Desktop) → client id + secret.
3. Refresh token:
```bash
# open (replace CLIENT_ID), approve, copy `code` from the redirect:
#   https://accounts.google.com/o/oauth2/auth?response_type=code&access_type=offline&scope=https://www.googleapis.com/auth/chromewebstore&client_id=[CLIENT_ID]&redirect_uri=http://localhost:8818
curl -s https://oauth2.googleapis.com/token -d client_id=[CLIENT_ID] -d client_secret=[CLIENT_SECRET] \
  -d code=[CODE] -d grant_type=authorization_code -d redirect_uri=http://localhost:8818   # copy refresh_token
```
**PRODUCES →** `chrome.env` (`CHROME_CLIENT_ID= CHROME_CLIENT_SECRET= CHROME_REFRESH_TOKEN=`); extension Item ID → repo var.

## 7 · Firefox extension — AMO
addons.mozilla.org → *Developer Hub ▸ Manage API Keys* → generate → JWT issuer + secret.
**PRODUCES →** `amo.env` (`AMO_JWT_ISSUER= AMO_JWT_SECRET=`)

## 8 · Safari extension — App Store (reuses Apple)
```bash
xcrun safari-web-extension-converter ./extension --bundle-identifier ai.hanzo.ext \
  --project-location ./SafariApp --macos-only --no-open
xcodebuild -project ./SafariApp/*.xcodeproj -scheme "MyExt" -archivePath SafariExt.xcarchive archive
```
Upload `SafariExt.xcarchive` as an artifact → `publish-safari.yml` exports + uploads. Secrets = same as iOS.

## 9 · Load secrets & set vars
```bash
ORG=hanzoai ./scripts/load-org-secrets.sh   # then luxfi, zooai
gh variable set AZURE_SIGNING_ACCOUNT --org hanzoai --body brand-signing
gh variable set AZURE_CERT_PROFILE   --org hanzoai --body hanzo-public-trust
gh variable set ANDROID_PACKAGE      --org hanzoai --body ai.hanzo.app
gh variable set LINUX_RUNNER         --org hanzoai --body hanzoai-amd64
```

## 10 · Wire an app repo & test
Copy `release.example.yml` into the app's `.github/workflows/`, then `git tag v0.0.1-test && git push --tags`.

## 11 · Verify
| Platform | Pass test |
|---|---|
| macOS | `spctl --assess -vv App.dmg` → "Notarized Developer ID" |
| iOS/Safari | build in App Store Connect ▸ TestFlight |
| Windows | `signtool verify /pa app.exe` → "Successfully verified" |
| Linux | `gpg --verify app.asc app` → "Good signature" |
| Android | `jarsigner -verify app.aab` → "jar verified" |
| Chrome | new version "Published" in dashboard |
| Firefox | signed `.xpi`; AMO listing live/pending |

## 12 · Master checklist
| Item | hanzoai | luxfi | zooai |
|---|:--:|:--:|:--:|
| Azure sub + Trusted Signing acct (shared) | ☐ | — | — |
| Azure identity validation approved | ☐ | ☐ | ☐ |
| Azure cert profile + OIDC SP | ☐ | ☐ | ☐ |
| macOS Developer ID cert | ☐ | ☐ | ☐ |
| App Store Connect API key | ☐ | ☐ | ☐ |
| iOS/Safari Distribution cert + profile | ☐ | ☐ | ☐ |
| Linux GPG key + pubkey published | ☐ | ☐ | ☐ |
| Play acct + upload keystore + service acct | ☐ | ☐ | ☐ |
| Chrome acct + OAuth refresh token | ☐ | ☐ | ☐ |
| Firefox AMO API key | ☐ | ☐ | ☐ |
| Secrets loaded (`load-org-secrets.sh`) | ☐ | ☐ | ☐ |
| Vars set + test tag green | ☐ | ☐ | ☐ |

---
Net new spend ≈ **$120/yr (Azure) + ~$80 one-time** (Play ×3 + Chrome); Apple already covered.
Credentials live only as GitHub Actions secrets/vars — never in this repo. Keep `secrets/` off git (it's `.gitignore`d).
