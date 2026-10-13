##################################################################
#   _______     ______  ______ _____            _____ _  _________ ______ _____ _    _ 
#  / ____\ \   / /  _ \|  ____|  __ \     /\   / ____| |/ /__   __|  ____/ ____| |  | |
# | |     \ \_/ /| |_) | |__  | |__) |   /  \ | |    | ' /   | |  | |__ | |    | |__| |
# | |      \   / |  _ <|  __| |  _  /   / /\ \| |    |  <    | |  |  __|| |    |  __  |
# | |____   | |  | |_) | |____| | \ \  / ____ \ |____| . \ _ | |  | |___| |____| |  | |
#  \_____|  |_|  |____/|______|_|  \_\/_/    \_\_____|_|\_(_)|_|  |______\_____|_|  |_|
#
##################################################################
# Authored by: Omar Assaf
# X: omar_assaf
# Please credit the author if you use this script
##################################################################

<#
.SYNOPSIS
    Update time zone settings.

.DESCRIPTION
    This script will change the default settings for the Windows Time Zone Auto Updater service.

.EXAMPLE
    Just run the script.

.NOTES
    Author: Omar Assaf
    lastUpdated: July-2025
    Version: 1.0
    Disclaimer: This script is provided 'as is' without any warranty. The author is not liable for any damages or issues that arise from using this script. Use at your own risk.

.LINK
    https://learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/cannot-set-timezone-automatically
#>

##################################################################
# --- Start Transcript Logging ---
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = "C:\ProgramData\MSF\Logs\Intune\Remediation"
$logFile = "$logPath\TimeZone_AutoUpdate_Remediate.log"

if (-not (Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path $logFile -Force -Append
###################################################################

##################################################################
# Define a helper function to set service startup type and start it if not running
function Set-And-Start-Service {
    param (
        [string]$ServiceName,
        [string]$DisplayName,
        [string]$DesiredStartupType
    )

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        #$currentStartupType = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'").StartMode
        $currentStartupType = (Get-Service -Name $ServiceName -Verbose).StartType

        if ($currentStartupType -ne $DesiredStartupType) {
            Write-Output "Changing '$DisplayName' ($ServiceName) startup type from '$currentStartupType' to '$DesiredStartupType'."
            Set-Service -Name $ServiceName -StartupType $DesiredStartupType
        } else {
            Write-Output "'$DisplayName' ($ServiceName) is already set to '$DesiredStartupType'."
        }

        if ($service.Status -ne 'Running') {
            Write-Output "Starting '$DisplayName' ($ServiceName)..."
            Start-Service -Name $ServiceName
        } else {
            Write-Output "'$DisplayName' ($ServiceName) is already running."
        }
    } catch {
        Write-Warning "Service '$DisplayName' ($ServiceName) not found or could not be modified."
        Stop-Transcript
    }
}

# Services and their desired startup types
$services = @(
    @{ Name = "tzautoupdate"; Display = "Auto Time Zone Updater"; StartupType = "Automatic" },
    @{ Name = "lfsvc"; Display = "Geolocation Service"; StartupType = "Manual" },
    @{ Name = "W32Time"; Display = "Windows Time"; StartupType = "Automatic" },
    @{ Name = "NlaSvc"; Display = "Network Location Awareness"; StartupType = "Automatic" },
    @{ Name = "wuauserv"; Display = "Windows Update"; StartupType = "Manual" },
    @{ Name = "SensorService"; Display = "Sensor Service"; StartupType = "Manual" }
)

# Apply settings
foreach ($svc in $services) {
    Set-And-Start-Service -ServiceName $svc.Name -DisplayName $svc.Display -DesiredStartupType $svc.StartupType
}
Restart-Service -Name "W32Time" -Force #-ErrorAction SilentlyContinue
Restart-Service -Name "lfsvc" -Force #-ErrorAction SilentlyContinue
#Restart-Service -Name "NlaSvc" -Force #-ErrorAction SilentlyContinue
Write-Output "All relevant services have been checked, configured, and started if necessary."
# Resync time
w32tm /resync /force
# --- End Transcript Logging ---
Stop-Transcript
