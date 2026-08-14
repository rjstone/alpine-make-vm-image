#!/bin/sh

_step_counter=0
step() {
	_step_counter=$(( _step_counter + 1 ))
	printf '\n\033[1;36m%d) %s\033[0m\n' $_step_counter "$@" >&2  # bold cyan
}

uname -a

step 'Set up timezone'
setup-timezone -z UTC

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
sed -Ei \
	-e 's/^[# ]*(UsePAM).*/\1 yes/' \
	-e 's/^[# ]*(PermitRootLogin).*/\1 prohibit-password/' \
	-e 's/^[# ]*(PasswordAuthentication).*/\1 no/' \
	/etc/ssh/sshd_config
grep -q '^UsePAM yes' /etc/ssh/sshd_config

step 'Enable services'
rc-update add acpid default
rc-update add chronyd default
rc-update add crond default
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

step 'Clean up instance state'
# The image must ship stateless; these are regenerated on first boot.
cloud-init clean --logs
rm -f /etc/ssh/ssh_host_*
: > /etc/machine-id
