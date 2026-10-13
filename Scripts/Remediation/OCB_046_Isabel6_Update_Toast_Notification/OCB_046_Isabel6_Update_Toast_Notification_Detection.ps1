## ==========================================================================
## MSFOCB Script
## --------------------------------------------------------------------------
## Filename   : Detection_Method_for_presence_and_version_v3.ps1
## Version         : 3.0
## Creation Date   : 10-01-2025
## Last Update     : -
## --------------------------------------------------------------------------
## Script's Author    : Fabrizio.Murgia@brussels.msf.org
## --------------------------------------------------------------------------
## ==========================================================================

#### -==- MAIN -==- ####

# Set up PowerShell parameters
Set-PSDebug -Trace 0    # 0 - 1 - 2
Set-StrictMode -Version 3

# Retrive the path from where the script has been run and put it in the $MyPath variable
$MyPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$_ALLUSERSPROFILE = ${Env:ALLUSERSPROFILE}

## ::::::::::::::::::::::::::::::::::::::

# Define the registry paths for both 64-bit and 32-bit
$appName = "Isabel Security Components"
$requiredVersion = "6.36.0008"
$_registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# Function to normalize only the third part of the version (e.g., .0008)
function NormalizeVersion {
    param (
        [string]$version,
        [int]$buildWidth = 4  # Pad the build number to 4 digits
    )

    $parts = $version -split '\.'
    if ($parts.Count -ge 3) {
        $parts[2] = $parts[2].PadLeft($buildWidth, '0')
    }
    return ($parts -join '.')
}

# Function to check if the application is installed and meets the version requirement
function CheckApp {
    $appInstalled = $false
    $InstalledVersion = "0.00.0000"

    foreach ($registryPath in $_registryPaths) {
        $subKeys = Get-ChildItem -Path $registryPath
        foreach ($subKey in $subKeys) {
            try {
                $item = Get-ItemProperty -Path $subKey.PSPath
                if ($item.DisplayName -like "*$appName*") {
                    $displayVersion = $item.DisplayVersion
                    $cleanVersion = ($displayVersion -split '\+')[0]  # Remove build metadata if present
                    $InstalledVersion = NormalizeVersion $cleanVersion
                    $appInstalled = $true
                    break
                }
            } catch {
                continue
            }
        }
        if ($appInstalled) { break }
    }

    $normalizedRequired = NormalizeVersion $requiredVersion
    $MeetsRequirement = ($appInstalled -and ($InstalledVersion -ge $normalizedRequired))

    return [PSCustomObject]@{
        AppInstalled         = $appInstalled
        InstalledVersion     = $InstalledVersion
        RequiredVersion      = $normalizedRequired
        MeetsRequirement     = $MeetsRequirement
    }
}

# Main logic
$result = CheckApp
$InstalledVersion = $result.InstalledVersion
$requiredVersion = $result.RequiredVersion

if ($result.MeetsRequirement) {
    Write-Output "$appName version ($InstalledVersion) is up-to-date or newer. No replacement needed."
    exit 0
} else {
    Write-Output "$appName version ($InstalledVersion) is older than requested ($requiredVersion) or is not installed on the machine."
    exit 1
}

#EOF#

