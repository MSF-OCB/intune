## ==========================================================================
## --------------------------------------------------------------------------
## Script's Author    : Fabrizio.Murgia@brussels.msf.org
## Contacts           : Contact MSFOCB ICT Support for information (dr.watson@brussels.msf.org)
<#
    Copyright (c) 2020-2050 Fabrizio Murgia. All rights reserved.

    This script is the intellectual property of Fabrizio Murgia.
    Unauthorized use, copying, modification, distribution, sell or publication of this script,
    in whole or in part, via any medium, is strictly prohibited without prior written permission.

    THE SCRIPT IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHOR BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
    ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
    WITH THE SCRIPT OR THE USE OR OTHER DEALINGS IN THE SCRIPT.
#>
## --------------------------------------------------------------------------
## ==========================================================================
## --------------------------------------------------------------------------
## Filename   : detection_method_for_WPS_Office.ps1
## Version         : 4.0
## Creation Date   : 10-04-26
## Last Update     : -
## --------------------------------------------------------------------------
## Software name    : 
## Software version : 
## Official site    : 
## --------------------------------------------------------------------------
## Description      :
##   -  Detection Method for DisplayName + Publisher + DisplayVersion
## --------------------------------------------------------------------------
## Requirements     : 
##   -  
##   -  
## --------------------------------------------------------------------------
## Resources        :
##   -
##   -
## --------------------------------------------------------------------------
## Notes : 
## - Windows application set-ups unattended : "http://unattended.sourceforge.net/installers.php"
## - Windows Installer (MSI)                : "https://docs.microsoft.com/en-us/windows/desktop/msi/command-line-options"
## - NSIS Installer                         : "http://nsis.sourceforge.net/Docs/Chapter3.html#installerusage"
## - InnoSetup Installer                    : "http://jrsoftware.org/ishelp/index.php?topic=setupcmdline"
## - WiX guide                              : "https://docs.firegiant.com/quick-start/"
##
## ==========================================================================

#### -==- MAIN -==- ####

# :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

# Set up PowerShell parameters
Set-PSDebug -Trace 0    # 0 = off; use 1 or 2 only for troubleshooting
Set-StrictMode -Version 3

# Retrieve the path from where the script has been run and put it in the $MyPath variable (preferred over Split-Path) 
$MyPath = $PSScriptRoot

# Environment variables are directly accessible when needed:
# $env:ALLUSERSPROFILE
# :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

## -- CUSTOM VARIABLES -- ##
# ---------------------------
$_AppName       = "WPS Office"
$_Producer      = "Kingsoft Corp."

# ==============================================================================================
# Global normalization helper (centralized)
# ==============================================================================================
function Format-Name {
    param ([string]$Text)

    if (-not $Text) { return "" }

    return (
        $Text -replace '[\u00A0\s]+', ' '
    ).ToLower().Trim()
}


# --------------------------------------------------------------------
# How to recover currently logged-in user info
# --------------------------------------------------------------------

$LoggedOnUser = (Get-CimInstance Win32_ComputerSystem).UserName

function Get-LoggedOnUserInfo {

    # --- 1. Detect active interactive user (Intune-safe) ---
    $explorer = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" |
    Sort-Object CreationDate |
    Select-Object -First 1

    if (-not $explorer) {
        Write-Error "No interactive user session found"
        return $null
    }

    $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner

    if (-not $owner.User) {
        Write-Error "Failed to resolve explorer.exe owner"
        return $null
    }

    $Username = $owner.User
    $Domain = $owner.Domain

    # --- 2. Resolve SID ---
    try {
        $ntAccount = New-Object System.Security.Principal.NTAccount("$Domain\$Username")
        $SID = ($ntAccount.Translate([System.Security.Principal.SecurityIdentifier])).Value
    }
    catch {
        Write-Error "Unable to resolve SID"
        return $null
    }

    # --- 3. Detect account type ---
    $AccountType = "Unknown"
    if ($Domain -eq $env:COMPUTERNAME) {
        $AccountType = "Local"
    }
    elseif ($Domain -eq "AzureAD") {
        $AccountType = "AzureAD"
    }
    else {
        $AccountType = "HybridAD"
    }

    # --- 4. Resolve UPN (WORKS IN SYSTEM CONTEXT) ---
    $UPN = $null
    try {
        $UPN = (Get-CimInstance Win32_ComputerSystem).UserName
    }
    catch {}

    # --- 5. Get profile path ---
    $ProfilePath = $null
    try {
        $ProfilePath = (Get-CimInstance Win32_UserProfile |
            Where-Object { $_.SID -eq $SID }).LocalPath
    }
    catch {}

    # --- 6. Get OneDrive path (SYSTEM safe) ---
    $OneDrivePath = $null

    if ($ProfilePath) {

        # Preferred: Known OneDrive folder inside profile
        $candidate = Join-Path $ProfilePath "OneDrive"
        if (Test-Path $candidate) {
            $OneDrivePath = $candidate
        }

        # Business tenant naming fallback
        if (-not $OneDrivePath) {
            $businessFolders = Get-ChildItem -Path $ProfilePath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "OneDrive -*" }

            if ($businessFolders) {
                $OneDrivePath = $businessFolders[0].FullName
            }
        }

        # Registry fallback ONLY if hive is loaded
        if (-not $OneDrivePath) {
            try {
                $regPath = "Registry::HKEY_USERS\$SID\Software\Microsoft\OneDrive\Accounts"
                if (Test-Path $regPath) {
                    $accountKey = Get-ChildItem $regPath | Select-Object -First 1
                    $OneDrivePath = (Get-ItemProperty $accountKey.PSPath).UserFolder
                }
            }
            catch {}
        }
    }


    # --- 7. Return object ---
    return [PSCustomObject]@{
        Username     = $Username
        Domain       = $Domain
        SID          = $SID
        UPN          = $UPN
        AccountType  = $AccountType
        ProfilePath  = $ProfilePath
        OneDrivePath = $OneDrivePath
    }
}

