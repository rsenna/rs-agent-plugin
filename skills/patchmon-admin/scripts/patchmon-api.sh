#!/bin/bash
# Thin wrapper around the PatchMon REST API (username/password login -> JWT
# -> Bearer auth for everything else).
#
# Usage (credentials already in your own env):
#   PATCHMON_HOST=patchmon.example.com PATCHMON_USERNAME=... PATCHMON_PASSWORD=... \
#     ./patchmon-api.sh /api/v1/host-groups
#   ./patchmon-api.sh /api/v1/patching/trigger -X POST -H "Content-Type: application/json" \
#     -d '{"host_id":"<uuid>","patch_type":"patch_all"}'
#
# Usage (credentials sourced from Doppler at call time instead):
#   PATCHMON_HOST=patchmon.example.com DOPPLER_TOKEN=dp.st.xxx ./patchmon-api.sh /api/v1/hosts
#   # optionally override the secret names Doppler stores them under:
#   DOPPLER_USERNAME_NAME=PATCHMON_USERNAME DOPPLER_PASSWORD_NAME=PATCHMON_PASSWORD
#
# Env vars:
#   PATCHMON_HOST                          - server hostname, no scheme (required)
#   PATCHMON_USERNAME / PATCHMON_PASSWORD   - admin login used to obtain a JWT
#   DOPPLER_TOKEN                           - alternative: pull username/password from Doppler
#   DOPPLER_USERNAME_NAME / _PASSWORD_NAME  - Doppler secret names
#                                              (default PATCHMON_USERNAME/_PASSWORD)
#
# There is no long-lived admin API key for host-groups/policies/notifications -
# only a JWT from /api/v1/auth/login (short-lived, so this logs in fresh every
# call rather than caching). A separate Basic-Auth (X-API-ID/X-API-KEY) scheme
# exists for per-host agent traffic and "integration" tokens - out of scope
# here, see references/lessons-learned.md.
#
# NOTE ON DOPPLER + NESTED SHELLS: path/args are passed as real positional
# arguments to the inner `bash -c`, not string-concatenated into the quoted
# script - concatenating mangles anything containing its own quotes (e.g. a
# JSON -d payload). Same gotcha documented in opnsense-admin's
# lessons-learned.md.

set -euo pipefail

PATCHMON_HOST="${PATCHMON_HOST:?set PATCHMON_HOST}"
DOPPLER_USERNAME_NAME="${DOPPLER_USERNAME_NAME:-PATCHMON_USERNAME}"
DOPPLER_PASSWORD_NAME="${DOPPLER_PASSWORD_NAME:-PATCHMON_PASSWORD}"

path="$1"
shift

if [ -n "${DOPPLER_TOKEN:-}" ]; then
    # shellcheck disable=SC2016
    doppler run --token "$DOPPLER_TOKEN" -- bash -c '
        user="${!1}"; pass="${!2}"; path="$3"; shift 3
        jwt=$(curl -sk -m 10 -X POST "https://'"${PATCHMON_HOST}"'/api/v1/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"${user}\",\"password\":\"${pass}\"}" \
            | python3 -c "import json,sys; print(json.load(sys.stdin)[\"token\"])")
        curl -sk -m 20 -H "Authorization: Bearer ${jwt}" "https://'"${PATCHMON_HOST}"'${path}" "$@"
    ' _ "$DOPPLER_USERNAME_NAME" "$DOPPLER_PASSWORD_NAME" "$path" "$@"
else
    PATCHMON_USERNAME="${PATCHMON_USERNAME:?set PATCHMON_USERNAME or DOPPLER_TOKEN}"
    PATCHMON_PASSWORD="${PATCHMON_PASSWORD:?set PATCHMON_PASSWORD or DOPPLER_TOKEN}"
    jwt=$(curl -sk -m 10 -X POST "https://${PATCHMON_HOST}/api/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"${PATCHMON_USERNAME}\",\"password\":\"${PATCHMON_PASSWORD}\"}" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
    curl -sk -m 20 -H "Authorization: Bearer ${jwt}" "https://${PATCHMON_HOST}${path}" "$@"
fi
