#!/usr/bin/env python3

import os
import pty
import select
import signal
import sys
import time


BOOT_MARKERS = (
    b"PciRoot",
    b"Booting from DVD/CD",
    b"starting Boot",
    b"Press any key to boot from CD",
)


def read_available(fd: int, timeout: float) -> bytes:
    poller = select.poll()
    poller.register(fd, select.POLLIN | select.POLLHUP | select.POLLERR)
    if not poller.poll(int(timeout * 1000)):
        return b""
    try:
        return os.read(fd, 4096)
    except OSError:
        return b""


def terminate_child(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: start_console_and_spam_enter.py INSTANCE OBSERVE_SECONDS SPAM_SECONDS", file=sys.stderr)
        return 2

    instance_name = sys.argv[1]
    observe_seconds = int(sys.argv[2])
    spam_seconds = int(sys.argv[3])

    pid, fd = pty.fork()
    if pid == 0:
        os.execlp("incus", "incus", "start", "--console", instance_name)

    matched = False
    buffer = b""
    observe_deadline = time.time() + observe_seconds

    try:
        while time.time() < observe_deadline:
            buffer += read_available(fd, 0.5)
            if any(marker in buffer for marker in BOOT_MARKERS):
                matched = True
                break

        if not matched:
            print(
                f"warning: did not observe a known firmware boot prompt for {instance_name} "
                f"within {observe_seconds} seconds; sending Enter anyway",
                file=sys.stderr,
            )

        for _ in range(spam_seconds):
            try:
                os.write(fd, b"\r\n")
            except OSError:
                break
            time.sleep(1)
    finally:
        terminate_child(pid)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
