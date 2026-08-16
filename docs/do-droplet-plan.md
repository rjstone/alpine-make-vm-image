# DigitalOcean Droplet Alpine base image

This is a coding agent plan for reproducing the main work done to build the
do-droplet directory and contents, plus the base github CI workflow. Was originally
created by Claude but edited by a human.

## Context

We want GitHub CI to build a DigitalOcean-compatible qcow2 of Alpine Linux, sized for
the $4/mo (512 MiB / 10 GiB) or $6/mo (1 GiB / 25 GiB) Droplet. This image build builds
a **lean cloud-init-ready base image** — extra things like Docker get installed on
first boot via cloud-init user-data, so the same base serves every variant.

### Requirements this is built against

From DigitalOcean's custom-image docs (fetched; saved to `docs/` as part of this work):

- qcow2 accepted; ext4 accepted; ≤100 GB uncompressed.
- **cloud-init ≥0.7.7 required**, and `ConfigDrive` **must be listed before** `NoCloud`
  in `datasource_list` or Droplets from the image "will not function properly".
- `sshd` must be installed and enabled at boot. Droplets from custom images have password
  auth disabled and require an SSH key — no control-panel root password reset.

From Alpine's `cloud-init` `README.Alpine`:

- `setup-cloud-init` is what enables the cloud-init OpenRC services. The package is
  deliberately thin on deps; the image must add what it actually uses.
- **`openssh-server-pam` (not `openssh-server`) with `UsePAM yes`** — cloud-init locks user
  passwords, and non-PAM sshd refuses key logins to password-locked accounts. This is the
  single most likely way to end up with an unloginable Droplet.
- ConfigDrive is delivered as iso9660; busybox `mount -t auto` fails to autoload the module.
  Fix with the `mount` package **and** an `/etc/filesystems` entry.
- `cc_growpart`/`cc_resizefs` need `cloud-utils-growpart`, `e2fsprogs-extra`, `parted`,
  `sgdisk` (GPT), `blockdev`, `lsblk`.
- `eudev` is recommended over mdev because it is based on udev with the systemd dependency
  removed; upstream cloud-init is only tested against udev.

### Decisions taken

- **BIOS + GPT** Droplets have historically booted SeaBIOS, so a UEFI-only image risks not
  booting at all. Confirmed: build BIOS mode with `--partition` (GPT satisfies DO's partition
  requirement).
- Also put `gcompat`, `libstdc++` in the base image, though they are optional.

## Work

### 1. `do-droplet/` profile

