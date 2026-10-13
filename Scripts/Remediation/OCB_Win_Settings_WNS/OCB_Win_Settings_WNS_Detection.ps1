##################################################################
#  _____                                                   _____ 
# ( ___ )-------------------------------------------------( ___ )
#  |   |                                                   |   | 
#  |   |  █▀▀ █ █ █▀▄ █▀▀ █▀▄ █▀█ █▀▀ █ █  ▀█▀ █▀▀ █▀▀ █ █ |   | 
#  |   |  █    █  █▀▄ █▀▀ █▀▄ █▀█ █   █▀▄   █  █▀▀ █   █▀█ |   | 
#  |   |  ▀▀▀  ▀  ▀▀  ▀▀▀ ▀ ▀ ▀ ▀ ▀▀▀ ▀ ▀ ▀ ▀  ▀▀▀ ▀▀▀ ▀ ▀ |   | 
#  |___|                                                   |___| 
# (_____)-------------------------------------------------(_____)
#
##################################################################
# Authored by: Omar Assaf
# X: omar_assaf
# Please credit the author if you use this script
##################################################################


# Detect if renaming had happened already
$regPath = 'HKLM:\SOFTWARE\MSFOCB\Intune'
$MsfRegKeyValue = 'IntuneDeviceRename'
$MsfRenameVer = '3'
$RegPathSysNameCurrent = "HKLM:\SYSTEM\CurrentControlSet\Control\Computername\ActiveComputername"
$RegPathSysNameNew     = "HKLM:\SYSTEM\CurrentControlSet\Control\Computername\Computername"
$RegKeySysValueName   = "Computername"
$RegPathTcpipNameNew     = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
$RegKeyTcpipValueNameCurrent   = "Hostname"
$RegKeyTcpipValueNameNew       = "NV Hostname"


# Check if device is Hybrid Joined
$DomainStatus = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
If ($DomainStatus.PartOfDomain) {
    Write-Host "Device is Hybrid Joined, Cannot be renamed."
    Exit 0
}
# Check if device was already renamed
$OldSysName = $(Get-ItemProperty $RegPathSysNameCurrent -ErrorAction SilentlyContinue).$RegKeySysValueName
$NewSysName = $(Get-ItemProperty $RegPathSysNameNew -ErrorAction SilentlyContinue).$RegKeySysValueName
$RenameStatus = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue ).$MsfRegKeyValue
if ($RenameStatus -eq $MsfRenameVer -and $OldSysName -ne $NewSysName) {
    # Check if rename is pending restart
    Write-Host "Device is Renamed. Pending restart to change to $NewSysName."
    Exit 0
} elseif ($RenameStatus -eq $MsfRenameVer -and $OldSysName -eq $NewSysName) {
    # Confirm rename completed with restart
    Write-Host "Device is already renamed. No further action needed on $NewSysName."
    Exit 0
} else {
    # Proceed with renaming
    Write-Host "Device renaming process was not triggered yet on $NewSysName."
    exit 1
}
