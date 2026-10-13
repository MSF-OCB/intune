#
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
# Author: Omar Assaf
# X: omar_assaf
#
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
# Please credit the author if you use this script
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
#
# This script will detect if a project code is assigned to device
# Will check Device SN in the list and corresponding Code at Reg & Env
# It includes different clear output messages over what is missing
#
# ^**^**^**^**^**^**^**^**
# Declare variables
# ^**^**^**^**^**^**^**^**
#
$Transcript = "C:\ProgramData\MSF\Logs\GLPI_Project_Detection.log"
Start-Transcript -Path $Transcript | Out-Null
# Reg path for either Fusion or GLPI, comment the one that your do NOT use
$RegPath = "HKEY_LOCAL_MACHINE\SOFTWARE\GLPI-Agent"
$ProjEnv = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name "MSFPROJECTCODE" -ErrorAction SilentlyContinue).MSFPROJECTCODE
# get device SN
$DeviceSN = (Get-WmiObject -class win32_bios).SerialNumber
# URL to fetch computer list CSV
$URI = "https://msfocbshare.blob.core.windows.net/ict-sd/data/ComputerName.csv"
# Fetch computer list data
$bytes = Invoke-WebRequest -Uri $URI -UseBasicParsing -Method Get | Select-Object -ExpandProperty Content
# Remove UTF-8 BOM if present (very safe - only removes if it really exists)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $bytes = $bytes[3..($bytes.Length-1)]
}
# Now convert bytes → string → objects
$ComputerListAsText = [System.Text.Encoding]::UTF8.GetString($bytes)
$ComputerList = $ComputerListAsText | ConvertFrom-Csv -ErrorAction Stop

# get data related to current SN
$DeviceData = $ComputerList | where-object Serial -EQ $DeviceSN
if ($null -ne $DeviceData){
    #get the project code that corresponds to current device
    $Project = $DeviceData.Project
    Write-Host "Device SN is available at the Computer list."
    if($null -ne $Project){
        Write-Host "Project code $Project is assigned to $DeviceSN"
        $RegKeyValue = (Get-ItemProperty -Path Registry::$RegPath -ErrorAction SilentlyContinue).tag
        if ($null -ne $RegKeyValue){
            if (($RegKeyValue.Length -gt 8) -and ($RegKeyValue.Substring(8) -eq $Project)) {
                Write-Host "Device is assigned same project code at Registry Key level"
                if ($ProjEnv -eq $RegKeyValue.substring(8)){
                    Write-Host " > Good, Device is assigned correct project code at all variables."
                    Stop-Transcript | Out-Null; Exit 0
                }else {Write-Host "Wrong project code at System Environment level"; Stop-Transcript | Out-Null; Exit 1}
            }else {Write-Host "Wrong project code at Registry Key level, it will be updated."; Stop-Transcript | Out-Null; Exit 1}
        }else {Write-Host "Registry key that belongs to Project Code is missing, it will be added & updated."; Stop-Transcript | Out-Null; Exit 1}
    }else {Write-Host "Project Code is missing from $DeviceSN, please add Project!"; Stop-Transcript | Out-Null; Exit 0}
}else {Write-Host "$DeviceSN is missing in the Computer List, please add SN & Project!"; Stop-Transcript | Out-Null; Exit 0}
