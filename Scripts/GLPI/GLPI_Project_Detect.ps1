#
###################################################
# Author: Omar Assaf
# X: omar_assaf
#
###################################################
# Please credit the author if you use this script
###################################################
# This script will detect if a project code is assigned to device
# It includes different clear output messages over what is missing
#
# # # # # # # # # # # #
# Declare variables
# # # # # # # # # # # #
#
$Transcript = "C:\ProgramData\MSF\Logs\GLPI_Project_Detection.log"
Start-Transcript -Path $Transcript | Out-Null
$RegPath = "HKEY_LOCAL_MACHINE\SOFTWARE\GLPI-Agent"
$ProjEnv = [System.Environment]::GetEnvironmentVariable("MSFPROJECTCODE")
# get device SN
$DeviceSN = (Get-WmiObject -class win32_bios).SerialNumber
# Fetch computer list data
$ComputerList = Invoke-RestMethod -Method Get "
https://msfocbshare.blob.core.windows.net/ict-sd/data/ComputerName.csv"
-UseBasicParsing | ConvertFrom-Csv
# get data related to current SN
$DeviceData = $ComputerList | where-object Serial -EQ $DeviceSN
if ($null -ne $DeviceData){
    #get the project code that corresponds to current device
    $Project = $DeviceData.Project
    Write-Host "Device SN is found in Computer list"
    if($null -ne $Project){
        Write-Host "Project code is assigned to $DeviceSN"
        $RegKeyValue = (Get-ItemProperty -Path Registry::$RegPath -ErrorAction SilentlyContinue).tag
        if ($null -ne $RegKeyValue){
            if ($RegKeyValue.substring(8) -eq $Project) {
                Write-Host "Device is assigned same project code at Registry Key level"
                if ($ProjEnv -eq $RegKeyValue.substring(8)){
                    Write-Host " > Good, Device is assigned correct project code at all variables."
                    Stop-Transcript | Out-Null; Exit 0
                }else {Write-Host "Wrong project code at System Environment level"; Stop-Transcript | Out-Null | Out-Null; Exit 1}
            }else {Write-Host "Wrong project code at Registry Key level"; Stop-Transcript | Out-Null; Exit 1}
        }else {Write-Host "Registry key value equivalent to Project Code is empty, it will be updated."; Stop-Transcript | Out-Null; Exit 0}
    }else {Write-Host "No project Code assigned to $DeviceSN, please update it!"; Stop-Transcript | Out-Null; Exit 0}
}else {Write-Host "$DeviceSN is missing in the Computer List, please update it!"; Stop-Transcript | Out-Null; Exit 0}
