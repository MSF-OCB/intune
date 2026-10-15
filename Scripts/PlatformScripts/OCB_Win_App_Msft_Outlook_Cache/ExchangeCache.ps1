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
    Change exchange cache.
.DESCRIPTION
    This script will chnage the default settings for Exchange cache mode
    It will enable cache exchange mode, it will optimize it for slow/poor connectivity offices.
    It will download only headers, and only cache 3 months in Outlook settings.
.EXAMPLE
    Just run the script.
.NOTES
    Authored by: Omar Assaf
    Date:10/Nov/2024.
    Version: 1.0
    Disclaimer: This script is provided 'as is' without any warranty. The author is not liable for any damages or issues that arise from using this script. Use at your own risk.
.LINK
    https://learn.microsoft.com/en-us/outlook/troubleshoot/installation/cached-exchange-mode
#>

##################################################################
# Define the registry path to be added
$regPath = "Software\Policies\Microsoft\Office\16.0\Outlook\Cached Mode"

# Define the Exchange cache mode settings
$dwordValues = @{
    "CachedExchangeMode" = 1
    "Enable" = 1
    "SyncWindowSetting" = 3
}
##################################################################

# Get all user SIDs from HKEY_USERS
$userSIDs = Get-ChildItem -Path "Registry::HKEY_USERS" | Select-Object -ExpandProperty PSChildName

# Define the regular expression pattern for the SID formats
$pattern = "^S-1-(5-21|12-1)-\d{1,10}-\d{1,10}-\d{1,10}(-\d{1,10})?$"

# Filter SIDs to match the specific formats
$filteredSIDs = $userSIDs | Where-Object { $_ -match $pattern }

foreach ($sid in $filteredSIDs) {
    # Construct the full registry path for the current user SID
    $fullRegPath = "Registry::HKEY_USERS\$sid\$regPath"
    
    # Check if the registry key already exists
    if (-not (Test-Path -Path $fullRegPath)) {
        # Create the registry key if it does not exist
        New-Item -Path $fullRegPath -Force | Out-Null
        Write-Output "Created registry key: $fullRegPath"
    } else {
        Write-Output "Registry key already exists: $fullRegPath"
    }
    
    # Add the DWORD values
    foreach ($name in $dwordValues.Keys) {
        Set-ItemProperty -Path $fullRegPath -Name $name -Value $dwordValues[$name] -Type DWord
        Write-Output "Set DWORD $name to $($dwordValues[$name]) at $fullRegPath"
    }
}

