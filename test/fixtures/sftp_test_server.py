"""Minimal SFTP server for the native-engine end-to-end tests.

Serves --root over SFTP on 127.0.0.1. Prints "PORT <n>" once listening.

  --auth password   only password auth
  --auth kbd        only keyboard-interactive auth (one password prompt)
  --throttle N      limit reads/writes to about N bytes/second per file

Requires paramiko. Test-only: accepts one fixed user/password.
"""
import argparse
import base64
import hashlib
import os
import socket
import sys
import threading
import time

import paramiko
from paramiko import SFTPAttributes, SFTPHandle, SFTPServer, SFTPServerInterface
from paramiko.sftp import SFTP_OK

USER = "tester"
PASSWORD = "secret"

ARGS = None


def _real(path):
    root = os.path.abspath(ARGS.root)
    rel = os.path.normpath("/" + path).lstrip("/\\")
    return os.path.join(root, rel)


class ThrottledHandle(SFTPHandle):
    def _throttle(self, n):
        if ARGS.throttle > 0:
            time.sleep(n / ARGS.throttle)

    def read(self, offset, length):
        data = super().read(offset, length)
        if isinstance(data, bytes):
            self._throttle(len(data))
        return data

    def write(self, offset, data):
        self._throttle(len(data))
        return super().write(offset, data)

    def stat(self):
        f = self.readfile or self.writefile
        return SFTPAttributes.from_stat(os.fstat(f.fileno()))

    def chattr(self, attr):
        return SFTP_OK


class FsSftp(SFTPServerInterface):
    def canonicalize(self, path):
        return os.path.normpath("/" + path).replace("\\", "/")

    def list_folder(self, path):
        real = _real(path)
        out = []
        for name in os.listdir(real):
            attr = SFTPAttributes.from_stat(os.stat(os.path.join(real, name)))
            attr.filename = name
            out.append(attr)
        return out

    def stat(self, path):
        try:
            return SFTPAttributes.from_stat(os.stat(_real(path)))
        except OSError as e:
            return SFTPServer.convert_errno(e.errno)

    lstat = stat

    def open(self, path, flags, attr):
        real = _real(path)
        try:
            fd = os.open(real, flags | getattr(os, "O_BINARY", 0), 0o644)
        except OSError as e:
            return SFTPServer.convert_errno(e.errno)
        if flags & os.O_WRONLY:
            mode = "ab" if flags & os.O_APPEND else "wb"
        elif flags & os.O_RDWR:
            mode = "a+b" if flags & os.O_APPEND else "r+b"
        else:
            mode = "rb"
        f = os.fdopen(fd, mode)
        h = ThrottledHandle(flags)
        h.filename = real
        h.readfile = f
        h.writefile = f
        return h

    def remove(self, path):
        try:
            os.remove(_real(path))
        except OSError as e:
            return SFTPServer.convert_errno(e.errno)
        return SFTP_OK

    def mkdir(self, path, attr):
        try:
            os.mkdir(_real(path))
        except OSError as e:
            return SFTPServer.convert_errno(e.errno)
        return SFTP_OK


class Server(paramiko.ServerInterface):
    def get_allowed_auths(self, username):
        return "password" if ARGS.auth == "password" else "keyboard-interactive"

    def check_auth_password(self, username, password):
        if ARGS.auth == "password" and username == USER and password == PASSWORD:
            return paramiko.AUTH_SUCCESSFUL
        return paramiko.AUTH_FAILED

    def check_auth_interactive(self, username, submethods):
        if ARGS.auth != "kbd" or username != USER:
            return paramiko.AUTH_FAILED
        q = paramiko.InteractiveQuery("", "")
        q.add_prompt("Password: ", False)
        return q

    def check_auth_interactive_response(self, responses):
        return paramiko.AUTH_SUCCESSFUL if list(responses) == [PASSWORD] else paramiko.AUTH_FAILED

    def check_channel_request(self, kind, chanid):
        if kind == "session":
            return paramiko.OPEN_SUCCEEDED
        return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED_OPEN_FAILED


def serve(conn, host_key):
    t = paramiko.Transport(conn)
    t.add_server_key(host_key)
    t.set_subsystem_handler("sftp", SFTPServer, FsSftp)
    try:
        t.start_server(server=Server())
        while t.is_active():
            time.sleep(0.2)
    except Exception:
        pass
    finally:
        t.close()


def main():
    global ARGS
    p = argparse.ArgumentParser()
    p.add_argument("--root", required=True)
    p.add_argument("--port", type=int, default=0)
    p.add_argument("--auth", choices=["password", "kbd"], default="password")
    p.add_argument("--throttle", type=int, default=0)
    ARGS = p.parse_args()

    host_key = paramiko.RSAKey.generate(2048)
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", ARGS.port))
    sock.listen(16)
    # OpenSSH-style fingerprint, so tests can trust exactly this key.
    digest = hashlib.sha256(host_key.asbytes()).digest()
    print("FP SHA256:%s" % base64.b64encode(digest).decode().rstrip("="), flush=True)
    print("PORT %d" % sock.getsockname()[1], flush=True)
    while True:
        conn, _ = sock.accept()
        threading.Thread(target=serve, args=(conn, host_key), daemon=True).start()


if __name__ == "__main__":
    sys.exit(main())
