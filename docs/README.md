# docs

Reference material for the `do-droplet` image profile. Everything here is either a
local copy of upstream documentation (so the requirements we build against are pinned
and reviewable) or a plan document.

| File | Source | Fetched |
|---|---|---|
| `digitalocean-custom-images-upload.md` | <https://docs.digitalocean.com/products/custom-images/how-to/upload/index.html.md> | 2026-08-14 (page `last_updated: 2026-07-13`) |
| `alpine-cloud-init-README.Alpine.txt` | <https://git.alpinelinux.org/aports/plain/community/cloud-init/README.Alpine> | 2026-08-14 |
| `do-droplet-plan.md` | — | implementation plan for this work |
| `user-data-docker.yaml` | — | cloud-init user-data to install Docker + Compose on first boot |

## Getting the image onto DigitalOcean

Every successful build on `do-droplet-image` publishes the bzip2'd image to a rolling
prerelease tagged `image-latest`, so this URL is stable and always points at the most recent
build:

    https://github.com/rjstone/alpine-make-vm-image/releases/download/image-latest/alpine-do.qcow2.bz2

Import it with DO's control panel ("Custom Images" -> "Import via URL") or:

```sh
doctl compute image create "Alpine DO Droplet" \
    --image-url "https://github.com/rjstone/alpine-make-vm-image/releases/download/image-latest/alpine-do.qcow2.bz2" \
    --image-distribution Unknown \
    --region nyc1
```

DigitalOcean decompresses gzip and bzip2 images on import, so the `.bz2` is uploaded as-is.
The release also carries a date-stamped copy of the same file (`alpine-do-YYYY-MM-DD.qcow2.bz2`)
so a downloaded image is identifiable, but only the fixed name is a stable URL — the rolling
tag keeps no history, and each build replaces the previous image.

The same file is attached to each run as a workflow artifact, but note that artifact downloads
require an authenticated GitHub API call, so DigitalOcean cannot import from an artifact URL.

### Automatic upload to your DigitalOcean account

CI also pushes each build straight into the account, so no manual import is needed. It needs
two repository settings:

| Setting | Kind | Value |
|---|---|---|
| `DO_IMG_UPLOAD_PAT` | secret | DigitalOcean personal access token (`dop_v1_...`) |
| `DO_IMG_UPLOAD_REGION` | variable | Region slug, or a space-separated list, e.g. `nyc3 sfo3` |

If the token uses **custom scopes** rather than full access, it needs all three of
`image:create`, `image:read` and `image:delete` — read for polling the import, delete for
removing the superseded image. A token missing `image:delete` still uploads fine but leaves
old images behind, accumulating storage charges.

If the upload step fails, the HTTP status tells you which half is wrong:

- `{"id":"unauthorized"}` (401) — the token is invalid, revoked or expired.
- `{"id":"forbidden","message":"Your request is not allowed"}` (403) — the token
  authenticated but is not permitted to make that call. Check `image:create` first, but note
  that the whole request is judged, not just the endpoint: setting `tags` in the create body
  additionally requires tag scopes, so a token with full `image` scopes and no `tag` scopes
  still gets a flat 403. That is why the create body here sets no tags. Failing all that, an
  account-level restriction on custom images.

The DO API cannot replace the contents of an existing custom image (`PUT /v2/images/{id}`
only edits name, description and distribution), so "one image, always current" is implemented
as: create the new image, poll until its status reaches `available`, then delete the older
images sharing the name `alpine-do-droplet-latest`. Creating first and deleting last means a
failed import leaves the previous image usable. Import status is one of `NEW`, `available`,
`pending`, `deleted` or `retired`; anything other than `available` fails the job and prints
the API's `error_message`.

### Multiple regions

`DO_IMG_UPLOAD_REGION` accepts a space-separated list. The image is created in the **first**
region and then **transferred** to the rest with
`POST /v2/images/{id}/actions` / `{"type": "transfer", "region": "..."}`, each transfer polled
until its action reports `completed`.

It is done this way, rather than creating the image once per region, because a DigitalOcean
custom image is a single object with a `regions[]` array — one image, visible in several
places. Creating it N times would produce N distinct images that happen to share a name, and
the cleanup step (which matches on name) would then delete all but the newest. Transfers
happen only after the initial import reaches `available`, since an image cannot be transferred
before it exists.

