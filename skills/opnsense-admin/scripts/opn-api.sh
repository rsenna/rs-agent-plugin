#!/bin/bash
# Thin wrapper around OPNsense's REST API.
#
# Usage (credentials already in your own env):
#   OPN_HOST=192.168.0.1 OPN_PORT=8443 OPN_KEY=... OPN_SECRET=... \
#     ./opn-api.sh /api/core/firmware/status
#   ./opn-api.sh /api/crowdsec/general/set -X POST -H "Content-Type: application/json" -d '{"general":{"agent_enabled":"1"}}'
#
# Usage (credentials sourced from Doppler at call time instead):
#   OPN_HOST=192.168.0.1 OPN_PORT=8443 DOPPLER_TOKEN=dp.st.xxx \
#     ./opn-api.sh /api/core/firmware/status
#   # optionally override the secret names Doppler stores them under:
#   DOPPLER_KEY_NAME=OPNSENSE_API_KEY DOPPLER_SECRET_NAME=OPNSENSE_API_SECRET
#
# Env vars:
#   OPN_HOST     - firewall hostname/IP (required)
#   OPN_PORT     - API port (default 443; use 8443 or whatever the GUI
#                  actually listens on if something else - HAProxy, Caddy,
#                  etc. - owns 443)
#   OPN_KEY / OPN_SECRET       - API key/secret directly (System > Access >
#                                Users > <user> > API keys > +)
#   DOPPLER_TOKEN              - alternative to OPN_KEY/OPN_SECRET: a Doppler
#                                service token to pull them from instead
#   DOPPLER_KEY_NAME/_SECRET_NAME - Doppler secret names to read
#                                    (default OPNSENSE_API_KEY/_SECRET)
#
# The API key/secret pair authenticates via HTTP Basic Auth. Scope the user
# down to the minimum privileges the task needs - this is a live firewall.
#
# NOTE ON DOPPLER + NESTED SHELLS: if you're tempted to wrap a call like this
# in your own `doppler run -- bash -c '...'`, don't string-concatenate the
# path/args INTO the quoted script text - it silently mangles anything
# containing its own quotes (e.g. a JSON -d payload). Pass them as real
# positional arguments to the inner `bash -c` instead (`bash -c 'script' _
# "$path" "$@"`), same as this script does below. Learned this the hard way -
# see references/lessons-learned.md.

set -euo pipefail

OPN_HOST="${OPN_HOST:?set OPN_HOST}"
OPN_PORT="${OPN_PORT:-443}"
DOPPLER_KEY_NAME="${DOPPLER_KEY_NAME:-OPNSENSE_API_KEY}"
DOPPLER_SECRET_NAME="${DOPPLER_SECRET_NAME:-OPNSENSE_API_SECRET}"

path="$1"
shift

if [ -n "${DOPPLER_TOKEN:-}" ]; then
    # shellcheck disable=SC2016
    doppler run --token "$DOPPLER_TOKEN" -- bash -c '
        key="${!1}"; secret="${!2}"
        curl -sk -m 20 -u "${key}:${secret}" "https://'"${OPN_HOST}"':'"${OPN_PORT}"'${3}" "${@:4}"
    ' _ "$DOPPLER_KEY_NAME" "$DOPPLER_SECRET_NAME" "$path" "$@"
else
    OPN_KEY="${OPN_KEY:?set OPN_KEY or DOPPLER_TOKEN}"
    OPN_SECRET="${OPN_SECRET:?set OPN_SECRET or DOPPLER_TOKEN}"
    curl -sk -m 20 -u "${OPN_KEY}:${OPN_SECRET}" "https://${OPN_HOST}:${OPN_PORT}${path}" "$@"
fi
