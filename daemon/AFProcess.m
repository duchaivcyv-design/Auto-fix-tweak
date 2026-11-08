#import "daemon/AFProcess.h"

#import <sys/sysctl.h>
#import <sys/proc.h>
#import <string.h>
#import <stdlib.h>
#import <strings.h>
#import <signal.h>
#import <unistd.h>

pid_t AFSpringBoardPID(void) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0 || size == 0) return 0;

    struct kinfo_proc *processes = malloc(size);
    if (!processes) return 0;

    if (sysctl(mib, 4, processes, &size, NULL, 0) != 0) {
        free(processes);
        return 0;
    }

    size_t count = size / sizeof(struct kinfo_proc);
    pid_t springBoardPID = 0;
    for (size_t i = 0; i < count; i++) {
        struct kinfo_proc *process = &processes[i];
        const char *name = process->kp_proc.p_comm;
        if (name && strncmp(name, "SpringBoard", 11) == 0) {
            springBoardPID = process->kp_proc.p_pid;
            break;
        }
    }

    free(processes);
    return springBoardPID;
}

static struct kinfo_proc *AFAllProcesses(size_t *outCount) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0 || size == 0) return NULL;
    struct kinfo_proc *processes = malloc(size);
    if (!processes) return NULL;
    if (sysctl(mib, 4, processes, &size, NULL, 0) != 0) {
        free(processes);
        return NULL;
    }
    *outCount = size / sizeof(struct kinfo_proc);
    return processes;
}

pid_t AFPIDForProcessNamed(NSString *name) {
    if (name.length == 0) return 0;
    size_t count = 0;
    struct kinfo_proc *processes = AFAllProcesses(&count);
    if (!processes) return 0;

    pid_t found = 0;
    const char *target = name.UTF8String;
    for (size_t i = 0; i < count; i++) {
        const char *comm = processes[i].kp_proc.p_comm;
        if (!comm || strcasecmp(comm, target) != 0) continue;
        pid_t pid = processes[i].kp_proc.p_pid;
        if (pid > 0 && pid != getpid()) { found = pid; break; }
    }
    free(processes);
    return found;
}

NSUInteger AFKillProcessNamed(NSString *name) {
    if (name.length == 0) return 0;
    size_t count = 0;
    struct kinfo_proc *processes = AFAllProcesses(&count);
    if (!processes) return 0;

    NSUInteger killed = 0;
    const char *target = name.UTF8String;
    for (size_t i = 0; i < count; i++) {
        const char *comm = processes[i].kp_proc.p_comm;
        if (!comm || strcasecmp(comm, target) != 0) continue;
        pid_t pid = processes[i].kp_proc.p_pid;
        if (pid <= 0 || pid == getpid()) continue;
        if (kill(pid, SIGKILL) == 0) killed++;
    }
    free(processes);
    return killed;
}
