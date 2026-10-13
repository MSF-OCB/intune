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
# --- Start Transcript Logging ---
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = "C:\ProgramData\MSF\Logs\Intune\Remediation"
$logFile = "$logPath\Forticlient_Registration_Remediate.log"

if (-not (Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path $logFile -Force
###################################################################

##################################################################
# Define the path to the FortiESNAC executable
$fortiESNACPath = "C:\Program Files\Fortinet\FortiClient\FortiESNAC.exe"

# Define the argument for the executable
$arguments = "-r ems.ocb.msf.org"

# Start transcript to log the script execution
Start-Transcript -Path "C:\Logs\FortiESNAC_Execution.log" -Append -Force

try {
    # Verify if the executable exists
    if (Test-Path -Path $fortiESNACPath) {
        Write-Host "Executing FortiESNAC with arguments: $arguments"
        
        # Execute the FortiESNAC command
        Start-Process -FilePath $fortiESNACPath -ArgumentList $arguments -Wait -NoNewWindow
        
        Write-Host "FortiESNAC executed successfully."
    }
    else {
        Write-Error "FortiESNAC executable not found at: $fortiESNACPath"
    }
}
catch {
    # Log any errors that occur during execution
    Write-Error "An error occurred while executing FortiESNAC: $_"
}
finally {
    # Stop the transcript logging
    Stop-Transcript
}
