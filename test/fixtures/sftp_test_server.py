"""Minimal SFTP server for the native-engine end-to-end tests.

Serves --root over SFTP on 127.0.0.1. Prints "PORT <n>" once listening.

  --auth password   only password auth
  --auth kbd        only keyboard-interactive auth (one password prompt)
  --auth publickey  only public key auth, for the key in --authorized-key
  --throttle N      limit reads/writes to about N bytes/second per file

Also acts as a jump host (direct-tcpip forwards to any address) and offers a
tiny shell that prints "SHELL-READY <user>@<port>" and echoes what it reads.

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
        return {"password": "password", "kbd": "keyboard-interactive", "publickey": "publickey"}[ARGS.auth]

    def check_auth_publickey(self, username, key):
        if ARGS.auth != "publickey" or username != USER or not ARGS.authorized_key:
            return paramiko.AUTH_FAILED
        with open(ARGS.authorized_key) as f:
            authorized = f.read().split()[1]
        return paramiko.AUTH_SUCCESSFUL if key.get_base64() == authorized else paramiko.AUTH_FAILED

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
        if kind in ("session", "direct-tcpip"):
            return paramiko.OPEN_SUCCEEDED
        return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED_OPEN_FAILED

    def check_channel_direct_tcpip_request(self, chanid, origin, destination):
        self.forwards[chanid] = destination
        return paramiko.OPEN_SUCCEEDED

    def check_channel_pty_request(self, channel, term, width, height, pw, ph, modes):
        return True

    def check_channel_shell_request(self, channel):
        threading.Thread(target=_shell, args=(channel,), daemon=True).start()
        return True

    def __init__(self):
        self.forwards = {}


def _shell(chan):
    try:
        chan.sendall(("SHELL-READY %s@%d\r\n" % (USER, ARGS.bound_port)).encode())
        while True:
            data = chan.recv(1024)
            if not data:
                break
            chan.sendall(data)
    except Exception:
        pass
    finally:
        chan.close()


def _pipe(a_recv, b_send):
    try:
        while True:
            data = a_recv(32768)
            if not data:
                break
            b_send(data)
    except Exception:
        pass


def _forward(chan, destination):
    try:
        sock = socket.create_connection(destination, timeout=10)
    except OSError:
        chan.close()
        return
    threading.Thread(target=_pipe, args=(sock.recv, chan.sendall), daemon=True).start()
    _pipe(chan.recv, sock.sendall)
    sock.close()
    chan.close()


def serve(conn, host_key):
    t = paramiko.Transport(conn)
    t.add_server_key(host_key)
    t.set_subsystem_handler("sftp", SFTPServer, FsSftp)
    try:
        server = Server()
        t.start_server(server=server)
        while t.is_active():
            chan = t.accept(0.2)
            if chan is not None and chan.get_id() in server.forwards:
                dest = server.forwards.pop(chan.get_id())
                threading.Thread(target=_forward, args=(chan, dest), daemon=True).start()
    except Exception:
        pass
    finally:
        t.close()


def main():
    global ARGS
    p = argparse.ArgumentParser()
    p.add_argument("--root", required=True)
    p.add_argument("--port", type=int, default=0)
    p.add_argument("--auth", choices=["password", "kbd", "publickey"], default="password")
    p.add_argument("--authorized-key", help="OpenSSH .pub file accepted with --auth publickey")
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
    ARGS.bound_port = sock.getsockname()[1]
    print("PORT %d" % ARGS.bound_port, flush=True)
    while True:
        conn, _ = sock.accept()
        threading.Thread(target=serve, args=(conn, host_key), daemon=True).start()


if __name__ == "__main__":
    sys.exit(main())
