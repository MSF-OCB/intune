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
#
# Authored by: Omar Assaf
# X: omar_assaf
# 
##################################################################

<#
.SYNOPSIS
    Change what happens when Lid is closed.
.DESCRIPTION
    This script will chnage the behavior of closing the lid when its connected to AC power source.
.EXAMPLE
    Just run the script.
.NOTES
    Authored by: Omar Assaf
    Date:02/Nov/2024.
    Version: 1.1
    Disclaimer: This script is provided 'as is' without any warranty. The author is not liable for any damages or issues that arise from using this script. Use at your own risk.
.LINK
    https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options
    https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings
    https://learn.microsoft.com/en-us/windows/win32/power/power-schemes
#>

##################################################################
#region Declarations
# Initialize variables and constants
# Power plan subgroup GUID for "Power buttons & LID"
$PowerSubgroupGUID = "4f971e89-eebd-4455-a8de-9e59040e7347"
# Power plan Setting GUID for "Lid close action"
$PowerSettingGUID = "5ca83367-6e45-459f-a27b-476b1d01c936"
#endregion
##################################################################
# Re-initialize power schemes
powercfg.exe -restoredefaultschemes
# Get all power schemes available
$AllPowerSchemes = powercfg.exe /list
# Iterate over each power scheme 
$AllPowerSchemes | ForEach-Object {
    # Only process lines that start with "Power Scheme GUID"
    if ($_ -match '^Power Scheme GUID:') {
        # Output only the Power Plan GUID from the list obtained
        if ($_ -match '([0-9a-fA-F-]{36})') {
            # Save the matched GUID as a variable
            $PowerPlanGUID = $matches[1]
            # Set the Lid close action to do nothing on AC power for each avilable power plan
            powercfg -setacvalueindex $PowerPlanGUID $PowerSubgroupGUID $PowerSettingGUID 0
            # Set the Lid close action to do nothing on AC power for the Active power plan
            if ($_ -match '\*') {
                Write-Output "ACTIVE Power Plan: $PowerPlanGUID"
                powercfg.exe -setacvalueindex SCHEME_CURRENT $PowerSubgroupGUID $PowerSettingGUID 0
                powercfg.exe /setactive $PowerPlanGUID
            }
            # Write-Output $PowerPlanGUID
        }
        else {
            Write-Output "Not a valid Power plan"
        }
    }
}
