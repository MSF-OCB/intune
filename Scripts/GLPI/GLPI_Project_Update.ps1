#
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
# Author: Omar Assaf
# X: omar_assaf
#
#
# Please credit the author if you use this script
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
#
# This script will assign proper project code to device in a list.
# It includes different clear output messages for each missing component.
#
# ^**^**^**^**^**^**^**^**
# Start Transcript
# ^**^**^**^**^**^**^**^**
#
$TranscriptGlpi = 'C:\ProgramData\MSF\Logs\GLPI_Project_Update.log'
Start-Transcript -Path $TranscriptGlpi | Out-Null
#
# ^**^**^**^**^**^**^**^**
# Declare variables
# ^**^**^**^**^**^**^**^**
#
$GlpiRegPath = "HKLM:\SOFTWARE\GLPI-Agent"
$GlpiPushUri = "
http://localhost:62355/now"
$DeviceSN = (Get-WmiObject -class win32_bios).SerialNumber
$ComputerList = Invoke-RestMethod -Method Get "
https://msfocbshare.blob.core.windows.net/ict-sd/data/ComputerName.csv"
-UseBasicParsing | ConvertFrom-Csv
$ProjectCode = ($ComputerList | where-object Serial -EQ $DeviceSN).Project
#
# ^**^**^**^**^**^**^**^**
# Main script
# ^**^**^**^**^**^**^**^**
#
If ($null -ne $ProjectCode){
    # Set the scope of the environment variables to SYSTEM
    [System.Environment]::SetEnvironmentVariable("MSFPROJECTCODE", $env:MSFPROJECTCODE, "Machine")
    # Set the environment variables
    Write-Host "> Setting system environment variable to: $ProjectCode"
    $env:MSFPROJECTCODE = $ProjectCode
    Write-Host "> Updating registry string: FIELDOCB$ProjectCode"
    $GlpiRegModify = New-ItemProperty -Path $GlpiRegPath -PropertyType String -Name "tag" -Value "FIELDOCB$ProjectCode" -Force
    $GlpiUpdatedPath = (($GlpiRegModify.PSPath).ToString()) -Replace "M.*::",""
    Write-Host "> Updated the following key: `n  path = $GlpiUpdatedPath`n  String value: tag= $($GlpiRegModify.tag)"
    # Restart GLPI service after modifying values
    Write-Host "> Restarting GLPI service..."
    Get-Service "*fusion*","*glpi*" | Restart-Service -Force
    # Wait 9 seconds as glpi needs 6 seconds to complete restart
    Start-Sleep -Seconds 9
    # Initiate forced refresh of updated config to server
    Write-Host "> Sending updated values to GLPI server..."
    $GlpiWebRequest = Invoke-WebRequest -Uri $GlpiPushUri -UseBasicParsing
    $WebResultCode = $GlpiWebRequest.StatusCode
    $WebResultDscp = $GlpiWebRequest.StatusDescription
    Write-Host "> Web request push update returned code: $WebResultCode,`n> Description: $WebResultDscp`n`nOperation completed successfully"
}
Else {
    Write-Output "No project code is assigned to $DeviceSN"
}
exit 0
Stop-Transcript | Out-Null
