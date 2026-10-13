#
#
# This script will detect if Automatic printer mapping is active
#
$TaskScriptFolder = "C:\Program Files (x86)\MSF\Printers"
$TaskScriptName = "MapPrinters.ps1"
$SchdTskName = "Map Shared Printers"
$TskReg = Get-ScheduledTask -TaskName $SchdTskName
if (("$TaskScriptFolder\$TaskScriptName") -and $TskReg) {
    write-host "Printer mapping  functioning automatically"
    exit 0
}
else {
    write-host "Printers could not be mapped automatically"
    exit 1
}

