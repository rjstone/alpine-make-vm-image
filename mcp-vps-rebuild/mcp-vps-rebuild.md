# Rebuilding the MCP hub on a fresh `do-droplet` image

What has to exist on a freshly booted droplet before the MCP hub
(`mcp.rjstone.net`) comes up. The hub's configuration lives in the separate
private `mcp-vps` repository, whose root maps to `/opt` on the VPS; this file
records only the **host-side** prerequisites, which that repo does not track.

> **Status: not verified against a live rebuild.** This was written alongside
> the docker-MCP change in `mcp-vps` and describes what that stack requires. No
> droplet has been built from it end to end yet. Anything marked *assumed* was
> inferred from the compose stack, not observed on the running host.

## Base image

The `do-droplet` profile in this repository. It does **not** include Docker —
`do-droplet/packages` has no `docker` entry — so Docker is a post-boot install,
not part of the image. If a future revision moves it into the image, add
`docker` and `docker-cli-compose` to `do-droplet/packages` and enable the
service in `do-droplet/configure.sh`, and update this file.

## Host prerequisites

```sh
# Alpine; community repo must be enabled in /etc/apk/repositories
apk add docker docker-cli-compose git
rc-update add docker default
service docker start
```

The `docker` group is created by the `docker` package. Its numeric GID matters:
the `mcp-docker` container in the hub's compose stack builds a user into that
group so it can read the bind-mounted socket without running as root.

```sh
getent group docker | cut -d: -f3   # feeds DOCKER_GID in caddy/compose.yml
```

If this is not `999`, the `DOCKER_GID` build arg in the hub's `compose.yml`
must be changed to match and the image rebuilt. A mismatch shows up as
permission-denied on `/var/run/docker.sock` from inside `mcp-docker`, not as a
build failure.

## Not carried in the config repo

These live on the VPS and are excluded from `mcp-vps` by a deny-by-default
`.gitignore` (it previously leaked live OAuth tokens). They must be restored
from backup or recreated by hand:

| Path | What it is |
| --- | --- |
| `/opt/caddy/.env` | GitHub OAuth client ID/secret, allowed users |
| `/opt/caddy/mcp-auth-proxy-data/` | OAuth token datastore — plaintext tokens |
| `/opt/caddy/data/`, `/opt/caddy/config/` | Caddy ACME account keys and certs |
| `/opt/caddy/agentgateway/npm-cache/` | npm cache for the `everything` target |

Caddy's ACME state and the token store both regenerate on their own — losing
them costs a certificate re-issue and one round of client re-authentication,
not data. `/opt/caddy/.env` does not regenerate: without it the auth proxy will
not start.

## Firewall

Only 22, 80, and 443 should be reachable. Nothing in the compose stack
publishes another port to a public interface — the gateway, the auth proxy, and
`mcp-docker` are all `expose`d on the Docker network only, and the agentgateway
admin UI binds `127.0.0.1:15000`. *(Assumed, from the compose file; the UFW
rules on the live host have not been confirmed.)*

## Bringing the stack up

```sh
git clone <mcp-vps remote> /opt        # or restore /opt from backup
cd /opt/caddy
docker compose build                   # agentgateway and mcp-docker build locally
docker compose up -d
docker compose ps
```

DNS for `mcp.rjstone.net` must already point at the droplet before the first
`up`, or Caddy's ACME challenge fails and it will back off before retrying.

## Note on the Docker socket

The hub's `mcp-docker` service bind-mounts `/var/run/docker.sock`, which is
root-equivalent access to this host, and reaches the public internet through an
OAuth-gated endpoint. Read-only access is enforced by an allowlist in the
gateway's config, **not** by the `:ro` on the mount — a read-only-mounted
socket still accepts `POST /containers/create`. Full reasoning is in the
`mcp-vps` repo's `AGENTS.md`; it matters here because a rebuild that skips the
gateway config, or gets it wrong, silently exposes host mutation rather than
failing closed.
