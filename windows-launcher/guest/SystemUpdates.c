#include <proto/dos.h>
#include <proto/exec.h>
#include <proto/intuition.h>
#include <proto/icon.h>
#include <intuition/intuition.h>
#include <workbench/workbench.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>

#define PREF "ENVARC:AROSWizard/SystemUpdates"
#define TOOL "SYS:Prefs/SystemUpdates"
#define STAGE "SYS:AROSWizard/Update"

/* The staging manifest contains relative paths, one regular file per line. */
static int allowed(const char *path)
{
    const char *part = path;
    for (const char *p = path;; ++p) {
        if (*p == '/' || !*p) {
            size_t n = p - part;
            if (!n || p[-1] == ' ' || p[-1] == '.')
                return 0;
            if (n >= 5 && !strncasecmp(p - 5, ".info", 5))
                return 0;
            if (!*p) return 1;
            part = p + 1;
        } else if (!isalnum((unsigned char)*p) &&
                   *p != '.' && *p != '_' && *p != '-' && *p != ' ') {
            return 0;
        }
    }
}

static int copy_payload(const char *path)
{
    char source[300], destination[300], temporary[320];
    char buffer[8192];
    FILE *in, *out;
    BPTR previous_temporary;
    size_t n;
    int ok = 1;

    snprintf(source, sizeof(source), STAGE "/files/%s", path);
    snprintf(destination, sizeof(destination), "SYS:%s", path);
    snprintf(temporary, sizeof(temporary), "%s.aros-update", destination);
    previous_temporary = Lock(temporary, ACCESS_READ);
    if (previous_temporary) { UnLock(previous_temporary); return 0; }
    in = fopen(source, "rb");
    if (!in) return 0;
    out = fopen(temporary, "wb");
    if (!out) { fclose(in); return 0; }
    while ((n = fread(buffer, 1, sizeof(buffer), in)) > 0) {
        if (fwrite(buffer, 1, n, out) != n) { ok = 0; break; }
    }
    if (ferror(in)) ok = 0;
    fclose(in);
    if (fclose(out)) ok = 0;
    if (ok) {
        char backup[320];
        BPTR existing;
        snprintf(backup, sizeof(backup), "%s.aros-previous", destination);
        existing = Lock(backup, ACCESS_READ);
        if (existing) { UnLock(existing); ok = 0; }
        else if ((existing = Lock(destination, ACCESS_READ))) {
            UnLock(existing);
            if (!Rename(destination, backup)) ok = 0;
            else if (!Rename(temporary, destination)) {
                Rename(backup, destination);
                ok = 0;
            } else DeleteFile(backup);
        } else ok = Rename(temporary, destination) != 0;
    }
    if (!ok) remove(temporary);
    return ok;
}

static int run_update(void)
{
    char path[256];
    FILE *prefs = fopen(PREF, "r");
    FILE *manifest;
    int enabled, ok = 1;
    if (!prefs) return 0;
    enabled = fgetc(prefs) == '1';
    fclose(prefs);
    if (!enabled) return 0;
    manifest = fopen(STAGE "/ready.txt", "r");
    if (!manifest) return 0;
    while (fgets(path, sizeof(path), manifest)) {
        size_t n = strcspn(path, "\r\n");
        if (n == sizeof(path) - 1) { ok = 0; break; }
        path[n] = 0;
        if (!allowed(path)) continue;
        if (!copy_payload(path)) { ok = 0; break; }
    }
    if (ferror(manifest)) ok = 0;
    fclose(manifest);
    if (ok && DeleteFile(STAGE "/ready.txt")) return 0;
    fprintf(stderr, "SystemUpdates: update incomplete; staging retained.\n");
    return 20;
}

int main(int argc, char **argv)
{
    struct EasyStruct request = {
        sizeof(struct EasyStruct), 0, "AROS Systemupdates",
        "Automatische Systemupdates aus dem vorbereiteten Paket?\n"
        "Vorhandene Icons (.info) bleiben erhalten.",
        "Einschalten|Ausschalten|Abbrechen"
    };
    FILE *prefs;
    BPTR lock;
    LONG answer;
    if (argc > 1 && !strcmp(argv[1], "--apply")) return run_update();
    if (argc > 1 && !strcmp(argv[1], "--icon")) {
        struct DiskObject *icon = GetDiskObject(TOOL);
        if (icon) { FreeDiskObject(icon); return 0; }
        icon = GetDefDiskObject(WBTOOL);
        if (!icon) return 20;
        answer = PutDiskObject(TOOL, icon);
        FreeDiskObject(icon);
        return answer ? 0 : 20;
    }
    answer = EasyRequestArgs(NULL, &request, NULL, NULL);
    if (!answer) return 0;
    lock = CreateDir("ENVARC:AROSWizard");
    if (lock) UnLock(lock);
    prefs = fopen(PREF, "w");
    if (!prefs) return 20;
    answer = fputs(answer == 1 ? "1\n" : "0\n", prefs);
    return fclose(prefs) || answer < 0 ? 20 : 0;
}