`cp -r example do-droplet`, then rewrite its contents. Drop `example/rootfs/usr/local/bin/hello`.
Rather than leaving `rootfs/` empty (git can't track an empty dir), reuse it for the two static
DO config files, which keeps `--fs-skel-dir` meaningful:

- `do-droplet/rootfs/etc/cloud/cloud.cfg.d/01-datasource.cfg`

  ```yaml
  datasource_list: [ ConfigDrive, DigitalOcean, None ]
  ```

  ConfigDrive first, per DO's hard requirement.
- `do-droplet/rootfs/etc/filesystems` — containing `iso9660`, for the busybox-mount issue.

`do-droplet/repositories` — drop the `@edge` pin from `example/repositories`; plain
`latest-stable` main + community (cloud-init lives in community).

`do-droplet/packages` — replacing `example/packages`:

| purpose | packages |
| --- | --- |
| cloud-init core | `cloud-init`, `eudev`, `dhclient` |
| ConfigDrive iso9660 | `mount`, `util-linux-misc` |
| growpart / resizefs | `cloud-utils-growpart`, `e2fsprogs`, `e2fsprogs-extra`, `parted`, `gptfdisk` |
| SSH (PAM variant, mandatory) | `openssh-server-pam` |
| privilege escalation | `doas`, `doas-sudo-shim` |
| glibc compat (optional) | `gcompat`, `libstdc++` |
| time / TLS / misc | `chrony`, `ca-certificates`, `tzdata`, `logrotate`, `less` |

`gcompat` + `libstdc++` go in the base so glibc-linked binaries (common in vendor-shipped
container tooling and static-ish third-party releases) run without per-variant fixups.

Carried over from `example/packages`: `chrony`, `doas`, `doas-sudo-shim`, `less`, `logrotate`.
Dropped: `ssmtp` (no MTA needed), bare `openssh` (superseded by `openssh-server-pam`).

`do-droplet/configure.sh` — keep the `step()` helper and structure from `example/configure.sh`,
change the body:

- timezone `UTC` instead of `Europe/Prague`.
- keep the existing `/etc/network/interfaces` + `net.lo`/`net.eth0` symlink block as a DHCP
  fallback; cloud-init overwrites it from ConfigDrive network metadata.
- keep the `rc.conf` `sed` block as-is.
- `setup-devd udev` (eudev, per README.Alpine).
- `setup-cloud-init` to register the cloud-init OpenRC services.
- `sshd_config`: `UsePAM yes`, `PermitRootLogin prohibit-password`, `PasswordAuthentication no`.
- services: `sshd`, `chronyd`, `crond`, `acpid`, `udev`, `net.eth0` default; `net.lo` boot.
- final cleanup so the image ships stateless: `cloud-init clean --logs`, remove
  `/etc/ssh/ssh_host_*`, truncate `/etc/machine-id`.

### 2. `.github/workflows/ci.yml`

Delete the `test-ubuntu` job entirely. Rename `test-alpine` → `build-alpine`
(`name: Build DO Droplet image`). Keep its `modprobe nbd max_part=16` step and the
`jirutka/setup-alpine@v1` v3.22 pin with its existing XXX comment. Delete the aarch64 steps
and the `setup-alpine` aarch64 re-invocation. One build step remains:

```yaml
- name: Build DigitalOcean Droplet image
  run: |
    ./alpine-make-vm-image \
        --image-format qcow2 \
        --image-size 2G \
        --partition \
        --serial-console \
        --repositories-file do-droplet/repositories \
        --packages "$(cat do-droplet/packages)" \
        --fs-skel-dir do-droplet/rootfs \
        --fs-skel-chown root:root \
        --script-chroot \
        alpine-do-$(date +%Y-%m-%d).qcow2 -- ./do-droplet/configure.sh
  shell: alpine.sh --root {0}
```

`--partition` gives GPT under BIOS boot. `--serial-console` wires ttyS0 for DO's recovery
console. 2G keeps the upload small — cloud-init `growpart` expands to the Droplet's 10/25 GiB
on first boot.

### 3. `docs/`

`mkdir docs` and save three references.

- `docs/digitalocean-custom-images-upload.md` — the DO upload/requirements page.
- `docs/alpine-cloud-init-README.Alpine.txt` — the aports README. (some outdated info here)
- `docs/do-droplet-plan.md` — this file.
- `docs/README.md` — short index naming each file, its source URL, and fetch date, plus a
  pointer to <https://cloud-init.io/> and the red-lichtie Alpine cloud-init repo. Worth a line
  in that index: red-lichtie's config uses `datasource_list: [ NoCloud, ConfigDrive ]`, which is
  the exact ordering DO says will break — it's a Proxmox reference, not a DO one.

## Verification

On push, the `build-alpine` job must go green; that alone proves the package set
resolves, `setup-cloud-init` exists and runs, and the image builds and unmounts cleanly.

Then, before trusting it, add a post-build assertion step in the same job (cheap, catches the
failure modes that CI green would otherwise hide) — remount the built image with
`--no-cleanup` semantics or `qemu-nbd`, and check:

- `/etc/cloud/cloud.cfg.d/01-datasource.cfg` exists and lists ConfigDrive first
- `/etc/init.d/cloud-init-local` is in a runlevel (i.e. `setup-cloud-init` took effect)
- `grep '^UsePAM yes' /etc/ssh/sshd_config`
- `/etc/ssh/ssh_host_*` absent, `/etc/machine-id` empty

Additional CI/CD isn't covered here. Compressing the image as `.bz2` is recommended and
a PAT generated by DO can be used to automatically upload the image to DO if desired.

End-to-end validation is manual and out of CI. Upload the qcow2 and test:

```bash
doctl compute image create alpine-do-droplet-latest --image-url <url of built image artifact> --region <region slug(s) from doctl compute region list>
doctl compute image list-user
doctl compute ssh-key list
# if needed: doctl compute ssh-key import --public-key-file <file>
# note that you may need to specify image ID rather than slug for custom images
# ssh keys probably need ID as well
doctl compute droplet create --image XXXXXXXXX --region SFO3 --size s-1vcpu-512mb-10gb --ssh-keys 39974029 --tag-name delete-me-just-testing --user-data-file user-data-docker.yaml --wait alpine-test-droplet-delete-me
```

and confirm you can `ssh root@<ip>`, that `df -h /` shows the full 10 GiB (growpart
worked), and that user-data succeeds.
