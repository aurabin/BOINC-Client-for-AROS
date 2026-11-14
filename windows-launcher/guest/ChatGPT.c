#include <exec/libraries.h>
#include <dos/dos.h>
#include <proto/dos.h>
#include <proto/exec.h>
#include <proto/bsdsocket.h>
#include <netinet/in.h>
#include <string.h>

struct Library *SocketBase;

static void print(BPTR console, const char *text)
{
    Write(console, (APTR)text, strlen(text));
}

static int send_all(int fd, const char *data, int count)
{
    while (count > 0) {
        int sent = send(fd, data, count, 0);
        if (sent <= 0) return 0;
        data += sent;
        count -= sent;
    }
    return 1;
}

static int read_answer(BPTR console, int fd)
{
    char buffer[512];
    char digit;
    unsigned long size = 0;
    unsigned int digits = 0;

    for (;;) {
        if (recv(fd, &digit, 1, 0) != 1) return 0;
        if (digit == '\n') break;
        if (digit < '0' || digit > '9' || ++digits > 5) return 0;
        size = size * 10 + (digit - '0');
    }
    if (digits == 0 || size > 32000) return 0;

    print(console, "\nChatGPT:\n");
    while (size > 0) {
        int wanted = size < sizeof(buffer) ? (int)size : (int)sizeof(buffer);
        int received = recv(fd, buffer, wanted, 0);
        if (received <= 0) return 0;
        Write(console, buffer, received);
        size -= received;
    }
    print(console, "\n\n");
    return 1;
}

int main(void)
{
    BPTR console = Open("CON:20/30/620/340/ChatGPT for AROS/AUTO/CLOSE/WAIT",
                       MODE_NEWFILE);
    struct sockaddr_in address;
    char prompt[1024];
    int fd = -1;
    int result = RETURN_FAIL;

    if (!console) return RETURN_FAIL;
    print(console, "ChatGPT for AROS\nVerbinde mit AROS Wizard auf Windows ...\n");
    SocketBase = OpenLibrary("bsdsocket.library", 0);
    if (!SocketBase) {
        print(console, "Starte zuerst das AROS-Netzwerk (RTL8139, DHCP).\n");
        goto done;
    }

    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(16811);
    address.sin_addr.s_addr = htonl(0x0a000264UL);
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0 || connect(fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        print(console, "Keine Verbindung. Starte AROS mit der ChatGPT-Option.\n");
        goto done;
    }

    print(console, "/reset beginnt einen neuen Chat. /quit beendet das Programm.\n\n");
    for (;;) {
        LONG count;
        print(console, "Du> ");
        count = Read(console, prompt, sizeof(prompt) - 1);
        if (count <= 0) break;
        while (count && (prompt[count - 1] == '\n' || prompt[count - 1] == '\r')) --count;
        for (LONG i = 0; i < count; ++i) {
            if (prompt[i] == '\n' || prompt[i] == '\r') prompt[i] = ' ';
        }
        prompt[count] = '\0';
        if (strcmp(prompt, "/quit") == 0) break;
        if (strspn(prompt, " \t") == (size_t)count) continue;
        print(console, "Warte auf Antwort ...\n");
        if (!send_all(fd, prompt, (int)count) || !send_all(fd, "\n", 1) ||
            !read_answer(console, fd)) {
            print(console, "Verbindung unterbrochen. Starte die AROS-VM neu.\n");
            goto done;
        }
    }
    result = RETURN_OK;

done:
    if (fd >= 0) CloseSocket(fd);
    if (SocketBase) CloseLibrary(SocketBase);
    Close(console);
    return result;
}
