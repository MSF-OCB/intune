## ==========================================================================
## MSFOCB Script
##
## --------------------------------------------------------------------------
## Filename   : Firefox_Detection_Process.ps1
## Version         : 1.0
## Creation Date   : 20-02-2025
## Last Update     : -
## --------------------------------------------------------------------------
## Software name    : 
## Software version : 
## Official site    : 
## --------------------------------------------------------------------------
## Description      :
##   -  Silenty installation
## --------------------------------------------------------------------------
## Requirements     : 
##   -  
##   -  
## --------------------------------------------------------------------------
## Resources        :
##   - https://www.mozilla.org/en-US/firefox/enterprise/
##   -
## --------------------------------------------------------------------------
## Script's Author    : Fabrizio.Murgia@brussels.msf.org
## Contacts           : Contact MSFOCB ICT Support for information ("dr.watson@brussels.msf.org")
## --------------------------------------------------------------------------
## Notes : 
## - Windows application set-ups unattended : "http://unattended.sourceforge.net/installers.php"
## - Windows Installer (MSI)                : "https://docs.microsoft.com/en-us/windows/desktop/msi/command-line-options"
## - NSIS Installer                         : "http://nsis.sourceforge.net/Docs/Chapter3.html#installerusage"
## - InnoSetup Installer                    : "http://jrsoftware.org/ishelp/index.php?topic=setupcmdline"
##
## ==========================================================================

#### -==- MAIN -==- ####

# Set up PowerShell parameters
Set-PSDebug -Trace 0    # 0 - 1 - 2
Set-StrictMode -Version 3

# Retrive the path from where the script has been run and put it in the $MyPath variable
$MyPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$_ALLUSERSPROFILE = ${Env:ALLUSERSPROFILE}

## ::::::::::::::::::::::::::::::::::::::

# 1. Detect all previous versions installed on HQ or Field Machines to avoid that a local IT install Firefox  manually without our customization

write-Output "Detection process for all older versions is starting now ...."

# Get all installed applications from the registry
$installedApps = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue
$installedApps += Get-ItemProperty -Path "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue

# Filter for Fireofox products
$FirefoxInfoProducts = $installedApps | Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like "*Firefox*" }

if ($FirefoxInfoProducts) {
    write-output "Firefox has been found into the machine"
     # Return Fireofx products properties. if you need ALL properties use * instead of Publisher,UninstallString,DisplayName,DisplayVersion
     $FirefoxInfoProducts | Format-list -Property Publisher, UninstallString, PSPath, PSChildName, DisplayName, DisplayVersion
     exit 1
} else {
    write-output "Firefox has not been detected into the machine"
    exit 0
}

## :::::::::::: -- EOF -- ::::::::::::##

