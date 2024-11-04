<#
.SYNOPSIS
    Print screen key modification.
.DESCRIPTION
    This script will enablePrtSc keyboard key to run snipping tool.
.EXAMPLE
    Just run the script.
.NOTES
    Authored by: Omar Assaf
    Date:02/Nov/2024.
    Version: 1.1
    Disclaimer: This script is provided 'as is' without any warranty. The author is not liable for any damages or issues that arise from using this script. Use at your own risk.
#>


##################################################################
# Please credit the author if you use this script
##################################################################
#region
# This key will enablePrtSc keyboard key to run snipping tool
New-ItemProperty "HKCU:\Control Panel\Keyboard" -Name "PrintScreenKeyForSnippingEnabled" -PropertyType DWord -Value "1" -Force
#endregion
