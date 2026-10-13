#
#
# This script will do the following:
#   1-Copy "MapPrinters.ps1" to its destination
#   2-Register a scheduled task to run the script at everytime user login
#
#
# Declare Variables
$CompanyName = "MSFOCB"
$TaskSchdXML = "https://msfocbshare.blob.core.windows.net/ict-prod/push/mapNetworkPrinters.xml"
$UriAddress = "https://msfocbshare.blob.core.windows.net/ict-prod/push/Printer_map_function.ps1"
$SchdTskName = "Map Shared Printers"
$TaskScriptName = "MapPrinters.ps1"
$TaskScriptFolder = "C:\Program Files (x86)\MSF\Printers"
$ScriptSourceDirectory = Split-Path -Parent $PSCommandPath

#region Functions
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
#endregion Functions

# ------------------------------------------------------------------------------------------------------- #
# Start Transcript
# ------------------------------------------------------------------------------------------------------- #
$Transcript = "C:\programdata\Microsoft\IntuneManagementExtension\Logs\$($(Split-Path $PSCommandPath -Leaf).ToLower().Replace(".ps1",".log"))"
Start-Transcript -Path $Transcript | Out-Null

# ------------------------------------------------------------------------------------------------------- #
# Create local copy of the script to be run from the Task Scheduler
# ------------------------------------------------------------------------------------------------------- #
if (!(Test-Path -path $TaskScriptFolder)) {
# Target Folder does not yet exist
	Write-Host "Creating Folder '$TaskScriptFolder' ..."
	New-Item $TaskScriptFolder -Type Directory | Out-Null
}

try {
	Write-Host "Source folder to copy script from: '$ScriptSourceDirectory'"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -Method Get -Uri $UriAddress -OutFile "$TaskScriptFolder\$TaskScriptName" -UseBasicParsing -ErrorAction Stop | Out-Null
	Write-Host "Created local copy of the script '$TaskScriptName' in folder: '$TaskScriptFolder'"
} catch {
	Write-Host "ERROR creating local copy of the script '$TaskScriptName' in folder: '$TaskScriptFolder'"
	CleanUpAndExit -ErrorLevel 1
}

# ------------------------------------------------------------------------------------------------------- #
# Create Scheduled Task to run At Logon
# ------------------------------------------------------------------------------------------------------- #
$XMLSTRING = (Invoke-WebRequest -URI $TaskSchdXML -UseBasicParsing).content
Register-ScheduledTask -TaskName $SchdTskName -XML $XMLSTRING -TaskPath "\$CompanyName" -Force


# ------------------------------------------------------------------------------------------------------- #
# Check End State
# ------------------------------------------------------------------------------------------------------- #
try {
    Get-ScheduledTask -TaskName $SchdTskName -ErrorAction Stop | Out-Null
    write-host "SUCCESS: Task is Scheduled."
    CleanUpAndExit -ErrorLevel 0
} catch {
    write-host "ERROR: Scheduled Task could not be found."
    CleanUpAndExit -ErrorLevel 2
}
