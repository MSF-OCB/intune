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
    Allow manual time zone settings.

.DESCRIPTION
    This script will change the time zone settings to allow manual configuration.

.EXAMPLE
    Just run the script.

.NOTES
    Author: Omar Assaf
    lastUpdated: Oct-2025
    Version: 3.1
    Disclaimer: This script is provided 'as is' without any warranty. The author is not liable for any damages or issues that arise from using this script. Use at your own risk.

.LINK
    https://learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/cannot-set-timezone-automatically
#>

##################################################################
Set-Service -Name tzautoupdate -StartupType Disabled
Stop-Service -Name w32time
w32tm /unregister
w32tm /register
Start-Service -Name w32time
w32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /update
w32tm /resync /nowait
