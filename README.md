# Windows VMs imaging

An Ansible-based Incus Windows image builder.

## Features

- Downloads and verifies Windows and virtio ISOs.
- Rebuilds the unattended ISO with `Autounattend.xml`, `oem/`, and optional local payloads.
- Builds a Windows VM image in Incus and exports `disk.qcow2` plus `incus.tar.xz`.
- Optionally imports the image into Incus and launches a VM from it.
- Keeps the build flow declarative where Ansible has native modules, and uses direct commands only for `incus` and `xorriso`.

The role is intended to target the machine where Incus is running. Source assets such as `oem/`, `unattend/`, and optional local customization payloads are read on the Ansible controller. ISO paths, temporary files, output artifacts, and all Incus operations are performed on the remote Incus host.

## Supported versions

- Windows 11 Enterprise (24H2)
- Windows 10 Enterprise (20H2, 21H2, 22H2)
- Windows Server 2025
- Windows Server 2022
- Windows Server 2019
- Windows Server 2016
- Windows Server 2012
- Windows Server 2008 R2 SP1

## Requirements

- `uv`
- `incus`
- `xorriso`

`uv` manages the Python environment and installs `ansible-core` plus `pexpect`, which the playbook uses for the console automation step.

```sh
apt-get --install-recommends install xorriso

# install uv if needed
curl -LsSf https://astral.sh/uv/install.sh | sh

# install and initialize Incus if needed
curl -fsSL https://pkgs.zabbly.com/get/incus-stable | sh
incus admin init --auto
```

## Usage

Unless you change the unattended install configuration, all built systems have an administrator-level account named `admin` with password `changeme`.

Install the project dependencies:

```sh
uv sync
```

Run the playbook against the Incus host. The repository checkout only needs to exist on the Ansible controller; the role copies `oem/`, `unattend/`, and optional local payloads to the remote host as part of the build.

Build and import a Windows image:

```sh
uv run ansible-playbook -i incus-host, build.yml -e incus_windows_target=2022
```

This creates the build artifacts on the remote Incus host under `incus_windows_output_root`:

- `disk.qcow2`
- `incus.tar.xz`
- `unattended-2022.iso`

## Customizations

Add a local payload directory that should appear as `X:\local\` during setup:

```sh
mkdir -p local
printf '%s\n' 'Write-Host hello' > local/main.ps1

uv run ansible-playbook build.yml \
  -e incus_windows_target=2025 \
  -e incus_windows_local_dir="$PWD/local"
```

Use a custom Windows installer ISO or `Autounattend.xml`:

```sh
uv run ansible-playbook build.yml \
  -e incus_windows_target=10e \
  -e incus_windows_alt_iso=/srv/isos/my.iso \
  -e incus_windows_alt_autounattend="$PWD/Autounattend.xml"
```

Use a preexisting virtio ISO on the Incus host instead of downloading it:

```sh
uv run ansible-playbook build.yml \
  -e incus_windows_target=2022 \
  -e incus_windows_virtio_iso_override=/srv/isos/virtio-win.iso
```

These paths are resolved on the remote Incus host:

- `incus_windows_workspace_dir` defaults to `/opt/incus-windows`
- `incus_windows_workspace_dir`
- `incus_windows_iso_dir`
- `incus_windows_output_root`
- `incus_windows_tmp_root`
- `incus_windows_alt_iso`
- `incus_windows_virtio_iso_override`

These paths are resolved on the Ansible controller:

- `incus_windows_controller_dir`
- `incus_windows_oem_dir`
- `incus_windows_unattend_root`
- `incus_windows_alt_autounattend`
- `incus_windows_local_dir`

Useful variables:

- `incus_windows_target`
- `incus_windows_controller_dir`
- `incus_windows_workspace_dir`
- `incus_windows_alt_iso`
- `incus_windows_virtio_iso_override`
- `incus_windows_alt_autounattend`
- `incus_windows_local_dir`
- `incus_windows_import_image`
- `incus_windows_import_alias`
- `incus_windows_iso_dir`
- `incus_windows_output_dir`

## Storage

Make sure the project filesystem has enough space.

- `incus_windows_iso_dir` on the remote Incus host caches the downloaded Windows and virtio ISOs.
- `incus_windows_tmp_root` on the remote Incus host is used while repacking and exporting images.
- `incus_windows_output_root` on the remote Incus host contains the final qcow2 disk, metadata archive, and unattended ISO.

## Windows Server 2008 R2 SP1

Windows Server 2008 R2 SP1 is EOL since 2020. Compared to the newer images, automatic configuration remains limited. To get a comparable result:

- Let Windows finish installation with the provided `Autounattend.xml`.
- Run `E:\OEM\install-ps3.ps1` in PowerShell.
- After the automatic reboot, run `E:\OEM\ConfigureRemotingForAnsible.ps1`.
- Run `E:\OEM\power.ps1`.
- Run `E:\OEM\qemu-ga.ps1`.
- Run `E:\OEM\sysprep.bat E:\OEM\unattend.xml`.

## Serial console access

EMS/SAC installation remains disabled by default. To enable it, uncomment the relevant instruction in `oem/main.ps1`. On Windows 10 this requires network connectivity, and it appears to be broken on Server 2012.

```text
incus console w22
SAC> cmd
SAC> ch -si 1
Username: admin
Domain:
Password: changeme
C:\Windows\System32>
```

## Debugging

During a build you can inspect the temporary VM with:

```sh
incus list
incus console --type=vga <build-vm-name>
```

If setup fails early, the usual source of trouble is drive-letter assumptions inside `Autounattend.xml` or custom setup scripts. Use `Shift+F10` inside the installer to inspect the current device layout.

## References

- https://github.com/ruzickap/packer-templates
- https://learn.microsoft.com/en-us/troubleshoot/windows-server/windows-server-eos-faq/end-of-support-windows-server-2008-2008r2
- https://github.com/lxc/incus/commit/f14c88de78bf9f2bbe91dd661004ab772ccf179e
- https://bugs.launchpad.net/qemu/+bug/1593605
- https://www.itninja.com/blog/view/validating-unattend-xml-files-with-system-image-manager
- https://vacuumbreather.com/index.php/blog/item/62-the-case-of-just-a-moment
- https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
