#
#
# Author: Omar Assaf
# X: omar_assaf 
#
# Please credit the author for any modification/usage of this script :)
#
# Autopilot Onboarding Script
# Designed by Omar Assaf
#
#
##############################################
# Start Transcripting
##############################################
#
#
Start-Transcript -path ((New-Item -Path "C:\ProgramData\MSF\Logs" -ItemType Directory -Force).FullName + '\Autopilot_Onboard.log') -Confirm:$false -append -force > $null
#
#
#
##############################################
# Time Zone setup
##############################################
#
# Author: Omar Assaf
# X: omar_assaf 
#
# Please credit the author for any modification/usage of this script :)
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
Write-Host "Current setup location is: $IanaTz, changing timezone to: $WindowsSimilar, with offset= $((Get-TimeZone -Id $WindowsSimilar).BaseUtcOffset)."
#
#
#
##############################################
# Folder Directory Configuration
##############################################
#
#
# Create the directories for MSF
New-Item -Path "C:\Program Files\_SpecialApps" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\Program Files (x86)\_SpecialApps" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\Program Files (x86)\MSF" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\Program Files (x86)\MSF\MSF Maintenance" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\ProgramData\MSF\Logs" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\" -Name "TEMP" -ItemType Directory -ErrorAction Continue
New-Item -Path "C:\Users\Default\Private Documents" -ItemType Directory -Force | Out-Null
Write-Host "Directories had been created"
#
#
#
###############################################
# Environment variables Configuration
##############################################
#
#
# Set environment variables
# Set the scope of the environment variables to SYSTEM
[System.Environment]::SetEnvironmentVariable("TEMP", $env:TEMP, "Machine")
[System.Environment]::SetEnvironmentVariable("TMP", $env:TMP, "Machine")
[System.Environment]::SetEnvironmentVariable("MSFPROGS", $env:MSFPROGS, "Machine")
[System.Environment]::SetEnvironmentVariable("MSFOSVERSION", $env:MSFOSVERSION, "Machine")
[System.Environment]::SetEnvironmentVariable("MSFSECTION", $env:MSFSECTION, "Machine")
[System.Environment]::SetEnvironmentVariable("MSFLOGS", $env:MSFLOGS, "Machine")
# Set the environment variables
$env:TEMP = "C:\TEMP"
$env:TMP = "C:\TEMP"
$env:MSFPROGS = "C:\Program Files (x86)\MSF"
$env:MSFOSVERSION = "INTUNE"
$env:MSFSECTION = "OCB"
$env:MSFLOGS = "C:\programdata\MSF\logs"
Write-Host "Computer Environment variables had been updated"
#
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
Write-Host "Downloading: $($Address.split('/')[5]) "
}
#
#
##############################################
# Local User Creation
##############################################
#
#
New-LocalUser -Name "msfD0ct0r" -NoPassword | Out-Null
Write-Host "Local account creation completed"
#
#
#
##############################################
# Registry - Machine based Configuration
##############################################
#
#
#
# Disable network new location
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff" -Force -ErrorAction Continue | Out-Null
#
#
# Disable pop-up "Could not reconnect all network drives"
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\NetworkProvider" -Name "RestoreConnection" -PropertyType DWord -Value "0" -Force -ErrorAction Continue | Out-Null
#
#
# Disable Fastboot
New-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value 0 -PropertyType DWord -Force -ErrorAction Continue | Out-Null
#
#
# Configure PDF Switching Handler
# New-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "DisablePDFHandlerSwitching" -PropertyType String -Value "1" -Force -ErrorAction Continue | Out-Null
#
# Configure Organization registered
New-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "RegisteredOwner" -PropertyType String -Value "MSFOCB IT Department" -Force -ErrorAction Continue | Out-Null
New-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "RegisteredOrganization" -PropertyType String -Value "MSFOCB" -Force -ErrorAction Continue | Out-Null
#
#
# Config Organization info
New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" -Name "SupportPhone" -PropertyType String -Value "444" -Force -ErrorAction Continue | Out-Null 
New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" -Name "SupportHours" -PropertyType String -Value "09:00 - 16:00" -Force -ErrorAction Continue | Out-Null
New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" -Name "SupportURL" -PropertyType String -Value "https://myhelp.brussels.msf.org" -Force -ErrorAction Continue | Out-Null
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
reg.exe load HKLM\User0 "C:\Users\Default\NTUSER.DAT" | Out-Null
#
#
# SearchBox taskbar for default user profile
New-Item -Path "HKLM:\User0\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Force -ErrorAction Continue | Out-Null
New-ItemProperty "HKLM:\User0\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchBoxTaskbarMode" -PropertyType DWORD -Value 1 -Force -ErrorAction Continue | Out-Null
New-ItemProperty "HKLM:\User0\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchBoxTaskbarModePrevious" -PropertyType DWORD -Value 1 -Force -ErrorAction Continue | Out-Null
New-ItemProperty "HKLM:\User0\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "TraySearchBoxVisible" -PropertyType DWORD -Value 0 -Force -ErrorAction Continue | Out-Null
New-ItemProperty "HKLM:\User0\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "TraySearchBoxVisibleOnAnyMonitor" -PropertyType DWORD -Value 0 -Force -ErrorAction Continue | Out-Null
New-ItemProperty "HKLM:\User0\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "OnboardSearchboxOnTaskbar" -PropertyType DWORD -Value 2 -Force -ErrorAction Continue | Out-Null
#
# Enable Numlock before login
New-ItemProperty "HKLM:\User0\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -PropertyType String -Value "2" -Force -ErrorAction Continue | Out-Null
New-ItemProperty "Registry::HKU\.DEFAULT\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -PropertyType String -Value "2147483650" -Force -ErrorAction Continue | Out-Null
#
# Show file extension
New-ItemProperty "HKLM:\User0\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -PropertyType DWORD -Value 0 -Force -ErrorAction Continue | Out-Null
# Enable show file extension for all Users
#
Start-Sleep -Seconds 5
# Unload the default registery
[gc]::Collect()
reg.exe unload "HKLM\User0" | Out-Null
#
#
#
################################################
# Registry - Current User profile Configuration
################################################
<#
#
#
# Get the current user
$UserSID = [System.Security.Principal.WindowsIdentity]::GetCurrent().user.Value
Write-Host "$UserSID is runing currently logged"
#
# you can use PSDrive to load HKU but
New-PSDrive -Name HKU -PSProvider Registry -Confirm:$false -Root HKEY_USERS | Out-Null
#
# Enable Num Lock
New-ItemProperty "Registry::HKU\$UserSID\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -PropertyType String -Value "2" -Force -ErrorAction Continue | Out-Null
#
# SearchBox taskbar for logged user
New-ItemProperty "Registry::HKU\$UserSID\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchBoxTaskbarMode" -PropertyType DWORD -Value 1 -Force -ErrorAction Continue | Out-Null
New-ItemProperty "Registry::HKU\$UserSID\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchBoxTaskbarModePrevious" -PropertyType DWORD -Value 1 -Force -ErrorAction Continue | Out-Null
New-ItemProperty "Registry::HKU\$UserSID\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "TraySearchBoxVisible" -PropertyType DWORD -Value 0 -Force -ErrorAction Continue | Out-Null
New-ItemProperty "Registry::HKU\$UserSID\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "TraySearchBoxVisibleOnAnyMonitor" -PropertyType DWORD -Value 0 -Force -ErrorAction Continue | Out-Null
New-ItemProperty "Registry::HKU\$UserSID\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "OnboardSearchboxOnTaskbar" -PropertyType DWORD -Value 2 -Force -ErrorAction Continue | Out-Null
# 
# Enable show file extension per the current user 
New-ItemProperty "Registry::HKU\$UserSID\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -PropertyType DWORD -Value "0" -Force | Out-Null
#
# Add Numlock on logon
# https://winaero.com/enable-numlock-logon-screen-windows-10/#Enable_NumLock_on_Login_Screen
New-ItemProperty "Registry::HKU\.DEFAULT\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -PropertyType String -Value "2147483650" -Force -ErrorAction Continue | Out-Null
#
#
# Remove the HKU PSDrive
Remove-PSDrive -Name HKU -Force -Confirm:$false
#
#>
##############################################
# Windows Bloatware removal
##############################################
#
#
#
# Specify windows Appx builtin to be removed
$AppsRemovable = @(
"Microsoft.Xbox.TCUI"
"Microsoft.XboxApp"
"Microsoft.GetHelp"
"Microsoft.XboxGameOverlay"
"Microsoft.XboxGamingOverlay"
"Microsoft.XboxIdentityProvider"
"Microsoft.XboxSpeechToTextOverlay"
"Microsoft.windowscommunicationsapps"
"Microsoft.WindowsFeedbackHub"
"Microsoft.SkypeApp"
"Microsoft.People"
"Microsoft.MixedReality.Portal"
"Microsoft.MicrosoftSolitaireCollection"
"Microsoft.Getstarted"
"Microsoft.BingWeather"
)
foreach ($Appx in $AppsRemovable) {
    if (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $Appx -ErrorAction SilentlyContinue) {
            Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $Appx | Remove-AppxProvisionedPackage -Online
            Write-Host "Removed provisioned package for $Appx."
        } else {
            Write-Host "Provisioned package for $Appx not found."
            }  
    if (Get-AppxPackage -Name $Appx -ErrorAction SilentlyContinue) {
        Get-AppxPackage -allusers -Name $Appx | Remove-AppxPackage -AllUsers
        Write-Host "Removed $Appx."
        } else {
        Write-Host "$Appx not found."
        }
  
}
#
#
$LASTEXITCODE
#
Write-Host "`nAutopilot onboarding is completed."
#
#
#*********************************************
# Sop Transcripting
#*********************************************
#
#
Stop-Transcript > $null
