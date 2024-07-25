#
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
# Author: Omar Assaf
# X: omar_assaf
#
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
# Please credit the author if you use this script
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
#
# Autopilot Onboarding Script
# This will initiate some of the functions that might be required before Autopilot start
#
##############################################
# Start Transcripting
##############################################
#
#
Start-Transcript -path "C:\ProgramData\MSF\Logs\Autopilot_Onboard.log" -Confirm:$false -force -append | Out-Null
#
#
##############################################
# Time Zone setup
##############################################
#
# Author: Omar Assaf
# X: omar_assaf 
#
# Please credit the author for any modification/usage of this
# Time Zone update before autopilot starts
#
# Fetch current ISP timezone details using IPinfo
$IanaTz = (Invoke-RestMethod https://ipinfo.io/json -UseBasicParsing).timezone
# When calling https webservices make sure always to use TLS1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Reach out to where you have a list of timezones in IANA format and thier equivilant in Windows format
# List could be in CSV or JSON, it could be on Github or Bitbucket or Azure Blob
# Fetch the list into a variable and make sure its converted from a JSON
$tzlist = Invoke-RestMethod "https://msfocbshare.blob.core.windows.net/ict/timezones.json" -UseBasicParsing #| ConvertFrom-Json
# Create variable to store windows Time Zone matching IANA the ISP details
$WindowsSimilar = ($tzlist | Where-Object {$_.IANA -eq "$IanaTz"}).Windows
# Set the windows time according to equivlant of IANA with windows Time ID
Set-TimeZone -Id "$WindowsSimilar"
# Get windows Time Zone reference from fetched list
# Set Windows Auto Time Zone Updater service to start manually
Set-Service -Name "tzautoupdate" -StartupType Automatic -Confirm:$false
Write-Host "`nCurrent location is: $IanaTz, changing timezone to: $WindowsSimilar, with offset= $((Get-TimeZone -Id $WindowsSimilar).BaseUtcOffset).`n" -ForegroundColor Green
#
#
#
##############################################
# Folder Directory Configuration
##############################################
#
#
# Create the directories for MSF
$MSFCustomDirectories = @(
"C:\Program Files\_SpecialApps",
"C:\Program Files (x86)\_SpecialApps",
"C:\Program Files (x86)\MSF",
"C:\Program Files (x86)\MSF\MSF Maintenance", 
"C:\ProgramData\MSF\Logs",
"C:\TEMP",
"C:\Users\Default\Private Documents"
)
foreach ($Directory in $MSFCustomDirectories) {
        If (Test-Path $Directory){
                Write-Host "$Directory already exist." -ForegroundColor Cyan
        }
        else { New-Item -Path $Directory -ItemType Directory -Force
                Write-Host "$Directory was created." -ForegroundColor Green
        }
}
#
#
#
###############################################
# Configure GLPI Requirements
##############################################
#
#
$RegPathFusion = "HKLM:\SOFTWARE\FusionInventory-Agent"
$RegPath = "HKLM:\SOFTWARE\GLPI-Agent"
# Match computer serial number to project code
$DeviceSN = (Get-WmiObject -class win32_bios).SerialNumber
$ComputerList = Invoke-RestMethod -Method Get "https://msfocbshare.blob.core.windows.net/ict-sd/data/ComputerName.csv" -UseBasicParsing | ConvertFrom-Csv
$ProjectCode = ($ComputerList | where-object Serial -EQ $DeviceSN).Project
#
If ($null -ne $ProjectCode){
    # Set the System environment variables
    Write-Host "> Setting system environment variable to: $ProjectCode."
    [System.Environment]::SetEnvironmentVariable("MSFPROJECTCODE", $ProjectCode, "Machine")
    If (!(Test-Path $RegPath) -or !(Test-Path $RegPathFusion)){
        New-Item -Path $RegPath -ErrorAction SilentlyContinue
        New-Item -Path $RegPathFusion -ErrorAction SilentlyContinue
        Write-Host "`n> Completed Creating GLPI Registry entries.`n"
    }
    Write-Host "> Updating registry string tag to: FIELDOCB$ProjectCode."
    $GlpiRegModify = New-ItemProperty -Path $RegPath -PropertyType String -Name "tag" -Value "FIELDOCB$ProjectCode" -Force
    $RegModifyFusion = New-ItemProperty -Path $RegPathFusion -PropertyType String -Name "tag" -Value "FIELDOCB$ProjectCode" -Force
    $GlpiUpdatedPath = (($GlpiRegModify.PSPath).ToString()) -Replace "M.*::",""
    Write-Host "> Updated the following key: `n  Path = $GlpiUpdatedPath`n  tag = $($GlpiRegModify.tag)"
}
Else {
        Write-Output "No project code is assigned to $DeviceSN."
}
#
###############################################
# Environment variables Configuration
##############################################
#
#
# Set the environment variables values
$env:TEMP = "C:\TEMP"
$env:TMP = "C:\TEMP"
$env:MSFPROGS = "C:\Program Files (x86)\MSF"
$env:MSFOSVERSION = "INTUNE"
$env:MSFSECTION = "OCB"
$env:MSFLOGS = "C:\programdata\MSF\logs"
#
# Set the scope of the environment variables to SYSTEM
[System.Environment]::SetEnvironmentVariable("TEMP", $env:TEMP, "Machine")
[System.Environment]::SetEnvironmentVariable("TMP", $env:TMP, "Machine")
[System.Environment]::SetEnvironmentVariable("MSFPROGS", $env:MSFPROGS, "Machine")
[System.Environment]::SetEnvironmentVariable("MSFOSVERSION", $env:MSFOSVERSION, "Machine")
[System.Environment]::SetEnvironmentVariable("MSFSECTION", $env:MSFSECTION, "Machine")
[System.Environment]::SetEnvironmentVariable("MSFLOGS", $env:MSFLOGS, "Machine")
Write-Host "`nComputer Environment variables had been updated`n" -ForegroundColor Green
#
#
##############################################
# Download PDF Desktop
##############################################
#
#
#
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Webfile = 'https://msfocbshare.z6.web.core.windows.net/data/links.txt'
$CSV = Invoke-RestMethod -Uri $Webfile -UseBasicParsing | ConvertFrom-Csv
ForEach ($row in $CSV) {
$Address = $row.URL
$Folder = $row.Destination
Invoke-RestMethod -Method Get -Uri $Address -OutFile $Folder -UseBasicParsing
Write-Host "Downloading: $($Address.split('/')[5]) " -ForegroundColor Green
}
#
#
##############################################
# Local User Creation
##############################################
#
#
if (!(Get-localuser -Name "msfD0ct0r" -ErrorAction SilentlyContinue)){
New-LocalUser -Name "msfD0ct0r" -NoPassword
Write-Host "`nLocal account creation completed." -ForegroundColor Green
} else {Write-Host "`nLocal account "msfD0ct0r" already exist." -ForegroundColor Cyan}
#
#
##############################################
# Registry - Machine based Configuration
##############################################
#
#
# Enable Delivery Optimization Peer Selection (DNS-SD)
New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Force | New-ItemProperty -Name "DORestrictPeerSelectionBy" -PropertyType DWord -Value 2 -Force
#
#
# Disable network new location
New-Item "HKLM:\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff" -Force -ErrorAction Continue
#
#
# Disable pop-up "Could not reconnect all network drives"
New-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\NetworkProvider" -Name "RestoreConnection" -PropertyType DWord -Value "0" -Force -ErrorAction Continue
#
#
# Disable Fastboot
New-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value 0 -PropertyType DWord -Force -ErrorAction Continue
#
#
# Allow Print drivers installation by users
New-Item "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint" -Force | New-ItemProperty -Name "RestrictDriverInstallationToAdministrators" -PropertyType DWord -Value "0" -Force
#
#
# Configure PDF Switching Handler
# New-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "DisablePDFHandlerSwitching" -PropertyType String -Value "1" -Force -ErrorAction Continue
#
# Configure Organization registered
New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "RegisteredOwner" -PropertyType String -Value "MSFOCB IT Department" -Force -ErrorAction Continue
New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "RegisteredOrganization" -PropertyType String -Value "MSFOCB" -Force -ErrorAction Continue
#
#
# Config Organization info
New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" -Name "SupportPhone" -PropertyType String -Value "444" -Force -ErrorAction Continue 
New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" -Name "SupportHours" -PropertyType String -Value "09:00 - 16:00" -Force -ErrorAction Continue
New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" -Name "SupportURL" -PropertyType String -Value "https://myhelp.brussels.msf.org" -Force -ErrorAction Continue
#Copy-Item "$installFolder\$($config.Config.OEMInfo.Logo)" "C:\Windows\OEMInfo.Logo)" -Force
#reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v Logo /t REG_SZ /d "C:\Windows\OEMInfo.Logo)" /f /reg:64 | Out-Host
#
#
##############################################
# Registry - Default Profile Configuration
##############################################
#
#
# Load default profile registry so we can modify
reg.exe load "HKLM\User0" "C:\Users\Default\NTUSER.DAT"

#
#
# SearchBox taskbar for default user profile
New-Item -Path "HKLM:\User0\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Force -ErrorAction Continue
New-ItemProperty "HKLM:\User0\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchBoxTaskbarMode" -PropertyType DWORD -Value 1 -Force -ErrorAction Continue
New-ItemProperty "HKLM:\User0\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchBoxTaskbarModePrevious" -PropertyType DWORD -Value 1 -Force -ErrorAction Continue
New-ItemProperty "HKLM:\User0\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "TraySearchBoxVisible" -PropertyType DWORD -Value 0 -Force -ErrorAction Continue
New-ItemProperty "HKLM:\User0\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "TraySearchBoxVisibleOnAnyMonitor" -PropertyType DWORD -Value 0 -Force -ErrorAction Continue
New-ItemProperty "HKLM:\User0\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "OnboardSearchboxOnTaskbar" -PropertyType DWORD -Value 2 -Force -ErrorAction Continue
#
# Enable Numlock before login
New-ItemProperty "HKLM:\User0\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -PropertyType String -Value "2" -Force -ErrorAction Continue
New-ItemProperty "Registry::HKU\.DEFAULT\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -PropertyType String -Value "2147483650" -Force -ErrorAction Continue
#
# Show file extension
New-ItemProperty "HKLM:\User0\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -PropertyType DWORD -Value 0 -Force -ErrorAction Continue
# Enable show file extension for all Users
#
Start-Sleep -Seconds 5
# Unload the default registery
[gc]::Collect()
reg.exe unload "HKLM\User0"
Write-Host "`nCleaning and unloading hive completed" -ForegroundColor Green

#
#
#
##############################################
# Windows Bloatware removal
##############################################
#
#
# Use windiws capabilities to remove older QuickAssist
$WinVer = (Get-CimInstance Win32_OperatingSystem).version
If ($WinVer -lt 10.0.2){
        $QuickAssistStat = Get-WindowsCapability -online -Name *QuickAssist*
        If ($QuickAssistStat.State -eq 'Installed') {
                Remove-WindowsCapability -Online -Name $QuickAssistStat.name -ErrorAction Continue
        }else {Write-Host "Quick assist is not installed." -ForegroundColor Cyan}
}else {Write-Host "`nYou are running Win 11, uninstalltion of Quick Assist will be via AppxPackages.`n" -ForegroundColor Cyan}
#
#
# Specify windows Appx builtin to be removed
#
$AppUrl = "https://raw.githubusercontent.com/MSF-OCB/intune/main/Scripts/Bloatware/AppList.txt"
$AppListContent = Invoke-RestMethod -Uri $AppUrl -UseBasicParsing
$AppListArray = $AppListContent -split "`n" -ne ''
# Proceed to remove each of the applications listed
foreach ($Appx in $AppListArray ) {
    if (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $Appx -ErrorAction Continue) {
            Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $Appx | Remove-AppxProvisionedPackage -Online
            Write-Host "Removed provisioned package for $Appx." -ForegroundColor Green
    } else {
            Write-Host "Provisioned package for $Appx not found." -ForegroundColor Cyan
            }  
    if (Get-AppxPackage -Name $Appx -ErrorAction SilentlyContinue) {
        Get-AppxPackage -allusers -Name $Appx | Remove-AppxPackage -AllUsers
        Write-Host "Removed $Appx." -ForegroundColor Green
    } else {
        Write-Host "$Appx not found." -ForegroundColor Cyan
        }
}
#
#
#
Write-Host "`nAutopilot onboarding is completed." -ForegroundColor Green
#
#
#*********************************************
# Sop Transcripting
#*********************************************
#
#
Stop-Transcript | Out-Null
#
