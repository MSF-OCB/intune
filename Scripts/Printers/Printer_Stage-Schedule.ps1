#
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
# Author: Omar Assaf
# X: omar_assaf
#
#
# Please credit the author if you use this script
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
#
#
# This script will do the following:
#   1-Stage printer drivers
#   2-Copy Printer Mapping Script to its destination
#   3-Register a scheduled task to run printer mapping function everytime user login
#
#
# ^**^**^**^**^**^**^**^**
# Declare variables
# ^**^**^**^**^**^**^**^**
$CompanyName = "MSFOCB"
$TaskSchdXML = "MapNetworkPrinters.xml"
$SchdTskName = "Map Shared Printers"
$TaskScriptName = "Printer_Mapping_Function.exe"
$TaskScriptFolder = "C:\Program Files (x86)\MSF\Printers"
$ScriptSourceDirectory = Split-Path -Parent $PSCommandPath
#
# ^**^**^**^**^**^**^**^**
# Functions
# ^**^**^**^**^**^**^**^**
#
Function CleanUpAndExit() {
    Param(
        [Parameter(Mandatory=$True)][String]$ErrorLevel
    )

    # Write results to registry for Intune Detection
    $Key = "HKEY_LOCAL_MACHINE\Software\$CompanyName\PrinterMapping\v2"
    $NOW = Get-Date -Format "yyyyMMdd-hhmmss"

    If ($ErrorLevel -eq "0") {
        [microsoft.win32.registry]::SetValue($Key, "Scheduled", $NOW)
    } else {
        [microsoft.win32.registry]::SetValue($Key, "Failure", $NOW)
        [microsoft.win32.registry]::SetValue($Key, "Error Code", $Errorlevel)
    }
    
    # Exit Script with the specified ErrorLevel
    Stop-Transcript | Out-Null
    EXIT $ErrorLevel
}
#
#
# ------------------------------------------------------------------------------------------------------- #
# Start Transcript
# ------------------------------------------------------------------------------------------------------- #
#
$Transcript = "C:\programdata\MSF\Logs\Printer_Install_Drv_Task.log"
Start-Transcript -Path $Transcript | Out-Null
#
# ------------------------------------------------------------------------------------------------------- #
# Start Printer Driver Staging
# ------------------------------------------------------------------------------------------------------- #
#
pnputil.exe /add-driver "$PSScriptRoot\Driver\r4600.inf" /install
#
# ------------------------------------------------------------------------------------------------------- #
# Create local copy of the script to be run from the Task Scheduler
# ------------------------------------------------------------------------------------------------------- #
#
if (!(Test-Path -path $TaskScriptFolder)) {
# Target Folder does not yet exist
	Write-Host "Creating Folder '$TaskScriptFolder' ..."
	New-Item $TaskScriptFolder -Type Directory | Out-Null
}

try {
	Write-Host "`nSource folder to copy script from: '$ScriptSourceDirectory'"
	Copy-Item "$ScriptSourceDirectory\$TaskScriptName" -Destination "$TaskScriptFolder" -Force -Confirm:$false -ErrorAction Stop
	Write-Host "Created local copy of the script '$TaskScriptName' in folder: '$TaskScriptFolder'"
} catch {
	Write-Host "ERROR creating local copy of the script '$TaskScriptName' in folder: '$TaskScriptFolder'"
	CleanUpAndExit -ErrorLevel 1
}
#
# ------------------------------------------------------------------------------------------------------- #
# Create Scheduled Task to run At Logon
# ------------------------------------------------------------------------------------------------------- #
#
$XMLSTRING = Get-Content $ScriptSourceDirectory\$TaskSchdXML -Raw
Register-ScheduledTask -TaskName $SchdTskName -XML $XMLSTRING -TaskPath "\$CompanyName" -Force
#
# ------------------------------------------------------------------------------------------------------- #
# Check End State
# ------------------------------------------------------------------------------------------------------- #
#
try {
    Get-ScheduledTask -TaskName $SchdTskName -ErrorAction Stop | Out-Null
    write-host "`nSUCCESS: Printer mapping task is scheduled."
    CleanUpAndExit -ErrorLevel 0
} catch {
    write-host "ERROR: Scheduled Task could not be found."
    CleanUpAndExit -ErrorLevel 2
}
