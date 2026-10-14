/* Small POSIX init for an experimental Darwin root filesystem. */
#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE 1
#endif
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define MAX_SERVICES 64
#define MAX_LINE 4096
#define SHUTDOWN_SECONDS 5

struct service {
    char name[64];
    char command[MAX_LINE];
    enum { ONCE, RESPAWN, CONSOLE } mode;
    pid_t pid, group;
    int started, done;
    unsigned backoff;
    double launched, retry;
};
static struct service services[MAX_SERVICES];
static size_t count;
static volatile sig_atomic_t stopping;
static int pid_one;

static double now(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        perror("xnu-init: clock_gettime");
        /* A working monotonic clock is required for restart/shutdown bounds. */
        if (pid_one) for (;;) pause();
        exit(1);
    }
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1000000000.0;
}

static void on_signal(int signo)
{
    if (signo != SIGCHLD) stopping = 1;
}

static char *trim(char *s)
{
    char *end;
    while (isspace((unsigned char)*s)) s++;
    end = s + strlen(s);
    while (end > s && isspace((unsigned char)end[-1])) *--end = '\0';
    return s;
}

/* name | once/respawn/console | command passed literally to /bin/sh -c */
static int load_config(const char *path)
{
    FILE *file = fopen(path, "r");
    char line[MAX_LINE];
    unsigned number = 0;
    if (!file) { perror(path); return -1; }
    while (fgets(line, sizeof(line), file)) {
        char *name, *mode, *command, *sep;
        struct service *s;
        number++;
        if (!strchr(line, '\n') && !feof(file)) goto invalid;
        name = trim(line);
        if (!*name || *name == '#') continue;
        if (count == MAX_SERVICES) goto invalid;
        sep = strchr(name, '|');
        if (!sep) goto invalid;
        *sep = '\0';
        mode = sep + 1;
        sep = strchr(mode, '|');
        if (!sep) goto invalid;
        *sep = '\0';
        command = trim(sep + 1);
        name = trim(name);
        mode = trim(mode);
        if (!*name || strlen(name) >= sizeof(services[0].name) || !*command)
            goto invalid;
        for (char *p = name; *p; p++)
            if (!isalnum((unsigned char)*p) && *p != '_' && *p != '-') goto invalid;
        for (size_t i = 0; i < count; i++)
            if (!strcmp(name, services[i].name)) goto invalid;
        s = &services[count];
        if (!strcmp(mode, "once")) s->mode = ONCE;
        else if (!strcmp(mode, "respawn")) s->mode = RESPAWN;
        else if (!strcmp(mode, "console")) s->mode = CONSOLE;
        else goto invalid;
        strcpy(s->name, name);
        strcpy(s->command, command);
        s->backoff = 1;
        count++;
    }
    if (ferror(file)) { perror(path); fclose(file); return -1; }
    fclose(file);
    if (!count) { fprintf(stderr, "xnu-init: empty configuration\n"); return -1; }
    return 0;
invalid:
    fprintf(stderr, "xnu-init: %s:%u: invalid service definition\n", path, number);
    fclose(file);
    return -1;
}

static int attach_console(void)
{
    int fd = open("/dev/console", O_RDWR);
    if (fd < 0) return -1;
    for (int i = 0; i < 3; i++) {
        if (dup2(fd, i) < 0) { if (fd > 2) close(fd); return -1; }
    }
    if (fd > 2) close(fd);
    return 0;
}

static void kill_group(struct service *s, int signo)
{
    if (s->group > 0) kill(-s->group, signo);
    /* Also covers a child that has not reached setsid() yet. */
    if (s->pid > 0) kill(s->pid, signo);
}

static void start_service(struct service *s)
{
    sigset_t block, previous;
    pid_t child;
    /* Prevent a child from inheriting a termination handler before exec. */
    sigemptyset(&block);
    sigaddset(&block, SIGTERM);
    sigaddset(&block, SIGINT);
    sigaddset(&block, SIGHUP);
    sigaddset(&block, SIGCHLD);
    sigprocmask(SIG_BLOCK, &block, &previous);
    child = fork();
    if (child == 0) {
        struct sigaction action;
        memset(&action, 0, sizeof(action));
        action.sa_handler = SIG_DFL;
        sigemptyset(&action.sa_mask);
        sigaction(SIGTERM, &action, NULL);
        sigaction(SIGINT, &action, NULL);
        sigaction(SIGHUP, &action, NULL);
        sigaction(SIGCHLD, &action, NULL);
        sigaction(SIGPIPE, &action, NULL);
        if (setsid() < 0) _exit(126);
        if (s->mode == CONSOLE) {
            if (attach_console() < 0) _exit(126);
#ifdef TIOCSCTTY
            if (ioctl(STDIN_FILENO, TIOCSCTTY, 0) < 0) {
                perror("xnu-init: controlling console");
                _exit(126);
            }
#endif
        } else {
            int fd = open("/dev/null", O_RDONLY);
            if (fd < 0 || dup2(fd, STDIN_FILENO) < 0) _exit(126);
            if (fd > 2) close(fd);
        }
        sigprocmask(SIG_SETMASK, &previous, NULL);
        execl("/bin/sh", "sh", "-c", s->command, (char *)NULL);
        perror("xnu-init: exec /bin/sh");
        _exit(127);
    }
    if (child < 0) {
        perror("xnu-init: fork");
        s->retry = now() + s->backoff;
    } else {
        s->pid = s->group = child;
        s->started = 1;
        s->launched = now();
        fprintf(stderr, "xnu-init: started %s pid=%ld\n", s->name, (long)child);
    }
    sigprocmask(SIG_SETMASK, &previous, NULL);
}

