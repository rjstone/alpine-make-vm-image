#!/bin/sh
set -eu

_step_counter=0
step() {
	_step_counter=$(( _step_counter + 1 ))
	printf '\n\033[1;36m%d) %s\033[0m\n' $_step_counter "$@" >&2  # bold cyan
}

uname -a

step 'Set up timezone'
# Not setup-timezone: it shells out to "apk add tzdata", which fails inside the
# build chroot with "Unable to read database: file format is invalid or
# inconsistent". tzdata is already in the package list, so link it directly.
cp /usr/share/zoneinfo/UTC /etc/localtime
echo 'UTC' > /etc/timezone

step 'Set up networking'
# Fallback only; cloud-init rewrites this from the ConfigDrive network metadata.
cat > /etc/network/interfaces <<-EOF
	iface lo inet loopback
	iface eth0 inet dhcp
EOF
ln -s networking /etc/init.d/net.lo
ln -s networking /etc/init.d/net.eth0

step 'Adjust rc.conf'
sed -Ei \
	-e 's/^[# ](rc_depend_strict)=.*/\1=NO/' \
	-e 's/^[# ](rc_logger)=.*/\1=YES/' \
	-e 's/^[# ](unicode)=.*/\1=YES/' \
	/etc/rc.conf

step 'Enable cloud-init'
setup-cloud-init

step 'Configure sshd'
# cloud-init locks user passwords, and non-PAM sshd refuses key-based logins to
# password-locked accounts, hence openssh-server-pam + UsePAM yes.
# With UsePAM yes, PAM can still prompt for a password through
# keyboard-interactive, bypassing PasswordAuthentication no (upstream's
# sshd_config says as much), so turn KbdInteractiveAuthentication off too.
# Lynis (SSH-7408) checks neither option, so the CI image test and mcp-vps
# scripts/audit-host.sh check them instead.
sed -Ei \
	-e 's/^[# ]*(UsePAM).*/\1 yes/' \
	-e 's/^[# ]*(PermitRootLogin).*/\1 prohibit-password/' \
	-e 's/^[# ]*(PasswordAuthentication).*/\1 no/' \
	-e 's/^[# ]*(KbdInteractiveAuthentication).*/\1 no/' \
	/etc/ssh/sshd_config
# The stock file has a commented "#KbdInteractiveAuthentication yes" for the sed
# above to rewrite. If a future one does not, put the line first, where it is
# global; appended at the end it could land inside a Match block.
if ! grep -q '^KbdInteractiveAuthentication' /etc/ssh/sshd_config; then
	{ echo 'KbdInteractiveAuthentication no'; cat /etc/ssh/sshd_config; } >/etc/ssh/sshd_config.new
	mv /etc/ssh/sshd_config.new /etc/ssh/sshd_config
fi
grep -q '^UsePAM yes' /etc/ssh/sshd_config
grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config
grep -q '^KbdInteractiveAuthentication no' /etc/ssh/sshd_config

step 'Use the PAM-enabled login on the consoles'
# getty on tty1 and ttyS0 runs /bin/login. util-linux is built with
# --prefix=/usr, so its PAM login can land under /usr while /bin/login stays a
# link to busybox, whose login ignores PAM: /etc/pam.d/login (passwordless
# alpine on the console, no empty passwords) would silently never apply. Point
# /bin/login at util-linux's wherever it is; CI re-checks this on every build.
ul_login=/$(apk info -L util-linux-login | grep -xE '(usr/)?s?bin/login' | head -n 1)
[ -x "$ul_login" ]
[ "$ul_login" = /bin/login ] || ln -sf "$ul_login" /bin/login
[ "$(readlink -f /bin/login)" = "$(readlink -f "$ul_login")" ]

step "Lock root's password"
# The base image ships root with an EMPTY password field, which audit tools
# flag and any PAM stack with nullok would accept. "*" is no valid hash, so
# password logins fail. It is not "!": on Linux, non-PAM sshd treats a leading
# "!" as a locked account and refuses even key logins; sshd here uses PAM, but
# "*" keeps root's SSH keys working either way. To log in as root on the
# console, set a password from the alpine console: doas passwd root.
sed -Ei 's/^root:[^:]*:/root:*:/' /etc/shadow
grep -q '^root:\*:' /etc/shadow

step 'Enable services'
rc-update add acpid default
rc-update add chronyd default
rc-update add crond default
rc-update add do-anchor-ip default
rc-update add net.eth0 default
rc-update add sshd default
rc-update add net.lo boot
rc-update add termencoding boot
# Upstream cloud-init is only tested against udev, so use eudev rather than
# mdev.  Done by hand instead of "setup-devd udev" because that also starts
# the services, which cannot work inside the build chroot.
rc-update add udev sysinit
rc-update add udev-trigger sysinit
rc-update add udev-settle sysinit
rc-update del mdev sysinit 2>/dev/null || true
# sysinit, so /proc is private before any daemon or login starts.
rc-update add proc-hidepid sysinit

step 'Clean up instance state'
# The image must ship stateless; these are regenerated on first boot.
cloud-init clean --logs
rm -f /etc/ssh/ssh_host_*
: > /etc/machine-id
