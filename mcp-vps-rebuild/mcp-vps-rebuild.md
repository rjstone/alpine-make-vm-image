# Rebuilding the MCP hub on a fresh `do-droplet` image

What has to exist on a freshly booted droplet before the MCP hub
(`mcp.rjstone.net`) comes up. The hub's configuration lives in the separate
private `mcp-vps` repository, whose root maps to `/opt` on the VPS; this
directory records only the **host-side** prerequisites, which that repo does
not track.

| File | Purpose |
| --- | --- |
| `mcp-vps-rebuild.md` | This document |
| `user-data-mcp-docker.yaml` | cloud-init user data that provisions the host |

> **Status: not verified against a live rebuild.** This was written alongside
> the docker-MCP change in `mcp-vps` and describes what that stack requires. No
> droplet has been built from it end to end yet. Anything marked *assumed* was
> inferred from the compose stack, not observed on the running host.

## Base image

The `do-droplet` profile in this repository. It does **not** include Docker —
`do-droplet/packages` has no `docker` entry — so Docker arrives at first boot
via cloud-init, not in the image. If a future revision bakes it into the image
instead, add `docker-engine` and `docker-cli-compose` to `do-droplet/packages`,
enable the service in `do-droplet/configure.sh`, create the `docker` group with
GID 1000 there, and update both this file and the user data.

## Host prerequisites

`user-data-mcp-docker.yaml` in this directory does all of it. Pass it as the
droplet's user data at creation time — DigitalOcean exposes it as "User data"
in the control panel, or:

```sh
doctl compute droplet create mcp \
    --image <the do-droplet custom image id> \
    --user-data-file mcp-vps-rebuild/user-data-mcp-docker.yaml \
    --region nyc1 --size s-2vcpu-2gb --ssh-keys <fingerprint>
```

It installs `docker-engine`, `docker-cli-compose`, and `git`; enables and
starts the daemon; sets log rotation and `overlay2` in
`/etc/docker/daemon.json`; adds a 1 GiB swapfile; creates a `deploy` user in
the `docker` and `wheel` groups and copies root's authorized keys to it; and
allows passwordless `doas` for `wheel`.

### The docker group GID is a coupling, not a detail

The `mcp-docker` container in the hub's compose stack creates a group with the
host's docker GID **at image build time**, and runs its non-root user in that
group, so it can read the bind-mounted socket without running as root. Both
sides must agree on the number:

| Side | Where | Value |
| --- | --- | --- |
| Host | `bootcmd` in `user-data-mcp-docker.yaml` | `1000` |
| Container | `DOCKER_GID` build arg in the hub's `caddy/compose.yml` | `1000` |

Because the container side is a *build* arg, changing the GID means editing
both places and rebuilding the image — a restart is not enough.

The `bootcmd` exists so the host side is not left to chance: cloud-init's
`groups:` module has no way to specify a GID, so without it the group takes
whatever number happened to be free.

**Use 1000, not 999.** Alpine's `alpine-baselayout` already assigns GID 999 to
the `ping` group, in the container image as well as on the host. Building
against 999 fails outright:

```
addgroup: gid '999' in use
```

1000 is the first GID Alpine leaves free, and is what the running VPS uses.

A mismatch between two *valid* GIDs is worse, because it is not a build
failure — it surfaces as permission denied on `/var/run/docker.sock` from
inside `mcp-docker`, at run time. The last `runcmd` echoes the actual GID into
the cloud-init log; check there first:

```sh
getent group docker | cut -d: -f3   # must match DOCKER_GID
```

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

Once cloud-init has finished (`cloud-init status --wait`):

```sh
git clone <mcp-vps remote> /opt        # or restore /opt from backup
cd /opt/caddy
# .env must be in place before this point or mcp-auth-proxy will not start
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
