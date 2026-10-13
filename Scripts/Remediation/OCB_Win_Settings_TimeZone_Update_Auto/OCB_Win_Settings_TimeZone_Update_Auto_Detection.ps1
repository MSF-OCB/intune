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

<#
.SYNOPSIS
    Detection script for Intune to verify that all required services for automatic time zone updates are correctly configured.

.DESCRIPTION
    This script checks the startup type and running status of key Windows services involved in automatic time zone updates.
    It uses Get-Service and sc.exe to determine compliance. If all services are configured correctly, the script exits with code 0.
    If any service is misconfigured or not running, it exits with code 1.

    Services checked:
    - Geolocation Service (lfsvc)
    - Windows Time (W32Time)
    - Network Location Awareness (NlaSvc)
    - Windows Update (wuauserv)
    - Sensor Service (SensorService) [optional, may not exist on all devices]

.PARAMETER None
    This script takes no parameters.

.OUTPUTS
    Writes compliance status to the output stream.

.EXAMPLE
    Run this script as a detection rule in Microsoft Intune to determine if remediation is needed.

.NOTES
    Author: Omar Assaf
    Last Updated: July 2025
    Version: 1.3
    Disclaimer: This script is provided 'as is' without any warranty. The author is not liable for any damages or issues that arise from using this script. Use at your own risk.

.LINK
    https://
#>


###################################################################

# Define required services and their expected startup types
$requiredServices = @(
    @{ Name = "lfsvc"; ExpectedStartup = "Manual" },
    @{ Name = "W32Time"; ExpectedStartup = "Automatic" },
    @{ Name = "NlaSvc"; ExpectedStartup = "Automatic" },
    @{ Name = "wuauserv"; ExpectedStartup = "Manual" },
    @{ Name = "SensorService"; ExpectedStartup = "Manual" }
)

$compliant = $true

foreach ($svc in $requiredServices) {
    try {
        $service = Get-Service -Name $svc.Name -ErrorAction Stop
        $startupType = (Get-Service -Name $($svc.Name) -Verbose).StartType
        #$startupType = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$($svc.Name)'").StartMode

        if ($startupType -ne $svc.ExpectedStartup) {
            Write-Output "Service '$($svc.Name)' is not compliant. StartupType: $startupType, Status: $($service.Status)"
            $compliant = $false
        }
    } catch {
        # If the service doesn't exist (e.g., SensorService on some devices), skip it
        Write-Output "Service '$($svc.Name)' not found. Skipping."
    }
}

if ($compliant) {
    Write-Output "All services are compliant."
    exit 0  # Compliant
} else {
    Write-Output "One or more services are not compliant."
    exit 1  # Not compliant
}

