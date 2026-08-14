# docs

Reference material for the `do-droplet` image profile. Everything here is either a
local copy of upstream documentation (so the requirements we build against are pinned
and reviewable) or a plan document.

| File | Source | Fetched |
|---|---|---|
| `digitalocean-custom-images-upload.md` | <https://docs.digitalocean.com/products/custom-images/how-to/upload/index.html.md> | 2026-08-14 (page `last_updated: 2026-07-13`) |
| `alpine-cloud-init-README.Alpine.txt` | <https://git.alpinelinux.org/aports/plain/community/cloud-init/README.Alpine> | 2026-08-14 |
| `do-droplet-plan.md` | — | implementation plan for this work |

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