static int reap(void)
{
    int status, failed = 0;
    pid_t child;
    while ((child = waitpid(-1, &status, WNOHANG)) > 0) {
        for (size_t i = 0; i < count; i++) {
            struct service *s = &services[i];
            if (s->pid != child) continue;
            s->pid = 0;
            fprintf(stderr, "xnu-init: exited %s status=%d signal=%d\n", s->name,
                WIFEXITED(status) ? WEXITSTATUS(status) : -1,
                WIFSIGNALED(status) ? WTERMSIG(status) : 0);
            /* Services must stay in the foreground. Remove leftover descendants. */
            kill_group(s, SIGKILL);
            s->group = 0;
            if (s->mode == ONCE) {
                s->done = 1;
                if (!stopping && (!WIFEXITED(status) || WEXITSTATUS(status))) failed = 1;
            } else {
                if (now() - s->launched >= 30) s->backoff = 1;
                s->retry = now() + s->backoff;
                fprintf(stderr, "xnu-init: retry %s in %u seconds\n", s->name, s->backoff);
                if (s->backoff < 30) s->backoff = s->backoff > 15 ? 30 : s->backoff * 2;
            }
            break;
        }
        /* waitpid(-1) also reaps untracked orphans adopted by PID 1. */
    }
    return failed;
}

static void tick(void)
{
    struct timespec delay = {0, 100000000};
    nanosleep(&delay, NULL);
}

static void shutdown_services(void)
{
    double deadline = now() + SHUTDOWN_SECONDS;
    fprintf(stderr, "xnu-init: stopping services\n");
    for (size_t i = count; i > 0; i--) kill_group(&services[i - 1], SIGTERM);
    /* Keep groups until the deadline, including descendants ignoring TERM. */
    while (now() < deadline) tick();
    for (size_t i = count; i > 0; i--) kill_group(&services[i - 1], SIGKILL);
    deadline = now() + 2;
    for (;;) {
        int status;
        pid_t child = waitpid(-1, &status, WNOHANG);
        if (child > 0) continue;
        if ((child < 0 && errno == ECHILD) || now() >= deadline) break;
        tick();
    }
    if (pid_one) sync();
}

static int supervise(void)
{
    int result = 0;
    while (!stopping) {
        if (reap()) { result = 1; break; }
        for (size_t i = 0; i < count && !stopping; i++) {
            struct service *s = &services[i];
            if (!s->pid && !s->done && now() >= s->retry) start_service(s);
            /* A once job is a barrier: later services wait for its success. */
            if (s->mode == ONCE && !s->done) break;
        }
        tick();
    }
    stopping = 1;
    shutdown_services();
    return result;
}

int main(int argc, char **argv)
{
    const char *config = "/etc/xnu-init/services.conf";
    int check = 0, user = 0, single = 0, result = 1;
    struct sigaction action;
    pid_one = getpid() == 1;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--check")) check = 1;
        else if (!strcmp(argv[i], "--user")) user = 1;
        else if (!strcmp(argv[i], "-s")) single = 1;
        else if (!strcmp(argv[i], "--config") && i + 1 < argc) config = argv[++i];
        else {
            fprintf(stderr, "usage: xnu-init [--check] [--user] [-s] [--config path]\n");
            goto finished;
        }
    }
    if (!check && !pid_one && !user) {
        fprintf(stderr, "xnu-init: requires PID 1; use --user for a development supervisor\n");
        goto finished;
    }
    if (pid_one) {
        umask(022);
        if (chdir("/") != 0 || attach_console() != 0) {
            perror("xnu-init: initialize console");
            goto finished;
        }
        if (setenv("PATH", "/sbin:/bin:/usr/sbin:/usr/bin", 1) != 0 ||
            setenv("HOME", "/", 1) != 0 || setenv("TERM", "vt100", 0) != 0)
            goto finished;
    }
    if (single && !check) {
        strcpy(services[0].name, "single-user");
        strcpy(services[0].command, "exec /bin/sh -i");
        services[0].mode = CONSOLE;
        services[0].backoff = 1;
        count = 1;
    } else if (load_config(config) < 0) goto finished;
    if (check) { printf("xnu-init: valid configuration (%zu services)\n", count); result = 0; goto finished; }
    memset(&action, 0, sizeof(action));
    action.sa_handler = on_signal;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGTERM, &action, NULL) < 0 || sigaction(SIGINT, &action, NULL) < 0 ||
        sigaction(SIGHUP, &action, NULL) < 0 || sigaction(SIGCHLD, &action, NULL) < 0) {
        perror("xnu-init: sigaction");
        goto finished;
    }
    action.sa_handler = SIG_IGN;
    sigaction(SIGPIPE, &action, NULL);
    result = supervise();
finished:
    if (pid_one) {
        fprintf(stderr, "xnu-init: stopped; PID 1 remains alive (result=%d)\n", result);
        for (;;) {
            int status;
            while (waitpid(-1, &status, WNOHANG) > 0) {}
            tick();
        }
    }
    return result;
}
