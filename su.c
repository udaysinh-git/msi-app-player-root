/*
 * Minimal bootstrap su for a rooted (SELinux-disabled) BlueStacks Android 9 guest.
 * Drops to root (uid/gid 0, clears supplementary groups) then execs the request.
 *
 * Supported forms (leading options and any user/uid spec are accepted and ignored;
 * this su always elevates to root, which is the intent on a dev emulator):
 *   su                         -> interactive root shell
 *   su -c "cmd ..."            -> run shell command string as root
 *   su <uid|name> -c "cmd"     -> same, user spec ignored
 *   su <uid|name> prog [args]  -> exec prog directly as root (no shell)
 *   su -mm -c "cmd" / etc.     -> extra flags ignored
 *
 * Intended ONLY as a temporary/simple bootstrap; can be replaced by MagiskSU later.
 */
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <grp.h>

static const char *SH = "/system/bin/sh";

int main(int argc, char **argv) {
    /* Become root. gid/groups before uid. */
    setgroups(0, NULL);
    setgid(0);
    setuid(0);

    int i = 1;
    int had_c = 0;

    /* Skip leading options (anything starting with '-'), stopping at "-c" or "--". */
    while (i < argc && argv[i][0] == '-' && strcmp(argv[i], "-c") != 0) {
        int is_dashdash = (strcmp(argv[i], "--") == 0);
        i++;
        if (is_dashdash) break;
    }

    /* Optional single user/uid spec (a non-option token that isn't "-c"). */
    if (i < argc && argv[i][0] != '-' && strcmp(argv[i], "-c") != 0) {
        i++;
    }

    /* Optional "-c": the rest is a shell command string. */
    if (i < argc && strcmp(argv[i], "-c") == 0) {
        had_c = 1;
        i++;
    }

    if (i < argc) {
        if (had_c) {
            /* Run via shell: sh -c "cmd" [args...] */
            char **nargv = calloc((size_t)(argc - i) + 3, sizeof(char *));
            int n = 0;
            nargv[n++] = (char *)SH;
            nargv[n++] = "-c";
            for (; i < argc; i++) nargv[n++] = argv[i];
            nargv[n] = NULL;
            execv(SH, nargv);
            perror("su: execv sh -c");
            return 127;
        } else {
            /* Direct exec, preserving all args: su <uid> prog arg1 arg2 ... */
            execvp(argv[i], &argv[i]);
            perror("su: execvp");
            return 127;
        }
    }

    /* Interactive root shell. */
    execl(SH, "sh", (char *)NULL);
    perror("su: execl sh");
    return 127;
}
