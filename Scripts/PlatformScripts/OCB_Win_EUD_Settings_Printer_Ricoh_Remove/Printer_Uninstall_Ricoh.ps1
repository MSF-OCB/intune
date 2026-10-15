##################################################################
#  _____                                                   _____ 
# ( ___ )-------------------------------------------------( ___ )
#                                                            
#       █▀▀ █ █ █▀▄ █▀▀ █▀▄ █▀█ █▀▀ █ █  ▀█▀ █▀▀ █▀▀ █ █     
#       █    █  █▀▄ █▀▀ █▀▄ █▀█ █   █▀▄   █  █▀▀ █   █▀█     
#       ▀▀▀  ▀  ▀▀  ▀▀▀ ▀ ▀ ▀ ▀ ▀▀▀ ▀ ▀ ▀ ▀  ▀▀▀ ▀▀▀ ▀ ▀     
#   ___                                                     ___ 
# (_____)-------------------------------------------------(_____)
#
##################################################################
# Authored by Omar Assaf
# X omar_assaf
# Please credit the author if you use this script
##################################################################

<#
.SYNOPSIS
    Function to uninstall Ricoh printer drivers.

.DESCRIPTION
    This script will uninstall Ricoh printer drivers from the system.

.EXAMPLE
    Just run the script.

.NOTES
    Author Omar Assaf
    lastUpdated July-2025
    Version 1.0
    Disclaimer This script is provided 'as is' without any warranty. The author is not liable for any damages or issues that arise from using this script. Use at your own risk.

.LINK
    https://
#>


##################################################################
# Uninstall Script for Printer Setup Components
##################################################################
# Declare Variables for logging
$CompanyLogName = "MSF"
$Category = "Scripts"
$logFileName = "Printer_Ricoh_Uninstall.log"
$intuneLogsPath = "C:\ProgramData\$CompanyLogName\Logs\Intune\$Category"
$logFileLocationName = "$intuneLogsPath\$logFileName"
#
# --- Start Transcript Logging ---
if (-not (Test-Path $intuneLogsPath)) {
    New-Item -Path $intuneLogsPath -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path $logFileLocationName -Force -Confirm:$false -Append
##################################################################

##################################################################
# --- Configuration Variables ---
$CompanyName = "MSFOCB"
$TaskSchdXML = "MapNetworkPrinters.xml"
$SchdTskName = "Map Shared Printers"
$TaskScriptName = "Printer_Mapping_Function.exe"
$TaskScriptFolder = "C:\Program Files (x86)\MSF\Printers"
$RegKey = "HKEY_LOCAL_MACHINE\Software\MSFOCB\PrinterMapping\v2"
$printerRicohOriginalDriver = "r4600.inf"
#
###################################################################
# --- Function: Clean Up and Exit ---
Function CleanUpAndExit {
    Param(
        [Parameter(Mandatory=$True)][String]$ErrorLevel
    )

    $NOW = Get-Date -Format "yyyyMMdd-HHmmss"

    if ($ErrorLevel -eq "0") {
        [Microsoft.Win32.Registry]::SetValue($RegKey, "Uninstalled", $NOW)
    } else {
        [Microsoft.Win32.Registry]::SetValue($RegKey, "UninstallFailure", $NOW)
        [Microsoft.Win32.Registry]::SetValue($RegKey, "Error Code", $ErrorLevel)
    }

    Stop-Transcript | Out-Null
    EXIT $ErrorLevel
}

##################################################################
# --- Remove Scheduled Task ---
try {
    Write-Host "Removing Scheduled Task '$SchdTskName'..."
    if (Get-ScheduledTask -TaskName $SchdTskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $SchdTskName -Confirm:$false -ErrorAction Continue
        Write-Host "Successfully removed Scheduled Task '$SchdTskName'"
    } else {
        Write-Host "Scheduled Task '$SchdTskName' not found, skipping..."
    }
} catch {
    Write-Host "ERROR removing Scheduled Task: $_"
    CleanUpAndExit -ErrorLevel 1
}

##################################################################
# --- Remove Script Folder ---
try {
    Write-Host "Removing script folder '$TaskScriptFolder'..."
    if (Test-Path -Path $TaskScriptFolder) {
        Remove-Item -Path $TaskScriptFolder -Recurse -Force -ErrorAction Stop
        Write-Host "Successfully removed script folder '$TaskScriptFolder'"
    } else {
        Write-Host "Script folder '$TaskScriptFolder' not found, skipping..."
    }
} catch {
    Write-Host "ERROR removing script folder: $_"
    CleanUpAndExit -ErrorLevel 3
}

##################################################################
<#
# --- Remove Registry Entries ---
try {
    Write-Host "Removing registry entries..."
    if (Test-Path -Path $RegKey) {
        Remove-Item -Path $RegKey -Recurse -Force -ErrorAction Stop
        Write-Host "Successfully removed registry entries"
    } else {
        Write-Host "Registry key '$RegKey' not found, skipping..."
    }
} catch {
    Write-Host "ERROR removing registry entries: $_"
    CleanUpAndExit -ErrorLevel 4
}
#>
##################################################################
# --- Remove Printer Driver ---
try {
    Write-Host "Searching for printer driver with original name '$printerRicohOriginalDriver'..."
    $driverBlocks = pnputil /enum-drivers | Out-String -Stream

    $currentBlock = @{}
    $driverList = @()

    foreach ($line in $driverBlocks) {
        if ($line -match "^\s*$") {
            if ($currentBlock.Count -gt 0) {
                $driverList += [PSCustomObject]$currentBlock
                $currentBlock = @{}
            }
        } elseif ($line -match "^\s*(.+?)\s*:\s*(.+)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            $currentBlock[$key] = $value
        }
    }

    # Add the last block if needed
    if ($currentBlock.Count -gt 0) {
        $driverList += [PSCustomObject]$currentBlock
    }

    $targetDriver = $driverList | Where-Object { $_."Original Name" -eq $printerRicohOriginalDriver }

    if ($targetDriver -and $targetDriver."Published Name") {
        $publishedName = $targetDriver."Published Name"
        Write-Host "Removing printer driver '$publishedName'..."
        pnputil.exe /delete-driver $publishedName /force
        Write-Host "Successfully removed printer driver"
    } else {
        Write-Host "Printer driver with original name '$printerRicohOriginalDriver' not found, skipping..."
    }
} catch {
    Write-Host "ERROR removing printer driver: $_"
    CleanUpAndExit -ErrorLevel 2
}

##################################################################
# --- Final Success Message ---
Write-Host "SUCCESS: All components removed successfully"
CleanUpAndExit -ErrorLevel 0

