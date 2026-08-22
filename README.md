# Windows VMs imaging

An Ansible-based Incus Windows image builder.

## Features

- Downloads and verifies Windows and virtio ISOs.
- Downloads and installs the stable Cloudbase-Init installer.
- Rebuilds the unattended ISO with `Autounattend.xml`, `oem/`, and optional local payloads.
- Builds a Windows VM image directly in Incus.
- Publishes the finished image directly into Incus.
- Enables the in-box OpenSSH server and its firewall rule where Windows offers it.
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

`uv` manages the Python environment and installs `ansible-core`. The role installs `xorriso` automatically on the Incus host.

```sh
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
The playbook installs `xorriso` on the remote host, so the Ansible user needs package-management privileges there.

Build and import a Windows image:

```sh
uv run ansible-playbook -i incus-host, build.yml -e incus_windows_target=2022
```

This publishes the image directly into Incus and does not run `incus image export`, which avoids creating a large temporary image tarball on disk. The role still writes `unattended-<target>.iso` under `incus_windows_output_dir` on the remote Incus host.

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

- `incus_windows_oem_dir`
- `incus_windows_unattend_root`
- `incus_windows_alt_autounattend`
- `incus_windows_local_dir`

Useful variables:

- `incus_windows_target`
- `incus_windows_workspace_dir`
- `incus_windows_alt_iso`
- `incus_windows_virtio_iso_override`
- `incus_windows_alt_autounattend`
- `incus_windows_local_dir`
- `incus_windows_import_alias`
- `incus_windows_iso_dir`
- `incus_windows_output_dir`

## Storage

Make sure the project filesystem has enough space.

- `incus_windows_iso_dir` on the remote Incus host caches the downloaded Windows and virtio ISOs.
- `incus_windows_tmp_root` on the remote Incus host is used while repacking and building images.
- `incus_windows_output_root` on the remote Incus host contains the unattended ISO for the selected target.

## Windows 11

Windows 11 Setup requires Secure Boot and a TPM, so the `11e` build VM is created with `security.secureboot=true` and a `tpm` device (`requires_secureboot` and `requires_tpm` on the target in `vars/main.yml`). This means the remote Incus host's firmware **must** support Secure Boot: EDK2/OVMF with the Microsoft UEFI certificates enrolled, which is the case for the Zabbly packages and the stock Debian/Ubuntu/Fedora EDK2 packages. On hosts without such firmware, the `11e` build VM fails to start. The published image is not affected and can still be launched with `security.secureboot=false` like the other versions.

If your firmware does not have Microsoft's certificates enrolled, consider building inside an Incus container with KVM passthrough and a nested Incus install from [Zabbly](https://github.com/zabbly/incus).

Another option is one of the publicly-documented "bypasses" that disable the installer's checks. These can be disabled manually after attaching to the VM's VGA console, or automatically by pointing `incus_windows_alt_autounattend` at a modified unattended configuration file.

## Windows Server 2008 R2 SP1

Windows Server 2008 R2 SP1 is EOL since 2020. Compared to the newer images, automatic configuration remains limited. To get a comparable result:

- Let Windows finish installation with the provided `Autounattend.xml`.
- Run `E:\OEM\install-ps3.ps1` in PowerShell.
- After the automatic reboot, run `E:\OEM\ConfigureRemotingForAnsible.ps1`.
- Run `E:\OEM\power.ps1`.
- Run `E:\OEM\qemu-ga.ps1`.
- Run `E:\OEM\sysprep.bat E:\OEM\unattend.xml`.

## SSH access

`oem/ssh.ps1` enables the in-box OpenSSH server on every target that offers it as
a Windows capability: `10e`, `10e-20h2`, `10e-21h2`, `11e`, `2019`, `2022` and
`2025`. The capability payload lives inside the OS image, so no network access is
needed. It sets `sshd` to start automatically and opens inbound TCP 22 in the
firewall, so published images listen on port 22 from first boot.

Server 2016 and older have no OpenSSH capability, so the script logs a line and
skips itself on those targets.

Two build-time details are worth knowing:

- The stock `sshd_config` sends every administrator to
  `administrators_authorized_keys`, which Cloudbase-Init does not write. That
  `Match Group administrators` block is commented out so keys injected into the
  user's profile (`%USERPROFILE%\.ssh\authorized_keys`) are honoured. Remove that
  step from `oem/ssh.ps1` if you would rather keep the stock behaviour.
- Host keys generated during the build are deleted before sysprep, so each
  machine launched from the image generates its own.

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