# --- Execution ---
$userInfo = Get-LoggedOnUserInfo
<#
Write-Output "`n ---- User Info Report ----"
$userInfo | Format-List
#>

Write-Output "---- User Details ----"
Write-Host "Username:       $($userInfo.Username)"
Write-Host "OneDrivePath:   $($userInfo.OneDrivePath)"
Write-Host "SID:            $($userInfo.SID)"
Write-Host "UPN:            $($userInfo.UPN)"

# -----------------------------------------------------------------




# ----------------------------------------------------------------------------------------------
# Function Type A: Detection Method for DisplayName + Publisher + DisplayVersion
# ----------------------------------------------------------------------------------------------
<#
.SYNOPSIS
    Version: 26.0
    - Get if version of the app exists for both 32-bit and 64-bit registry paths.
    - Exit 0 if condition are satisfied, Exit 1 if NOT
.NOTES 
    -
#>

Write-Host "`nScanning Process starts now...`n"

## :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::: ##
## == function Get-AppInfo :collect and display information about the target application == ##
## :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::: ##

function Get-AppInfo {
    param (
        [string]$regPath32 = "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\",
        [string]$regPath64 = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\",
        [string]$regPath_Usersession = "Registry::HKEY_USERS\$($userInfo.SID)\Software\Microsoft\Windows\CurrentVersion\Uninstall\",
        [string[]]$targetApps
    )

    $programInfo = @()

    foreach ($targetApp in $targetApps) {

        $normalizedTarget = Format-Name $targetApp

        foreach ($regPath in $regPath32, $regPath64, $regPath_Usersession) {
            try {
                $subkeys = Get-ChildItem -Path $regPath
            }
            catch {
                Write-Warning "Failed to access registry path: $regPath. Error: $_"
                continue
            }

            foreach ($subkey in $subkeys) {
                try {
                    $program = Get-ItemProperty -Path $subkey.PSPath

                    if ($program -and $program.PSObject.Properties['DisplayName']) {

                        $displayName = Format-Name $program.DisplayName

                        if ($displayName -like "*$normalizedTarget*") {
                            Write-Host "Match found: $($program.DisplayName)"

                            $programInfo += [PSCustomObject]@{
                                "TargetName"        = $targetApp
                                "DisplayName"       = if ($program.PSObject.Properties['DisplayName']) { $program.DisplayName } else { $null }
                                "DisplayVersion"    = if ($program.PSObject.Properties['DisplayVersion']) { $program.DisplayVersion } else { $null }
                                "Publisher"         = if ($program.PSObject.Properties['Publisher']) { $program.Publisher } else { $null }
                                "UninstallString"   = if ($program.PSObject.Properties['UninstallString']) { $program.UninstallString } else { $null }
                                "RegistryPath"      = $subkey.PSPath
                                "BundleCachePath"   = if ($program.PSObject.Properties['BundleCachePath']) { $program.BundleCachePath } else { $null }
                                "BundleProviderKey" = if ($program.PSObject.Properties['BundleProviderKey']) { $program.BundleProviderKey } else { $null }

                            }
                        }
                    }
                }
                catch {
                    Write-Warning "Failed to read registry subkey: $($subkey.PSPath). Error: $_"
                }
            }
        }
    }

    if ($programInfo.Count -eq 0) {
        Write-Host "No matching applications found for: $($targetApps -join ', ')"
    }

    return $programInfo
}

###############################################################################################
## == Main logic: detect target apps and check required version and publisher == ##
###############################################################################################

$targetApps = @(
    "$_AppName"
)

# Force array output
$appInfos = @(Get-AppInfo -targetApps $targetApps)

# Optional: local debug only (remove for Intune)
$appInfos | Format-List

Write-Host "Number of apps found: $($appInfos.Count)"

$compliant = $false

foreach ($app in $appInfos) {

    $normalizedPublisher    = Format-Name $app.Publisher
    $normalizedReqProducer  = Format-Name $_Producer

    if (
        $app.Publisher -and
        ($normalizedPublisher -eq $normalizedReqProducer)
    ) {
        Write-Host "Found compliant app:"
        Write-Host "  Name      : $($app.DisplayName)"
        Write-Host "  Version   : $($app.DisplayVersion)"
        Write-Host "  Publisher : $($app.Publisher)"

        $compliant = $true
        break
    }
}

# Remediation Exit value: 1 need to run remediation script, 0 need to run it. Exactely opposed logic from software installation

if ($compliant) {
    Write-Output "$_AppName detected and correct publisher."
    exit 1
}
else {
    Write-Output "$_AppName not detected or publisher mismatch."
    exit 0
}
