#!/usr/bin/env bash
# Load signing secrets into a GitHub ORG's Actions secrets from local files.
# Windows (Azure Trusted Signing) uses OIDC, so only 3 non-secret IDs are stored.
#
# Layout expected (keep secrets/ OUT of git — it's .gitignore'd):
#   secrets/<org>/developer_id.p12        Apple Developer ID Application (mac)
#   secrets/<org>/p12_password.txt
#   secrets/<org>/ios_dist.p12            Apple Distribution (iOS)        [if shipping iOS]
#   secrets/<org>/ios_dist_password.txt
#   secrets/<org>/profile.mobileprovision iOS provisioning profile       [if shipping iOS]
#   secrets/<org>/AuthKey.p8              App Store Connect API key (mac+iOS)
#   secrets/<org>/asc.env                 ASC_API_KEY_ID=  ASC_API_ISSUER_ID=  APPLE_TEAM_ID=
#   secrets/<org>/azure.env               AZURE_CLIENT_ID=  AZURE_TENANT_ID=  AZURE_SUBSCRIPTION_ID=
#   secrets/<org>/gpg_private.asc         Linux GPG private key (armored)
#   secrets/<org>/gpg_passphrase.txt
#   secrets/<org>/upload.jks              Android upload keystore         [if shipping Android]
#   secrets/<org>/android.env             KEYSTORE_PASSWORD=  KEY_ALIAS=  KEY_PASSWORD=
#   secrets/<org>/play-service-account.json                              [if Play upload]
#
# Usage:  ORG=<org> ./scripts/load-org-secrets.sh
set -euo pipefail
ORG="${ORG:?set ORG=<github-org>}"
D="secrets/$ORG"
have() { [ -e "$1" ]; }
b64()  { base64 -i "$1" | tr -d '\n'; }
put()  { printf '%s' "$2" | gh secret set "$1" --org "$ORG" --visibility all && echo "  set $1"; }

echo "==> $ORG : macOS"
put MACOS_CERT_P12_BASE64 "$(b64 "$D/developer_id.p12")"
put MACOS_CERT_PASSWORD   "$(cat "$D/p12_password.txt")"
put ASC_API_KEY_P8_BASE64 "$(b64 "$D/AuthKey.p8")"
# shellcheck disable=SC1090
source "$D/asc.env"
put ASC_API_KEY_ID "$ASC_API_KEY_ID"; put ASC_API_ISSUER_ID "$ASC_API_ISSUER_ID"; put APPLE_TEAM_ID "$APPLE_TEAM_ID"

if have "$D/ios_dist.p12"; then
  echo "==> $ORG : iOS"
  put IOS_DIST_CERT_P12_BASE64        "$(b64 "$D/ios_dist.p12")"
  put IOS_DIST_CERT_PASSWORD          "$(cat "$D/ios_dist_password.txt")"
  put IOS_PROVISIONING_PROFILE_BASE64 "$(b64 "$D/profile.mobileprovision")"
fi

echo "==> $ORG : Windows (Azure Trusted Signing, OIDC)"
# shellcheck disable=SC1090
source "$D/azure.env"
put AZURE_CLIENT_ID "$AZURE_CLIENT_ID"; put AZURE_TENANT_ID "$AZURE_TENANT_ID"; put AZURE_SUBSCRIPTION_ID "$AZURE_SUBSCRIPTION_ID"

echo "==> $ORG : Linux (GPG)"
put LINUX_GPG_PRIVATE_KEY "$(b64 "$D/gpg_private.asc")"
put LINUX_GPG_PASSPHRASE  "$(cat "$D/gpg_passphrase.txt")"

if have "$D/upload.jks"; then
  echo "==> $ORG : Android"
  put ANDROID_KEYSTORE_BASE64 "$(b64 "$D/upload.jks")"
  # shellcheck disable=SC1090
  source "$D/android.env"
  put ANDROID_KEYSTORE_PASSWORD "$KEYSTORE_PASSWORD"; put ANDROID_KEY_ALIAS "$KEY_ALIAS"; put ANDROID_KEY_PASSWORD "$KEY_PASSWORD"
  have "$D/play-service-account.json" && put PLAY_SERVICE_ACCOUNT_JSON "$(cat "$D/play-service-account.json")"
fi

echo "✅ $ORG secrets loaded"
