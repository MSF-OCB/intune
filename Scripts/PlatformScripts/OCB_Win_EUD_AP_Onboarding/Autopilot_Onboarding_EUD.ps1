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
#
# Autopilot Onboarding Script
# This will initiate some of the functions that might be required during Autopilot phase.
#
##############################################
# Variables and Constants and definitions
##############################################
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$OCBAutoPilotRegPath = 'HKLM:\SOFTWARE\MSFOCB\Autopilot'
$TimeZoneUrlProvider = "https://ident.me/json"
#
#
###############################################
# Function Definitions
##############################################
# Log Function
function log() {
    param (
        [Parameter(Mandatory=$True)]
        [string]$message
    )
    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "$date - $message"
}
#
##############################################
# Check Autopilot Onboarding Status
##############################################
# Declare Microsoft Tenant ID for Autopilot detection
$Msftenant = "4d9dd1af-83ce-4e9b-b090-b0543ccc2b31"
$TenantId = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\AutoPilot" -ErrorAction SilentlyContinue ).CloudAssignedTenantId
if ($TenantId -ne $Msftenant) {
    log "Device is NOT Autopilot. Cannot run Onboarding for this device."
    Exit 0
}

# Check if Autopilot onboarding has already been completed
if (Test-Path -Path $OCBAutoPilotRegPath) {
    $ApOnbordProps = Get-ItemProperty $OCBAutoPilotRegPath -ErrorAction SilentlyContinue    
    if ($ApOnbordProps.PSObject.Properties.Name -contains 'AutopilotOnboardingScriptStatus') {
            $AutopilotOnboardingStatus = $ApOnbordProps.AutopilotOnboardingScriptStatus
        if ($AutopilotOnboardingStatus -eq 1) {
            log "Autopilot onboarding has already been completed previously. Exiting script."
            exit 0
        }
    }
}

log "Autopilot onboarding is starting as no previous status found."
#
#
##############################################
# Start Transcripting
##############################################
#
Start-Transcript -path "C:\ProgramData\MSF\Logs\Intune\Scripts\Autopilot_Onboard.log" -Confirm:$false -force -append | Out-Null
#
#
##############################################
# Time Zone setup
##############################################
# Fetch current ISP timezone details using IPinfo
$IanaTz = (Invoke-RestMethod $TimeZoneUrlProvider -UseBasicParsing).tz
# Reach out to where you have a list of timezones in IANA format and thier equivilant in Windows format
# List could be in CSV or JSON, it could be on Github or Bitbucket or Azure Blob Storage
$tzlist = Invoke-RestMethod "https://msfocbshare.blob.core.windows.net/ict/timezones.json" -UseBasicParsing #| ConvertFrom-Json
# Create variable to store windows Time Zone matching IANA the ISP details
$WindowsSimilar = ($tzlist | Where-Object {$_.IANA -eq "$IanaTz"}).Windows
# Set the windows time according to equivlant of IANA with windows Time ID
[CultureInfo]::CurrentCulture.ClearCachedData()
Set-TimeZone -Id "$WindowsSimilar"
[CultureInfo]::CurrentCulture.ClearCachedData()
# Get windows Time Zone reference from fetched list
# Set Windows Auto Time Zone Updater service to start manually
Set-Service -Name "tzautoupdate" -StartupType Automatic -Confirm:$false
Restart-Service -Name "W32Time" -Force #-ErrorAction SilentlyContinue
Restart-Service -Name "lfsvc" -Force #-ErrorAction SilentlyContinue
#Restart-Service -Name "NlaSvc" -Force #-ErrorAction SilentlyContinue
log "All relevant services have been checked, configured, and started if necessary."
# Resync time
w32tm /resync /force | Out-Null
[CultureInfo]::CurrentCulture.ClearCachedData()
$CurrentTimeZone =  tzutil /g
log "Current Time Zone: $CurrentTimeZone."
log "Current location is: $IanaTz."
log "Changing timezone to: $WindowsSimilar, with offset= $((Get-TimeZone -Id $WindowsSimilar).BaseUtcOffset).`n"
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
"C:\ProgramData\MSF\Logs\Intune",
"C:\TEMP",
"C:\Users\Default\Private Documents"
)
foreach ($Directory in $MSFCustomDirectories) {
        If (Test-Path $Directory){
                log "$Directory already exist."
        }
        else { New-Item -Path $Directory -ItemType Directory -Force > $null
                log "$Directory was created."
        }
}
"`n"
#
#
###############################################
# Folder Permissions Configuration
##############################################
#
#
# Set read-write permissions for Everyone on the folder and subfolders
$MSFDirPerm = @(
    "C:\Program Files\_SpecialApps",
    "C:\Program Files (x86)\_SpecialApps"
)

