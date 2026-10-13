#!/bin/sh
# Runs OpenTofu in this directory with the Cloudflare API token, account ID and R2 state key
# from 1Password (see README), e.g. `./tofu.sh plan`. Nothing lands on disk or in shell history.
# The variables have the same names as the homelab repo's GitHub Actions secrets.
# On WSL, the Windows op.exe talks to the 1Password app (Windows Hello); a Linux op can't.
set -eu

vault="${HOMELAB_OP_VAULT:-Homelab}"
op=op
if command -v op.exe >/dev/null 2>&1; then
  op=op.exe
fi

# One op call for all values, so 1Password asks at most once.
env="$("$op" inject <<TEMPLATE
CLOUDFLARE_API_TOKEN={{ op://$vault/homelab-cloudflare-terraform/credential }}
CLOUDFLARE_ACCOUNT_ID={{ op://$vault/homelab-cloudflare-terraform/account_id }}
AWS_ACCESS_KEY_ID={{ op://$vault/homelab-tfstate-r2/username }}
AWS_SECRET_ACCESS_KEY={{ op://$vault/homelab-tfstate-r2/password }}
TEMPLATE
)"
env="$(printf '%s\n' "$env" | tr -d '\r')" # op.exe ends lines with CRLF

while IFS='=' read -r name value; do
  export "$name=$value"
done <<VARS
$env
VARS

# The S3 backend's R2 endpoint.
export AWS_ENDPOINT_URL_S3="https://$CLOUDFLARE_ACCOUNT_ID.r2.cloudflarestorage.com"

cd "$(dirname "$0")"
exec tofu "$@"
