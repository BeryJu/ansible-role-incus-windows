Function Log {
    $Message = $args[0]
    Write-Output $Message
}

get-wmiobject win32_logicaldisk | % {
	if ($_.volumename -like 'STUFF*') {
		$setupdrive = $_.deviceid
	}
}

Log ".net - Compile .net assemblies"
$ngen32 = "$env:windir\microsoft.net\framework\v4.0.30319\ngen.exe"

& $ngen32 update /force /queue | Out-Null
& $ngen32 executequeueditems | Out-Null

if ($env:PROCESSOR_ARCHITECTURE -eq "AMD64") {
    $ngen64 = "$env:windir\microsoft.net\framework64\v4.0.30319\ngen.exe"

    & $ngen64 update /force /queue | Out-Null
    & $ngen64 executequeueditems | Out-Null
}

Log "Settings - Disable 'New network' window"
reg.exe add "HKLM\System\CurrentControlSet\Control\Network\NewNetworkWindowOff"
Log "Settings - High performance power plan"
powercfg -setactive scheme_min
Log "Settings - Disable hibernate file"
cmd /c "%systemroot%\System32\reg.exe ADD HKLM\SYSTEM\CurrentControlSet\Control\Power\ /v HibernateFileSizePercent /t REG_DWORD /d 0 /f"
cmd /c "%systemroot%\System32\reg.exe ADD HKLM\SYSTEM\CurrentControlSet\Control\Power\ /v HibernateEnabled /t REG_DWORD /d 0 /f"

Log "Drivers - Installing qemu Agent"
Start-Process msiexec.exe -Wait -ArgumentList ("/I ${setupdrive}\guest-agent\qemu-ga-x86_64.msi /quiet /norestart")
Log "Drivers - Installing qemu Guest Additions"
Start-Process msiexec.exe -Wait -ArgumentList ("/I ${setupdrive}\virtio-win-gt-x64.msi /quiet /norestart")
Log "Drivers - Manually installing viosock driver"
pnputil /add-driver "${setupdrive}\viosock\*.inf" /install /subdirs

start-sleep 30

Log "Install incus-agent"
$agentdrive = Get-WmiObject -Class Win32_Volume | Where-Object { $_.Label -eq "incus-agent" }
if ($agentdrive -and (Test-Path -Path "$($agentdrive.Name)install.ps1")) {
	. "$($agentdrive.Name)install.ps1"
}

. "${setupdrive}\OEM\spice.ps1" # copy-paste
start-sleep 30
# . "${setupdrive}\OEM\sac.ps1"
. "${setupdrive}\OEM\ConfigureRemotingForAnsible.ps1"

if (test-path "${setupdrive}\local\main.ps1") {
	. "${setupdrive}\local\main.ps1"
}

New-Item -ItemType Directory -Force -Path "$env:WINDIR\Setup\Scripts" | Out-Null

Log "Disable WinRM until Windows is fully initialized / started"
netsh advfirewall firewall set rule name="Allow WinRM HTTPS" new action=block
netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-In)" new action=block

$setupComplete = "$env:WINDIR\Setup\Scripts\SetupComplete.cmd"

# Write lines that will re-enable WinRM once Windows finishes initializing.
# SetupComplete.cmd is a batch file, so %WINDIR% must be written literally.
Add-Content -Path $setupComplete -Value 'netsh advfirewall firewall set rule name="Allow WinRM HTTPS" new action=allow >> %WINDIR%\Temp\SetupComplete.log'
Add-Content -Path $setupComplete -Value 'netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-In)" new action=allow >> %WINDIR%\Temp\SetupComplete.log'

Log "Running sysprep"
& "$env:WINDIR\System32\Sysprep\sysprep.exe" /generalize /oobe /shutdown /unattend:"${setupdrive}\OEM\unattend.xml"
