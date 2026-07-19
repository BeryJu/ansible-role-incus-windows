#!/usr/bin/env python3
#
# Removes the network interface(s) from an instance, if any.
#

import json
import subprocess
import sys

from urllib.parse import quote, urlencode


def getconfig(name):
    proj = subprocess.check_output(['incus', 'project', 'get-current'])
    proj = proj.decode().strip()
    args = urlencode({'project': proj, 'recursion': '1'})
    path = f'/1.0/instances/{quote(name, safe="")}?{args}'
    opts = ['incus', 'query', '--wait', path]
    return json.loads(subprocess.check_output(opts))


if len(sys.argv) != 2:
    print(f"usage: {sys.argv[0]} <instance>", file=sys.stderr)
    sys.exit(1)


inst = sys.argv[1]
conf = getconfig(inst)

insdevs = conf.get('devices') or {}
expdevs = conf.get('expanded_devices') or {}

for name, dev in expdevs.items():
    if dev.get('type') != 'nic':
        continue

    if name not in insdevs:
        # Inherited, block it
        # https://linuxcontainers.org/incus/docs/main/reference/devices_none/
        subprocess.check_call(['incus', 'config', 'device', 'add', inst, name, 'none'])
    else:
        subprocess.check_call(['incus', 'config', 'device', 'rm', inst, name])