Note that the image consumes storage in every region it lives in, so a longer list costs
proportionally more.

## Other references

- <https://cloud-init.io/> — upstream cloud-init project.
- <https://github.com/red-lichtie/alpine-cloud-init> — a worked example of cloud-init on
  Alpine. Useful for the Alpine-side mechanics, but it targets **Proxmox**, not
  DigitalOcean, and sets `datasource_list: [ NoCloud, ConfigDrive ]` — that ordering is
  precisely what DigitalOcean says will stop a Droplet from functioning. We use
  `[ ConfigDrive, DigitalOcean, None ]` instead, in
  `do-droplet/rootfs/etc/cloud/cloud.cfg.d/01-datasource.cfg`.

## The requirements that actually drive the build

From the DigitalOcean page:

- qcow2 is an accepted format; ext3/ext4 only; ≤100 GB uncompressed.
- cloud-init ≥0.7.7, with **`ConfigDrive` ahead of `NoCloud`** in `datasource_list`.
- `sshd` installed and enabled at boot. Droplets from custom images have password auth
  disabled and *require* an SSH key — there is no control-panel root password reset.

From the Alpine `cloud-init` README:

- `setup-cloud-init` is what registers the cloud-init OpenRC services.
- **`openssh-server-pam` with `UsePAM yes`**, not plain `openssh-server`: cloud-init locks
  user passwords, and non-PAM sshd then refuses key-based logins to those accounts. This is
  the easiest way to end up with a Droplet you cannot log into.
- ConfigDrive arrives as iso9660 and busybox `mount -t auto` won't autoload the module —
  hence both the `mount` package and `/etc/filesystems`.
- `growpart`/`resizefs` need `cloud-utils-growpart`, `e2fsprogs-extra`, `parted`, `gptfdisk`
  (`sgdisk`, for GPT) and `util-linux-misc` (`blockdev`, `lsblk`).
- Prefer `eudev` over mdev; upstream cloud-init is only tested against udev.
- **`bash`** is required, despite nothing in the image itself needing it. DigitalOcean's
  vendor-data writes scripts into `/var/lib/cloud/scripts/per-instance/` that are written for
  Debian/Ubuntu. Without bash, `machine_id.sh` fails to exec (`execve` returns ENOENT when the
  shebang's interpreter is missing, which reads confusingly as "No such file or directory" for
  a file that plainly exists), `runparts` raises, and cloud-init marks `modules-final` as
  FAILED — so `cloud-init status` reports an error even though every module that matters ran.

### Why the repositories file is pinned to v3.22

`do-droplet/repositories` names `v3.22` explicitly rather than `latest-stable`, and it must
stay in step with the `jirutka/setup-alpine` branch pin in `.github/workflows/ci.yml`.

`alpine-make-vm-image` installs into the image using the **host's** apk, so
`/lib/apk/db/installed` ends up in the host apk-tools' format. v3.22 ships apk-tools 2.14.10,
but `latest-stable` has moved to v3.24 with apk-tools 3.0.7 and a new, incompatible database
format. Building with one and installing the other produced an image whose own `apk` could not
read its own database — every command failed with:

    ERROR: Unable to read database: file format is invalid or inconsistent

The Droplet booted fine; only package management was broken. If you bump one pin, bump both,
and check the `host apk` / `image apk` lines that CI now prints.

### Where we deviate from the vendored README

`README.Alpine`'s datasource table tells you to install `dhclient` for the DigitalOcean-style
datasources that need an ephemeral DHCPv4 lease to reach the metadata server. That advice is
stale: ISC dhcp is EOL and **no package provides a `dhclient` binary** — `apk` fails with
`dhclient (no such package)`. We use `dhcpcd` instead, which cloud-init has supported since
23.3; the image currently resolves cloud-init 26.1 from `latest-stable`, so this is fine.

We list only `dhcpcd`, but `apk` pulls in `dhcpcd-openrc` as a dependency, so the init script
is present in the image. That is harmless because nothing adds it to a runlevel — cloud-init
invokes the binary directly for its ephemeral lease, and a running dhcpcd daemon would compete
with `/etc/network/interfaces` for `eth0`. CI asserts the service stays out of the default
runlevel.
