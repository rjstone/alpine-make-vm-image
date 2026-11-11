/*
 * pamcheck: run one PAM service the way login or sshd would, for CI tests of
 * the image's /etc/pam.d files. Built on the CI host against linux-pam-dev and
 * run inside the image with chroot, so it uses the image's own libpam,
 * modules, pam.d files and /etc/shadow.
 *
 *   pamcheck auth SERVICE USER TTY PASSWORD   pam_authenticate + pam_acct_mgmt
 *   pamcheck acct SERVICE USER TTY            pam_acct_mgmt only (as sshd does
 *                                             after a public-key login)
 *
 * TTY "-" leaves PAM_TTY unset. Any password prompt is answered with PASSWORD
 * (auth mode) or an empty string. Exit status 0 means PAM allowed the login.
 */
#include <security/pam_appl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int conv(int n, const struct pam_message **msg,
		struct pam_response **resp, void *data)
{
	struct pam_response *r = calloc(n, sizeof(*r));
	if (!r)
		return PAM_BUF_ERR;
	for (int i = 0; i < n; i++) {
		switch (msg[i]->msg_style) {
		case PAM_PROMPT_ECHO_OFF:
		case PAM_PROMPT_ECHO_ON:
			r[i].resp = strdup(data ? (const char *)data : "");
			break;
		default:
			fprintf(stderr, "pam: %s\n", msg[i]->msg);
		}
	}
	*resp = r;
	return PAM_SUCCESS;
}

int main(int argc, char **argv)
{
	if (argc < 5 || (strcmp(argv[1], "auth") && strcmp(argv[1], "acct"))) {
		fprintf(stderr, "usage: %s auth|acct SERVICE USER TTY [PASSWORD]\n",
			argv[0]);
		return 2;
	}
	int auth = !strcmp(argv[1], "auth");
	struct pam_conv c = { conv, argc > 5 ? argv[5] : NULL };
	pam_handle_t *ph;
	int rc = pam_start(argv[2], argv[3], &c, &ph);
	if (rc == PAM_SUCCESS && strcmp(argv[4], "-"))
		rc = pam_set_item(ph, PAM_TTY, argv[4]);
	if (rc == PAM_SUCCESS && auth)
		rc = pam_authenticate(ph, 0);
	if (rc == PAM_SUCCESS)
		rc = pam_acct_mgmt(ph, 0);
	printf("%s %s user=%s tty=%s: %s\n", argv[1], argv[2], argv[3], argv[4],
	       pam_strerror(ph, rc));
	pam_end(ph, rc);
	return rc == PAM_SUCCESS ? 0 : 1;
}
