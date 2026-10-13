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
    Autodesk Inventory Tool (AIT) Report detection.

.DESCRIPTION
    This script will detect if the AIT report is available for upload.

.EXAMPLE
    Just run the script.

.NOTES
    Author: Omar Assaf
    lastUpdated: Aug-2025
    Version: 1.0
    Disclaimer: This script is provided 'as is' without any warranty. The author is not liable for any damages or issues that arise from using this script. Use at your own risk.

.LINK
    https://samtools.autodesk.com/m/104297/l/1403329-introduction
#>

##################################################################
$CompanyName = "MSFOCB"  # Replace with your actual company name
$Key = "HKLM:\Software\$CompanyName\Autodesk\Inventory"
$AITPath = "C:\Program Files (x86)\Autodesk\Autodesk Inventory Tool\AIT.exe"
$DeviceSerial = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
$targetPath = "C:\ProgramData\Autodesk\AIT\Autodesk-$DeviceSerial.xml" 

# Check if the 'Uploaded' value exists and is not empty
$uploadedValue = Get-ItemProperty -Path $Key -Name "Uploaded" -ErrorAction SilentlyContinue

if ((Test-Path $targetPath) -and $uploadedValue -and ![string]::IsNullOrEmpty($uploadedValue.Uploaded)) {
    Write-Output "Success: Autodesk Inventory report already uploaded."
    exit 0
}
elseif (-not (Test-Path $AITPath)) {
    Write-Output "Error: AIT is not installed."
    exit 1
}
elseif (![string]::IsNullOrEmpty($uploadedValue.Uploaded)) {
    Write-Output "old report detected, needs re-upload."
    exit 1
}
elseif (!(Test-Path $targetPath)) {
    Write-Output "New report is not created for upload."
    exit 1
}
else {
    Write-Output "Error: check on local machine."
    exit 1
}
