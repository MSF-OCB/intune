#
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
# Author: Omar Assaf
# X: omar_assaf
#
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
# Please credit the author if you use this script
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
#
# This script will upload Hardware Hash for Autopilot devices
# You will be requested to sign in with you Admin Account
#
#  1-Check internet connectivity
#  2-Check the name of the device
#  3-Upload the hardware hash ID
#
if (($env:computername -ilike "OCB-*") -or ($env:computername -ilike "OCBL*")) {
    Write-Host "`n$env:computername meets OCB naming convention, proceeding...`n" -Foreground Green -BackgroundColor Black
    if (Test-Connection 1.1.1.1 -Quiet -ErrorAction SilentlyContinue){
        Write-Host "Computer can access internet. `n" -Foreground Green -BackgroundColor Black
        # Define Group TAG & Name
        $GroupTag = "OCB-APPP"
        #Allowing remote signed scripts
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
        Write-Host "Installing NuGet package manager" -foreground green
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -Confirm:$false -Force:$true > $null
        Install-Module WindowsAutopilotIntune -Confirm:$false -Force:$true > $null
        Write-Host "Downloading Autpilotinfo script`n" -foreground green
        Install-Script -Name Get-WindowsAutopilotInfo -Confirm:$false -Force:$true
        # Add path variable so it doesnt through error of unrecognized command
        $env:Path += ";C:\Program Files\WindowsPowerShell\Scripts" 
        Write-Host "Trying to upload HardwareHash ID with following details:`n  Device Name: $env:computername `n  Group TAG: $GroupTag" -foreground Yellow
        Get-WindowsAutopilotInfo.ps1 -Online -GroupTag "$GroupTag" -AssignedComputerName "$env:computername"
        Write-Host "`nCOMPLETED" -foreground green
    }
    else {
        Write-Host "You are OFFLINE, troubleshoot your internet connectivity"
    }
}
else {
    Write-Host "Computer Name must meet OCB naming convention before proceeding." -Foreground Red -BackgroundColor Black
    Write-Host "Once computername is set properly, the process will continue automatically.`n" -Foreground Magenta -BackgroundColor Black
    Write-Host "Instructions: Computer Asset name must contain ONLY:" -Foreground Magenta -BackgroundColor Black
    Write-Host "* OCBL prefix is added automatically, don not add it. `n* 12 characters max. `n* Upper Case Letters or Numbers ONLY. `n* No special characters or space." -Foreground Yellow -BackgroundColor Black
    Do {
        try {
            [ValidatePattern("^[A-Z0-9]{1,12}$", Options = 'None')]$DeviceNameInput = Read-Host "Enter computer asset (without OCBL)"
            Write-Host "Name meets OCB requirements = OCBL$DeviceNameInput" -ForegroundColor Green -BackgroundColor Black
            Read-Host -Prompt "`nWARNING - WARNING - WARNING`n`nComputer will RESTART after you press any key"
            Rename-Computer -NewName "OCBL$DeviceNameInput" -Force -Confirm:$false -Restart
            Write-Host "Proceeding with onboarding Intune Autopilot device `n" -ForegroundColor Cyan -BackgroundColor Black
        }
        catch {}
    } 
    until ($?)
}