foreach ($folder in $MSFDirPerm) {
    icacls $folder /grant "Users:(OI)(CI)F" /T | Out-Null
    log "Set permissions for $folder"
}
"`n"
#
#
###############################################
# Configure GLPI Requirements
##############################################
#
#
$RegPathGlpi = "HKLM:\SOFTWARE\GLPI-Agent"
# Match computer serial number to project code
$DeviceSN = (Get-WmiObject -class win32_bios).SerialNumber
$ComputerList = Invoke-RestMethod -Method Get "https://msfocbshare.blob.core.windows.net/ict-sd/data/ComputerName.csv" -UseBasicParsing | ConvertFrom-Csv

# Get the project code that corresponds to current device
$ProjectCode = ($ComputerList | where-object Serial -EQ $DeviceSN).Project
#
If ($null -ne $ProjectCode){
    # Set the System environment variables
    log "Setting system environment variable to: $ProjectCode."
    [System.Environment]::SetEnvironmentVariable("MSFPROJECTCODE", $ProjectCode, "Machine")
    If (!(Test-Path $RegPathGlpi)){
        New-Item -Path $RegPathGlpi -ErrorAction SilentlyContinue
        log "Completed Creating GLPI Registry entries."
    }
    log "Updating registry string tag to: FIELDOCB$ProjectCode."
    $GlpiRegModify = New-ItemProperty -Path $RegPathGlpi -PropertyType String -Name "tag" -Value "FIELDOCB$ProjectCode" -Force
    $GlpiUpdatedPath = (($GlpiRegModify.PSPath).ToString()) -Replace "M.*::",""
    log "Updated the following key: `n     Path = $GlpiUpdatedPath`n     tag = $($GlpiRegModify.tag)"
}
Else {
        log "No project code is assigned to: $DeviceSN."
}
"`n"
#
#
###############################################
# Environment variables Configuration
##############################################
#
#
log "Updating System Environment variables..."
# Set the environment variables values
$env:TEMP = "C:\TEMP"
$env:TMP = "C:\TEMP"
$env:MSFPROGS = "C:\Program Files (x86)\MSF"
$env:MSFOSVERSION = "AUTOPILOT"
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
log "System Environment variables had been updated.`n"
#
#
##############################################
# Download PDF Desktop
##############################################
#
#
# TLS 1.2 enforcement in global variable
$Webfile = 'https://msfocbshare.z6.web.core.windows.net/data/links.txt'
$CSV = Invoke-RestMethod -Uri $Webfile -UseBasicParsing | ConvertFrom-Csv
ForEach ($row in $CSV) {
$Address = $row.URL
$Folder = $row.Destination
Invoke-RestMethod -Method Get -Uri $Address -OutFile $Folder -UseBasicParsing | Out-Null
log "Downloading: $($Address.split('/')[5]) "
}
"`n"
#
#
##############################################
# Local User Creation
##############################################
#
<#
if (!(Get-localuser -Name "msfD0ct0r" -ErrorAction SilentlyContinue)){
New-LocalUser -Name "msfD0ct0r" -NoPassword
Add-LocalGroupMember -Group "Administrators" -Member "msfD0ct0r"
log "Local account creation completed."
}
else {log "Local account msfD0ct0r already exist."}
"`n"
#>
#
##############################################
# Registry - Machine based Configuration
##############################################
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
# Enable Office to save to Computer by default
New-Item -Path "HKLM:\User0\Software\Microsoft\Office\16.0\Common\General" -Force -ErrorAction Continue
New-ItemProperty "HKLM:\User0\Software\Microsoft\Office\16.0\Common\General" -Name "PreferCloudSaveLocations" -PropertyType DWORD -Value 0 -Force -ErrorAction Continue
#
# Enable show file extension for all Users
New-ItemProperty "HKLM:\User0\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -PropertyType DWORD -Value 0 -Force -ErrorAction Continue
#
Start-Sleep -Seconds 5
# Unload the default registry
[gc]::Collect()
reg.exe unload "HKLM\User0"
log "Cleaning and unloading hive completed"
"`n"
#
#
##############################################
# Windows Bloatware removal
##############################################
#
#
# Use Windows capabilities to remove older QuickAssist
# not needed on Win11 as it is Appx based
<#
$WinVer = (Get-CimInstance Win32_OperatingSystem).version
If ($WinVer -lt 10.0.2){
        $QuickAssistStat = Get-WindowsCapability -online -Name *QuickAssist*
        If ($QuickAssistStat.State -eq 'Installed') {
                Remove-WindowsCapability -Online -Name $QuickAssistStat.name -ErrorAction Continue
                log "Quick assist was uninstalled."
        }else {log "Quick assist is not installed."}
}else {log "You are running Win 11, uninstalltion of Quick Assist will be via AppxPackages."}
#
#>
#
# Specify windows Appx builtin to be removed
#
$AppUrl = "https://raw.githubusercontent.com/MSF-OCB/intune/main/Scripts/Bloatware/AppList.txt"
#$AppUrl = "https://github.com/MSF-OCB/intune/raw/refs/heads/main/Scripts/Bloatware/AppList.txt"
$AppListContent = Invoke-RestMethod -Uri $AppUrl -UseBasicParsing
$AppListArray = $AppListContent -split "`n" -ne ''
# Proceed to remove each of the applications listed
foreach ($Appx in $AppListArray ) {
    if (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $Appx -ErrorAction Continue) {
            Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $Appx | Remove-AppxProvisionedPackage -Online -AllUsers
            log "Removed provisioned system package: $Appx."
    } else {
            log "Provisioned system package: $Appx not found."
            }  
    if (Get-AppxPackage -Name $Appx -AllUsers -ErrorAction SilentlyContinue) {
        Get-AppxPackage -AllUsers -Name $Appx | Remove-AppxPackage -AllUsers
        log "Removed Appx user package: $Appx."
    } else {
        log "Appx user package: $Appx not found."
        }
}
"`n"
#
#
try {
    # Ensure key exists
    # $dateStr = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')  # ISO 8601 with offset
    $dateStr = (Get-Date).ToString('yyyy-MM-dd_HH:mm:ss')
    $statusValue = 1
    New-Item -Path $OCBAutoPilotRegPath -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $OCBAutoPilotRegPath -Name 'AutopilotOnboardingScriptStatus' `
                        -Value $statusValue -PropertyType DWord -Force -ErrorAction Stop | Out-Null

    New-ItemProperty -Path $OCBAutoPilotRegPath -Name 'AutopilotOnboardingScriptDate' `
                        -Value $dateStr -PropertyType String -Force -ErrorAction Stop | Out-Null
    log "Successfully wrote Autopilot registry values."
}
catch {
    Write-Warning "Failed to write Autopilot registry values: $($_.Exception.Message)"
}
#
#
#
"`n"
log "Autopilot onboarding is completed."
#
#
#*********************************************
# Stop Transcripting
#*********************************************
Stop-Transcript | Out-Null
#
