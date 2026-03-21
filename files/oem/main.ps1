Function Log {
    $Message = $args[0]
    Write-Output $Message
}

get-wmiobject win32_logicaldisk | % {
	if ($_.volumename -like 'STUFF*') {
		$setupdrive = $_.deviceid
	}
}

cmd.exe /c "${setupdrive}\OEM\compile-dotnet-assemblies.bat"

Log "Settings - Disable 'New network' window"
reg.exe add "HKLM\System\CurrentControlSet\Control\Network\NewNetworkWindowOff"
Log "Settings - High performance power plan"
powercfg -setactive scheme_min
Log "Settings - Disable hibernate file"
cmd /c "%systemroot%\System32\reg.exe ADD HKLM\SYSTEM\CurrentControlSet\Control\Power\ /v HibernateFileSizePercent /t REG_DWORD /d 0 /f"
cmd /c "%systemroot%\System32\reg.exe ADD HKLM\SYSTEM\CurrentControlSet\Control\Power\ /v HibernateEnabled /t REG_DWORD /d 0 /f"

Log "Drivers - Installing qemu Agent"
Start-Process msiexec.exe -Wait -ArgumentList ("/I ${setupdrive}\guest-agent\qemu-ga-x86_64.msi /quiet")
Log "Drivers - Installing qemu Guest Additions"
Start-Process msiexec.exe -Wait -ArgumentList ("/I ${setupdrive}\virtio-win-gt-x64.msi /quiet")
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

cmd.exe /c "${setupdrive}\OEM\sysprep.bat" "${setupdrive}\OEM\unattend.xml"
