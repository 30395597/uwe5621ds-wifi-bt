#!/usr/bin/env python3
"""Run a command on the box over SSH (helper used while developing this repo).

No host, user or password is stored in this file. All come from the environment.

Usage:
  BOXHOST=192.168.x.x BOXUSER=root BOXPW=xxxx python remote-run.py 'uname -r'
  BOXHOST=... BOXUSER=... BOXPW=... python remote-run.py --put local remote
  BOXHOST=... BOXUSER=... BOXPW=... python remote-run.py --get remote local
"""
import os
import sys

try:
    import paramiko
except ImportError:
    sys.exit("pip install paramiko")

HOST = os.environ.get("BOXHOST")
USER = os.environ.get("BOXUSER", "root")
PW = os.environ.get("BOXPW")
TIMEOUT = int(os.environ.get("BOXTIMEOUT", "180"))

if not HOST or not PW:
    sys.exit("BOXHOST and BOXPW environment variables are required")


def connect():
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username=USER, password=PW, timeout=15,
              look_for_keys=False, allow_agent=False,
              banner_timeout=30, auth_timeout=30)
    return c


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    c = connect()
    try:
        if a[0] == "--put" and len(a) == 3:
            sftp = c.open_sftp()
            sftp.put(a[1], a[2])
            sftp.close()
            print("uploaded ->", a[2])
            return 0
        if a[0] == "--get" and len(a) == 3:
            sftp = c.open_sftp()
            sftp.get(a[1], a[2])
            sftp.close()
            print("downloaded ->", a[2])
            return 0
        _, out, err = c.exec_command(" ".join(a) if len(a) > 1 else a[0],
                                     timeout=TIMEOUT)
        sys.stdout.write(out.read().decode("utf-8", "replace"))
        e = err.read().decode("utf-8", "replace")
        if e.strip():
            sys.stdout.write("\n----- STDERR -----\n" + e)
        rc = out.channel.recv_exit_status()
        sys.stdout.write("\n----- RC:%d -----\n" % rc)
        return rc
    finally:
        c.close()


if __name__ == "__main__":
    sys.exit(main())
