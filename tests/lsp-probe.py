# SPDX-License-Identifier: MIT
"""Starts a language server, opens one Elm file, and prints the
diagnostics the server publishes for it.

    python3 lsp-probe.py FILE -- COMMAND ARGS...

It exits with status 0 once the server publishes at least one diagnostic
for FILE, and with status 1 when none arrive within the timeout.
"""

import json
import os
import pathlib
import select
import subprocess
import sys
import time

TIMEOUT = 180


def send(proc, message):
    body = json.dumps(message).encode()
    proc.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
    proc.stdin.flush()


def receive(proc, deadline):
    headers = {}
    while True:
        if not select.select([proc.stdout], [], [], max(0, deadline - time.time()))[0]:
            return None
        line = proc.stdout.readline().decode()
        if line in ("\r\n", ""):
            break
        key, _, value = line.partition(":")
        headers[key.strip().lower()] = value.strip()
    return json.loads(proc.stdout.read(int(headers["content-length"])))


def main():
    split = sys.argv.index("--")
    path = pathlib.Path(sys.argv[1]).resolve()
    command = sys.argv[split + 1 :]
    root = pathlib.Path.cwd().as_uri()
    uri = path.as_uri()
    proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    send(proc, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                "params": {"processId": os.getpid(), "rootUri": root, "capabilities": {},
                           "workspaceFolders": [{"uri": root, "name": "project"}]}})
    deadline = time.time() + TIMEOUT
    opened = False
    while time.time() < deadline:
        message = receive(proc, deadline)
        if message is None:
            break
        if message.get("id") == 1 and not opened:
            send(proc, {"jsonrpc": "2.0", "method": "initialized", "params": {}})
            send(proc, {"jsonrpc": "2.0", "method": "textDocument/didOpen",
                        "params": {"textDocument": {"uri": uri, "languageId": "elm", "version": 1,
                                                    "text": path.read_text()}}})
            send(proc, {"jsonrpc": "2.0", "method": "textDocument/didSave",
                        "params": {"textDocument": {"uri": uri}}})
            opened = True
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
    print("no diagnostics arrived", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
