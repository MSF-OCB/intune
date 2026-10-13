#  _______     ______  ______ _____            _____ _  _________ ______ _____ _    _ 
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
    Register FortiClient.

.DESCRIPTION
    This script will register FortiClient to the specified EMS server.

.EXAMPLE
    Just run the script.

.NOTES
    Author: Omar Assaf
    lastUpdated: Aug-2025
    Version: 1.3
    Disclaimer: This script is provided 'as is' without any warranty. The author is not liable for any damages or issues that arise from using this script. Use at your own risk.

.LINK
    https://docs.fortinet.com/document/forticlient/7.4.3/administration-guide/95591/forticlient-windows-cli-commands
#>

##################################################################

##################################################################
# Define the registry path and value name
$registryPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\FA_ESNAC"
$valueName = "fgt_name"

# Try to get the registry value
try {
    $fgtNameValue = (Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction Stop).$valueName

    if ($fgtNameValue -eq "EMS-OCB.dmz.brussels.ocb.msf.org") {
        Write-Host "FortiClient is registered to proper EMS server: $fgtNameValue"
        exit 0
    }
    else {
        Write-Host "FortiClient is not registered to OCB proper EMS server."
        exit 1
    }
}
catch {
    Write-Host "Registry key or value not found."
    exit 1
}
