# OPNsense API — lessons learned

Field notes from actually driving an OPNsense 26.x box end-to-end via its REST
API: enabling CrowdSec, standing up a WireGuard server+peer, gating HAProxy
backends behind a source-IP ACL, and recovering from a box stuck mid major
upgrade. Read the relevant section before doing the analogous thing again.

## Contents
- [Finding the API in the first place](#finding-the-api-in-the-first-place)
- [Endpoint shape and discovery](#endpoint-shape-and-discovery)
- [Reading and writing multi-select fields](#reading-and-writing-multi-select-fields)
- [Save vs. apply](#save-vs-apply)
- [Sourcing credentials from Doppler](#sourcing-credentials-from-doppler)
- [Config backups are cheap insurance](#config-backups-are-cheap-insurance)
- [Settings with no API at all](#settings-with-no-api-at-all)
- [Stuck mid major-version upgrade](#stuck-mid-major-version-upgrade)
- [Worked example: CrowdSec](#worked-example-crowdsec)
- [Worked example: WireGuard server + peer](#worked-example-wireguard-server--peer)
- [Worked example: gating a HAProxy backend by source IP](#worked-example-gating-a-haproxy-backend-by-source-ip)

## Finding the API in the first place

If a plain `https://<host>/` gives a 503 or something unexpected, another
service (commonly HAProxy, if the os-haproxy plugin is installed and someone's
using OPNsense itself as a reverse proxy) may have claimed port 443. The actual
GUI/API is often still reachable on 8443 — a quick port scan
(`for p in 443 8443 4443 9443; do curl -sko /dev/null -w "$p: %{http_code}\n" https://host:$p/; done`)
finds it fast. Whatever port the GUI login page loads on is the port the API
uses too.

## Endpoint shape and discovery

Endpoints follow `/api/<module>/<controller>/<command>`, e.g.
`/api/crowdsec/general/set`, `/api/firewall/filter/searchRule`. There is no
single "list all endpoints" call. Two things make discovery fast:

1. **Pull the config backup**: `GET /api/core/backup/download/this` returns
   the live `config.xml`. Top-level `<OPNsense>` child tags map directly to
   API module names — `<OPNsense><crowdsec>` → `/api/crowdsec/...`,
   `<OPNsense><wireguard>` → `/api/wireguard/...`, `<OPNsense><HAProxy>` →
   `/api/haproxy/...`. This is the fastest way to confirm a plugin's actual
   module name instead of guessing.
2. **CRUD naming convention**: most list-backed resources expose
   `search<Item>` (paginated list), `get<Item>` / `get<Item>/<uuid>` (fetch
   one, or a *default template* with sensible blank values when called with no
   uuid — this template also reveals every valid field and, for enum fields,
   every valid choice), `add<Item>`, `set<Item>/<uuid>`, `del<Item>/<uuid>`,
   `toggle<Item>/<uuid>`. Service-level actions live under a sibling `service`
   controller: `status`, `start`, `stop`, `reconfigure`, and sometimes
   `configtest`.

Calling `get<Item>` with no uuid before writing anything is the single best
habit here — it tells you the exact field names and legal values without
reading any source code or docs.

## Reading and writing multi-select fields

Fields like `linkedAcls`, `tunneladdress`, `dns`, `peers` render in a `GET`
response as a dict keyed by value, each with a `selected` flag — that's the
form-widget representation:

```json
"linkedAcls": {
  "abc-123": {"value": "hostHeaderMatches_foo_condition", "selected": 1},
  "def-456": {"value": "srcIsTrustedAdmin_condition", "selected": 0}
}
```

Don't POST that structure back. Send a plain comma-separated string of the
keys (or values, for simple CSV-style fields) you want selected instead:
`"linkedAcls": "abc-123,def-456"`. Same applies to `tunneladdress: "10.0.0.1/24"`,
`dns: "192.168.0.1"`, etc. — plain strings in, structured dicts out.

## Save vs. apply

A `set`/`add` call persists the config but does **not** touch the running
service. You need an explicit follow-up call — `/api/<module>/service/reconfigure`
(most plugins), `/api/firewall/filter/apply` (filter rules specifically), or
occasionally `service/start`/`restart`. Verify afterward against a live signal,
not just a 200 response — e.g. for CrowdSec, check `bouncers/search` and
confirm `last_seen` is actually recent, don't just trust that `general/set`
returned `{"result":"saved"}`.

If the module has a `configtest` action (HAProxy does), call it before
`reconfigure` — cheap insurance against syntax errors landing on a live
config.

## Sourcing credentials from Doppler

If the API key/secret live in Doppler rather than your own shell env, it's
tempting to wrap a call in `doppler run -- bash -c '...'` and string-build the
inner script to include the request path and any `-d`/`-H` args. Don't -
concatenating them into the quoted script text breaks the moment any of them
contain their own quotes, which a JSON `-d` payload always does. It fails
confusingly too: `curl: option -X: requires parameter`, or worse, silently
sends a mangled/truncated request that still gets a response, just the wrong
one.

Pass the dynamic bits as real positional arguments to the inner `bash -c`
instead of interpolating them into its script text:

```bash
doppler run --token "$DOPPLER_TOKEN" -- bash -c '
  curl -s -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" "https://host:port${1}" "${@:2}"
' _ "$path" "$@"
```

(dropped the `-k` here on purpose — don't skip TLS verification by default
when sending the API key/secret over Basic auth; `scripts/opn-api.sh`'s
`OPN_INSECURE` env var is the opt-in escape hatch for a self-signed GUI cert.)

The literal `_` is a throwaway `$0` for the inner shell; `$path` becomes `$1`,
everything else in `"$@"` becomes `$2` onward. `scripts/opn-api.sh` in this
skill already does this correctly - reuse it rather than re-deriving the
pattern.

## Config backups are cheap insurance

Before any nontrivial change, pull a fresh `GET /api/core/backup/download/this`
and keep a copy off the box. This matters more than it sounds: some installs
are UFS, not ZFS, so there's no instant snapshot rollback if something goes
sideways — a saved config.xml plus a fresh install is the only fallback.

## Settings with no API at all

Some legacy pages (System > Settings > Administration, including the SSH
root-login/password-auth toggles) predate the REST-ified controllers and
simply have no `/api/` surface. Don't try to force these through a full
`config.xml` restore — that's a blunt, high-blast-radius instrument for a
one-checkbox change, and restoring an old backup can revert unrelated things
that changed since. Tell the user to flip it by hand in the GUI instead.

## Stuck mid major-version upgrade

A major upgrade (e.g. 26.1 → 26.7) interrupted partway through (including by
Ctrl-C during a `configd`-related stall) can leave the base OS/kernel already
upgraded while the package metadata/ABI tracking stays on the old version.
Once that happens, *every* path to fix it — GUI, API, and manual `pkg upgrade`
alike — fails identically with 404s on package mirrors, because the ABI+version
combination pkg is now computing was never a real released combination. It
looks like "wrong mirror" but isn't.

Don't hand-edit pkg repo config to patch around this. The supported recovery
is the console menu's firmware-update option (option 12 in recent versions),
explicitly typing the target version (e.g. `26.7`) when prompted rather than
letting it auto-detect — this re-syncs ABI and version atomically the way the
interrupted upgrade should have.

Before attempting any upgrade-related fix remotely: **confirm the user has
physical or console access as a fallback.** The API/GUI you're using to manage
the box runs *through* the box's own network stack — if a step goes wrong
mid-upgrade, you can lose access to the very channel you're using to fix it,
and so can the user if they only have network access too.

## Worked example: CrowdSec

```
POST /api/crowdsec/general/set
{"general": {"agent_enabled":"1","lapi_enabled":"1","firewall_bouncer_enabled":"1"}}

POST /api/crowdsec/service/reconfigure

GET /api/crowdsec/bouncers/search
# confirm a bouncer's "last_seen" timestamp is within the last few seconds
```

If alerts/decisions already have historical data (`/api/crowdsec/alerts/search`,
`/api/crowdsec/decisions/search`), collections may already be configured from
a previous setup — check before assuming you're starting from scratch.

## Worked example: WireGuard server + peer

There's no keypair-generation endpoint, so generate X25519 keys locally
(WireGuard keys are just raw 32-byte Curve25519 keys, base64-encoded):

```python
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives import serialization
import base64

priv = X25519PrivateKey.generate()
priv_b64 = base64.b64encode(priv.private_bytes(
    encoding=serialization.Encoding.Raw,
    format=serialization.PrivateFormat.Raw,
    encryption_algorithm=serialization.NoEncryption())).decode()
pub_b64 = base64.b64encode(priv.public_key().public_bytes(
    encoding=serialization.Encoding.Raw,
    format=serialization.PublicFormat.Raw)).decode()
```

Generate one pair for the server, one for each client peer, and a random 32
bytes the same way for an optional preshared key.

Order of operations — create the client (peer) first, then the server
referencing it, not the other way round:

```
POST /api/wireguard/client/addClient
{"client": {"enabled":"1","name":"...","pubkey":"<CLIENT_PUBKEY>",
            "psk":"<PSK>","tunneladdress":"10.10.10.2/32",
            "serveraddress":"<public-ip-or-hostname>","serverport":"51820",
            "keepalive":"25"}}
# -> returns {"uuid": "<client-uuid>"}

POST /api/wireguard/server/addServer
{"server": {"enabled":"1","name":"...","instance":"0",
            "pubkey":"<SERVER_PUBKEY>","privkey":"<SERVER_PRIVKEY>",
            "port":"51820","dns":"<lan-dns-ip>",
            "tunneladdress":"10.10.10.1/24","peers":"<client-uuid>"}}

POST /api/wireguard/general/set
{"general": {"enabled":"1"}}

POST /api/wireguard/service/reconfigure
```

Then add firewall rules: one on WAN passing the UDP listen port inbound
(`destination_net: "wanip"`), and one on the `wireguard` interface group
(`interface: "wireguard"`) allowing the tunnel subnet onward to wherever it
needs to reach. Apply with `POST /api/firewall/filter/apply`.

Hand the client its own private key + the server's public key + PSK as a
`.conf` file — treat it as a credential, not something to leave lying around.

## Worked example: gating a HAProxy backend by source IP

HAProxy's routing here is ACL-driven: a `use_backend` **action** references
one or more **ACLs** via `linkedAcls`, combined with `operator` (`and`/`or`).
To restrict an existing Host-header-routed backend to trusted networks
without touching the routing logic for everything else:

```
POST /api/haproxy/settings/addAcl
{"acl": {"name":"srcIsTrustedAdmin_condition","expression":"src",
         "src":"192.168.0.0/24 10.10.10.0/24"}}
# -> returns {"uuid": "<new-acl-uuid>"}

GET /api/haproxy/settings/getAction/<action-uuid>
# read which ACLs are currently selected under linkedAcls

POST /api/haproxy/settings/setAction/<action-uuid>
{"action": {"linkedAcls": "<existing-acl-uuid>,<new-acl-uuid>"}}
# operator defaults to "and" - both conditions now required

POST /api/haproxy/service/configtest   # validate before going live
POST /api/haproxy/service/reconfigure  # apply
```

Requests that fail the new ACL don't get an explicit block — they just don't
match any `use_backend` rule, so they fall through to HAProxy's own generic
503. That's a reasonable default-deny; no separate explicit-deny action
needed for this pattern.

Testing the negative case (blocked) from the same LAN the trusted ACL allows
is impossible by definition — verify from an actual untrusted vantage point
(e.g. a phone on cellular data) rather than assuming it worked.
