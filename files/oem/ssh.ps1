# Enable the in-box OpenSSH server, on the images that have it as an option.
#
# The OpenSSH.Server capability ships inside the OS image from Windows 10 1809
# and Server 2019 onwards, so it installs without network access. Older targets
# (2008 R2, 2012 R2, 2016) have no such capability and are skipped: there
# Get-WindowsCapability either does not exist or reports nothing to install.

if (-not (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue)) {
    Log "OpenSSH - Get-WindowsCapability unavailable, skipping"
    return
}

$capability = Get-WindowsCapability -Online -Name OpenSSH.Server* -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $capability) {
    Log "OpenSSH - No OpenSSH.Server capability on this image, skipping"
    return
}

$name = $capability.Name

function Test-CapabilityMissing($capabilityName) {
    Get-WindowsCapability -Online -Name $capabilityName | ? state -notlike installed*
}

if (Test-CapabilityMissing $name) {
    Log "OpenSSH - Installing $name"
    $result = Add-WindowsCapability -Online -Name $name -ErrorAction SilentlyContinue

    if ($result.RestartNeeded) {
        # sysprep /generalize refuses to run with a servicing operation
        # pending, so surface this in the build log if it ever happens.
        Log "OpenSSH - WARNING: capability install requests a restart"
    }

    if (Test-CapabilityMissing $name) {
        # Same workaround as sac.ps1: the capability store can refuse the
        # request in the FirstLogon context, but accepts it as SYSTEM.
        Log "OpenSSH - Direct install failed, retrying as SYSTEM"
        $trigger = New-ScheduledTaskTrigger -At 23:59 -Once
        $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM'
        $action = New-ScheduledTaskAction -Execute "powershell" `
            -Argument "-noprofile -command `"& { Add-WindowsCapability -Online -Name $name }`""
        $task = Register-ScheduledTask -TaskPath \ -TaskName "AddOpenSSHServer" `
            -Trigger $trigger -Principal $principal -Action $action
        Start-ScheduledTask -TaskName AddOpenSSHServer

        $waited = 0
        while ((Test-CapabilityMissing $name) -and $waited -lt 900) {
            Start-Sleep -Seconds 30
            $waited += 30
        }

        $task | Unregister-ScheduledTask -Confirm:$false
    }
}

if (Test-CapabilityMissing $name) {
    Log "OpenSSH - ERROR: capability did not install, leaving SSH disabled"
    return
}

# The capability install registers the sshd and ssh-agent services, but the
# service control manager can lag a little behind Add-WindowsCapability.
$waited = 0
while (-not (Get-Service sshd -ErrorAction SilentlyContinue) -and $waited -lt 60) {
    Start-Sleep -Seconds 5
    $waited += 5
}

if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
    Log "OpenSSH - ERROR: sshd service never appeared, leaving SSH disabled"
    return
}

Log "OpenSSH - Starting sshd once to lay down its default configuration"
# The first start populates C:\ProgramData\ssh, sshd_config included.
Start-Service sshd
Start-Sleep -Seconds 5
Stop-Service sshd

$sshdConfig = "$env:ProgramData\ssh\sshd_config"
if (Test-Path $sshdConfig) {
    Log "OpenSSH - Allowing per-user authorized_keys for administrators"
    # The stock config routes every administrator to
    # administrators_authorized_keys, which Cloudbase-Init does not write to.
    # Comment the whole block out so injected keys under the user profile work.
    (Get-Content $sshdConfig) `
        -replace '^(Match Group administrators)', '#$1' `
        -replace '^(\s*AuthorizedKeysFile\s+__PROGRAMDATA__.*)$', '#$1' |
        Set-Content $sshdConfig
}

Log "OpenSSH - Removing build-time host keys so each clone generates its own"
Remove-Item "$env:ProgramData\ssh\ssh_host_*" -Force -ErrorAction SilentlyContinue

Log "OpenSSH - Enabling sshd at boot"
Set-Service -Name sshd -StartupType Automatic

$rule = Get-NetFirewallRule -Name OpenSSH-Server-In-TCP, sshd -ErrorAction SilentlyContinue |
    Select-Object -First 1

if ($rule) {
    Log "OpenSSH - Enabling firewall rule $($rule.Name)"
    $rule | Enable-NetFirewallRule
} else {
    Log "OpenSSH - Creating inbound firewall rule for TCP 22"
    New-NetFirewallRule -Name OpenSSH-Server-In-TCP -DisplayName "OpenSSH SSH Server (sshd)" `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any |
        Out-Null
}
