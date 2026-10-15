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
    Fix Appxbundle.

.DESCRIPTION
    This script will install Company Portal & Microsoft Store.

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
# --- Start Transcript Logging ---
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
# Get the script name without the path
$scriptName = $MyInvocation.MyCommand.Name
# Remove the file extension
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($scriptName)
# Split the name by the first underscore only
$splitIndex = $baseName.IndexOf('_')
if ($splitIndex -gt -1) {
    $Directory = $baseName.Substring(0, $splitIndex)
    $Details = $baseName.Substring($splitIndex + 1)
} else {
    # If no underscore is found, assign the whole name to Directory and leave Details empty
    $Directory = $baseName
    $Details = ""
}
# Define the log path and file name
$intuneLogsPath = "C:\ProgramData\MSF\Logs\Intune\"
$logFileLocationName = "$intuneLogsPath\$Directory\$Details.txt"
if (-not (Test-Path $intuneLogsPath\$Directory)) {
    New-Item -Path $intuneLogsPath\$Directory -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path $logFileLocationName -Force -Confirm:$false | Out-Null
###################################################################
# Preferences
$ProgressPreference = 'SilentlyContinue' # Suppress progress bar (makes downloading super fast)
$ConfirmPreference = 'None' # Suppress confirmation prompts
Set-ExecutionPolicy Bypass -Scope Process -Force
if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-Host ">> Installing NuGet package provider..." -ForegroundColor Yellow
        Install-PackageProvider -Name NuGet -Force -Scope AllUsers -Confirm:$false | Out-Null
    } else { Write-Host ">> NuGet package provider is installed." -ForegroundColor Green }
#
if ($null -eq (get-module microsoft.winget.client)) {
    Write-Host ">> Installed MSIXBundle Winget AppInstaller..." -ForegroundColor Yellow
    install-module microsoft.winget.client -Scope AllUsers -Force -AllowClobber
    }else { Write-Host ">> Winget is installed." -ForegroundColor Green }
#
import-module microsoft.winget.client -Force
Write-Host ">> Repairing MSIXBundleApp..." -ForegroundColor Yellow
repair-wingetpackagemanager
# Check if Microsoft Store is installed
if (-not (Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction SilentlyContinue)) {
    Write-Host ">> Installing Microsoft Store..." -ForegroundColor Yellow
    install-wingetpackage 9WZDNCRFJBMP -source msstore -Scope Any | Out-Null # Microsoft Store
}else {Write-Host ">> Microsoft Store is installed." -ForegroundColor Green}
# Check if Company Portal is installed
if (-not (Get-AppxPackage -Name Microsoft.CompanyPortal -ErrorAction SilentlyContinue)) {
    Write-Host ">> Installing Company Portal..." -ForegroundColor Yellow
    install-wingetpackage 9WZDNCRFJ3PZ -source msstore -Scope Any | Out-Null # Company Portal
}else {Write-Host ">> Company Portal is installed." -ForegroundColor Green}
Stop-Transcript  | Out-Null
