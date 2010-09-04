#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

static int stack_trace_done;
static char perl_path[PATH_MAX], gdb_path[PATH_MAX];

static void
stack_trace_sigchld (int sig)
{
    PERL_UNUSED_ARG(sig);
    stack_trace_done = 1;
}

static void
stack_trace (char **args)
{
    pid_t pid;
    int in_fd[2], out_fd[2], sel, idx, state;
    fd_set fdset, readset;
    struct timeval tv;
    char c, buffer[4096];

    /* stop gdb from wrapping lines */
    snprintf(buffer, sizeof(buffer), "%u", (unsigned int)sizeof(buffer));
    setenv("COLUMNS", buffer, 1);

    stack_trace_done = 0;
    signal(SIGCHLD, stack_trace_sigchld);

    if ((pipe(in_fd) == -1) || (pipe(out_fd) == -1)) {
        perror("unable to open pipe");
        _exit(0);
    }

    pid = fork();
    if (pid == 0) {
        close(0); dup(in_fd[0]);
        close(1); dup(out_fd[1]);
        close(2); dup(out_fd[1]);

        execvp(args[0], args);
        perror("exec failed");
        _exit(0);
    }
    else if (pid == (pid_t)-1) {
        perror("unable to fork");
        _exit(0);
    }

    FD_ZERO(&fdset);
    FD_SET(out_fd[0], &fdset);

    write(in_fd[1], "backtrace\n", 10);
    write(in_fd[1], "quit\n", 5);

    idx = 0;
    state = 0;

    while (1) {
        readset = fdset;
        tv.tv_sec = 1;
        tv.tv_usec = 0;

        sel = select(FD_SETSIZE, &readset, NULL, NULL, &tv);
        if (sel == -1)
            break;

        if ((sel > 0) && (FD_ISSET(out_fd[0], &readset))) {
            if (read(out_fd[0], &c, 1)) {
                switch (state) {
                case 0:
                    if (c == '#') {
                        state = 1;
                        idx = 0;
                        buffer[idx++] = c;
                    }
                    break;
                case 1:
                    buffer[idx++] = c;
                    if ((c == '\n') || (c == '\r')) {
                        buffer[idx] = 0;
                        write(1, buffer, strlen(buffer));
                        state = 0;
                        idx = 0;
                    }
                    break;
                default:
                    break;
                }
            }
        }
        else if (stack_trace_done) {
            break;
        }
    }

    close(in_fd[0]);
    close(in_fd[1]);
    close(out_fd[0]);
    close(out_fd[1]);
    _exit(0);
}

static void
backtrace ()
{
    pid_t pid;
    char buf[16], *args[4];
    int status;

    snprintf(buf, sizeof(buf), "%u", (unsigned int)getpid());

    args[0] = gdb_path;
    args[1] = perl_path;
    args[2] = buf;
    args[3] = NULL;

    pid = fork();
    if (pid == 0) {
        stack_trace(args);
        _exit(0);
    }
    else if (pid == (pid_t)-1) {
        perror("unable to fork");
        return;
    }

    waitpid(pid, &status, 0);
}

static void
sighandler (int sig) {
    PERL_UNUSED_ARG(sig);
    backtrace();
    _exit(0);
}

static void
register_segv_handler (char *gdb, char *perl)
{
    strncpy(gdb_path, gdb, sizeof(gdb_path));
    strncpy(perl_path, perl, sizeof(perl_path));

    signal(SIGILL, sighandler);
    signal(SIGFPE, sighandler);
    signal(SIGBUS, sighandler);
    signal(SIGSEGV, sighandler);
    signal(SIGTRAP, sighandler);
    signal(SIGABRT, sighandler);
    signal(SIGQUIT, sighandler);
}

MODULE = Devel::bt  PACKAGE = Devel::bt

PROTOTYPES: DISABLE

void
register_segv_handler (gdb, perl)
        char *gdb
        char *perl
