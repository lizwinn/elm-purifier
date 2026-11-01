# SPDX-License-Identifier: MIT
"""Starts a language server, opens one Elm file, and prints the
diagnostics the server publishes for it.

    python3 lsp-probe.py FILE -- COMMAND ARGS...

It exits with status 0 once the server publishes at least one diagnostic
for FILE, and with status 1 when none arrive within the timeout. The
server may still be reading the project when it gets the first save, and
then publishes nothing for it, so the probe saves the file again every
RESAVE seconds. On failure it prints the messages it received and the
standard error of the server.
"""

import json
import os
import pathlib
import select
import subprocess
import sys
import tempfile
import time

# A slow runner, such as an ARM machine under load, can take minutes to
# start the server and compile the project.
TIMEOUT = 600
RESAVE = 20


def send(proc, message):
    body = json.dumps(message).encode()
    proc.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
    proc.stdin.flush()


def receive(proc, until):
    """The next message, or None when none arrives before `until`. Raises
    EOFError when the server closed its output."""
    headers = {}
    while True:
        if not select.select([proc.stdout], [], [], max(0, until - time.time()))[0]:
            return None
        line = proc.stdout.readline().decode()
        if line == "":
            raise EOFError
        if line == "\r\n":
            break
        key, _, value = line.partition(":")
        headers[key.strip().lower()] = value.strip()
    return json.loads(proc.stdout.read(int(headers["content-length"])))


def save(proc, uri):
    send(proc, {"jsonrpc": "2.0", "method": "textDocument/didSave",
                "params": {"textDocument": {"uri": uri}}})


def main():
    split = sys.argv.index("--")
    path = pathlib.Path(sys.argv[1]).resolve()
    command = sys.argv[split + 1 :]
    root = pathlib.Path.cwd().as_uri()
    uri = path.as_uri()
    stderr = tempfile.TemporaryFile()
    proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr)
    send(proc, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                "params": {"processId": os.getpid(), "rootUri": root, "capabilities": {},
                           "workspaceFolders": [{"uri": root, "name": "project"}]}})
    started = time.time()
    deadline = started + TIMEOUT
    next_save = None
    received = []
    reason = "no diagnostics arrived"
    while time.time() < deadline:
        try:
            message = receive(proc, min(deadline, next_save or deadline))
        except EOFError:
            reason = f"the server exited with status {proc.wait()}"
            break
        if message is None:
            if next_save is not None and time.time() >= next_save:
                save(proc, uri)
                next_save = time.time() + RESAVE
            continue
        received.append(message.get("method") or f"response {message.get('id')}")
        if message.get("id") == 1 and next_save is None:
            send(proc, {"jsonrpc": "2.0", "method": "initialized", "params": {}})
            send(proc, {"jsonrpc": "2.0", "method": "textDocument/didOpen",
                        "params": {"textDocument": {"uri": uri, "languageId": "elm", "version": 1,
                                                    "text": path.read_text()}}})
            save(proc, uri)
            next_save = time.time() + RESAVE
        elif message.get("method") == "textDocument/publishDiagnostics":
            params = message["params"]
            if params["uri"] == uri and params["diagnostics"]:
                for diagnostic in params["diagnostics"]:
                    print(diagnostic["message"].splitlines()[0])
                proc.kill()
                return 0
        elif "id" in message and "method" in message:
            # A request from the server, such as workspace/configuration.
            send(proc, {"jsonrpc": "2.0", "id": message["id"], "result": [{}] * 8})
    proc.kill()
    print(f"{reason} after {time.time() - started:.0f} seconds", file=sys.stderr)
    print(f"messages received: {received}", file=sys.stderr)
    stderr.seek(0)
    print("standard error of the server:", file=sys.stderr)
    print(stderr.read().decode(errors="replace"), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
