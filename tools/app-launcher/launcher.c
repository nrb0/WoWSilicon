#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

extern char **environ;

// Writes the path of Contents/Resources/launch.zsh for the application bundle containing this
// executable, which is located at Contents/MacOS/<executable>.
// Returns 0 on success, -1 when the executable path cannot be resolved or the result does not fit.
static int resolveLaunchScriptPath(char *launchScriptPath, size_t launchScriptPathCapacity) {
    char executablePath[PATH_MAX];
    uint32_t executablePathCapacity = sizeof(executablePath);
    if (_NSGetExecutablePath(executablePath, &executablePathCapacity) != 0) {
        return -1;
    }
    char resolvedExecutablePath[PATH_MAX];
    if (realpath(executablePath, resolvedExecutablePath) == NULL) {
        return -1;
    }
    int writtenLength = snprintf(
        launchScriptPath,
        launchScriptPathCapacity,
        "%s/../Resources/launch.zsh",
        dirname(resolvedExecutablePath)
    );
    return (writtenLength < 0 || (size_t)writtenLength >= launchScriptPathCapacity) ? -1 : 0;
}

int main(void) {
    char launchScriptPath[PATH_MAX];
    if (resolveLaunchScriptPath(launchScriptPath, sizeof(launchScriptPath)) != 0) {
        fprintf(stderr, "Could not locate launch.zsh inside the application bundle.\n");
        return 1;
    }

    // The shell is spawned as a child instead of replacing this process with exec. macOS Local
    // Network privacy attributes network access to the responsible process, which must remain this
    // bundle's executable for the bundle's NSLocalNetworkUsageDescription and permission to apply.
    char *shellArguments[] = {"/bin/zsh", launchScriptPath, NULL};
    pid_t shellProcessIdentifier;
    int spawnResult = posix_spawn(&shellProcessIdentifier, "/bin/zsh", NULL, NULL, shellArguments, environ);
    if (spawnResult != 0) {
        fprintf(stderr, "Could not start /bin/zsh: %s\n", strerror(spawnResult));
        return 1;
    }

    int shellStatus = 0;
    if (waitpid(shellProcessIdentifier, &shellStatus, 0) < 0) {
        return 1;
    }
    return WIFEXITED(shellStatus) ? WEXITSTATUS(shellStatus) : 1;
}
