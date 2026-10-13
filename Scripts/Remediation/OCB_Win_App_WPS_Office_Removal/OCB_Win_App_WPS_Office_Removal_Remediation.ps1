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
## Filename   : uninstall.ps1
## Version         : 8.0
## Creation Date   : xx-xx-xxxx
## Last Update     : -
## --------------------------------------------------------------------------
## Software name    :
## Software version :
## Official site    :
## --------------------------------------------------------------------------
## Description      :
##   -  Silenty uninstall
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


# Set up PowerShell parameters
Set-PSDebug -Trace 0    # 0 = off; use 1 or 2 only for troubleshooting
Set-StrictMode -Version 3

# Retrieve the path from where the script has been run and put it in the $_MyPath variable (preferred over Split-Path) 
$_MyPath = $PSScriptRoot

# Environment variables are directly accessible when needed:
# $env:ALLUSERSPROFILE

# :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
# ---------------------------
## -- CUSTOM VARIABLES -- ##
# ---------------------------
$_AppName = "WPS Office"
$_Producer = "Kingsoft Corp."

## :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
# ------------------------------------------------------------
# Ensure log directory exists
# ------------------------------------------------------------
$LogFolder = "C:\ProgramData\MSF\Logs"
if (!(Test-Path $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
}

# ------------------------------------------------------------
## Start transcription
# ------------------------------------------------------------

# region Logging
# $LogFolder = 'C:\ProgramData\Company\Logs\AppName'
# New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null

$logFile = Join-Path $LogFolder "${_AppName}_Uninstall_IntuneProcess.log"

$transcriptStarted = $false

try {
    Start-Transcript -Path $logFile -ErrorAction Stop
    $transcriptStarted = $true
}
catch {
    Write-Host "Transcript could not be started: $($_.Exception.Message)"
}

# End region

###################################################################

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



# ==========================================================================================
# Function Type E : Detection Method: DisplayName / Publisher  +  Unistall Process
# ==========================================================================================

<#
.SYNOPSIS
    Version: 40.0
    - Get if the app exist for both 32-bit and 64-bit registry paths.
    - If the function finds the apps, script proceeds to uninstall them regardless of version.
.NOTES 
    - Uninstaller process must be adapted based on the application, this is not an universal uninstaller.
      In this case , Uninstaller function can be used  for MSI File and exe files
#>


Write-Host "`nScanning Process starts now...`n"

# -----------------------------------------------------------------------------------------
## == function Get-AppInfo :collect and display information about the target application 
# -----------------------------------------------------------------------------------------

function Get-AppInfo {
    param (
        [string]$regPath32 = "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\",
        [string]$regPath64 = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\",
        [string]$regPath_Usersession = "Registry::HKEY_USERS\$($userInfo.SID)\Software\Microsoft\Windows\CurrentVersion\Uninstall\",
        [string[]]$targetApps
    )

    $programInfo = @()

    foreach ($targetApp in $targetApps) {

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

                        # normalized registry DisplayName + Publisher + Custom Variables
                        $DisplayName_Normalized = Format-Name $program.DisplayName
                        $Publisher_Normalized = Format-Name $program.Publisher
                        $_AppName_Normalized = Format-Name $_AppName
                        $_Producer_Normalized = Format-Name $_Producer

                        if (
                            $DisplayName_Normalized -like "*$_AppName_Normalized*" -and
                            $Publisher_Normalized -like "*$_Producer_Normalized*") {
                            Write-Host "Match found: $($program.DisplayName)"
                           <# OR in the case you need a perfect match
                            $DisplayName_Normalized -match "^$([regex]::Escape($_AppName_Normalized))(\s+\d+.*)?$" -and
                            $Publisher_Normalized -eq $_Producer_Normalized) {
                            Write-Host "Match found: $($program.DisplayName)"
                            #>

                            $programInfo += [PSCustomObject]@{
                                "TargetName"        = $targetApp
                                "DisplayName"       = if ($program.PSObject.Properties['DisplayName']) { $program.DisplayName } else { $null }
                                "DisplayVersion"    = if ($program.PSObject.Properties['DisplayVersion']) { $program.DisplayVersion } else { $null }
                                "Publisher"         = if ($program.PSObject.Properties['Publisher']) { $program.Publisher } else { $null }
                                "UninstallString"   = if ($program.PSObject.Properties['UninstallString']) { $program.UninstallString } else { $null }
                                "InstallSource"     = if ($program.PSObject.Properties['InstallSource']) { $program.InstallSource } else { $null }
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

# -----------------------------------------------------------------------------------------
# == function Uninstall-App : Uninstall engine - FULL -
# -----------------------------------------------------------------------------------------

function Uninstall-App {
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$appInfo
    )

    $UninstallString = $appInfo.UninstallString
    if (-not $UninstallString) {
        Write-Warning "No uninstall string for $($appInfo.DisplayName)"
        throw "NO_UNINSTALL_STRING"
    }

    $logRoot = "C:\ProgramData\MSF\Logs"
    if (-not (Test-Path $logRoot)) {
        New-Item -ItemType Directory -Path $logRoot | Out-Null
    }

    # ---------------------------------------------------
    # SAFE log file name (no symbols, no spaces, no empty)
    # ---------------------------------------------------
    $safeName = Format-Name $appInfo.DisplayName
    if (-not $safeName) { $safeName = "unknown_app" }

    # remove illegal file name characters
    $safeName = $safeName -replace '[\\\/:\*\?"<>\|]', '_'

    $logFile = Join-Path $logRoot "${safeName}_uninstall.log"
    # ---------------------------------------------------

    function Write-Log {
        param ($Message)
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$ts - $Message" | Tee-Object -FilePath $logFile -Append
    }

    Write-Log "Starting uninstall for $($appInfo.DisplayName)"
    Write-Log "UninstallString: $UninstallString"

    # ------------------------------------------------------------
    # PRE-UNINSTALL: Stop $_AppName processes and services
    # ------------------------------------------------------------
    Write-Log "Pre-uninstall cleanup: stopping $_AppName processes and services"

    # ---- Kill running $_AppName processes ----
    try {
        $_App_Processes = Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match "^$_AppName(\d+)?$" -or
            $_.Path -match "\\$_AppName"
        }

        foreach ($_proc in $_App_Processes) {
            Write-Log "Stopping process: $($_proc.Name) (PID $($_proc.Id))"
            Stop-Process -Id $_proc.Id -Force -ErrorAction Stop
        }

        if (-not $_App_Processes) {
            Write-Log "No running $_AppName processes found"
        }
    }
    catch {
        Write-Log "WARNING: Failed stopping some $_AppName processes: $_"
    }

    # ---- Stop $_AppName related services ----
    try {
        $_App_Services = Get-CimInstance Win32_Service |
        Where-Object {
            $_.Name -match "$_AppName" -or
            $_.DisplayName -match "$_AppName" -or
            $_.PathName -match "\\$_AppName"
        }

        foreach ($_svc in $_App_Services) {
            if ($_svc.State -ne 'Stopped') {
                Write-Log "Stopping service: $($_svc.Name)"
                Invoke-CimMethod -InputObject $_svc -MethodName StopService | Out-Null
            }
            else {
                Write-Log "Service already stopped: $($_svc.Name)"
            }
        }

        if (-not $_App_Services) {
            Write-Log "No $_AppName related services found"
        }
    }
    catch {
        Write-Log "WARNING: Failed stopping some $_AppName services: $_"
    }

    # Allow time for handles to release
    Start-Sleep -Seconds 3
    Write-Log "Pre-uninstall cleanup completed"

    # ------------------------------------------------------------
    # MSI
    # ------------------------------------------------------------
    if ($UninstallString -match 'msiexec' -or $UninstallString -match '\{[0-9A-F\-]{36}\}') {

        $guid = if ($UninstallString -match '\{[0-9A-F\-]{36}\}') { $matches[0] }

        if (-not $guid) {
            Write-Log "MSI detected but GUID not found : process aborting"
            throw "MSI_GUID_NOT_FOUND"
        }

        # $_args = "/X $guid /qn /norestart /lv `"$logFile`""
        $_args = @(
            "/X"
            $guid
            "/qn"
            "/norestart"
            "/L*v `"$logFile`""
        )
        
        Write-Log "Installer type: MSI"
        Write-Log "Arguments: $_args"

        $proc = Start-Process msiexec.exe -ArgumentList $_args -Wait -PassThru
        Write-Log "Exit code: $($proc.ExitCode)"

        # --------------------------------------------------------
        # MSI FAILED : FALLBACK TO INSTALLSOURCE
        # --------------------------------------------------------
        if ($proc.ExitCode -ne 0) {

            Write-Log "MSI uninstall failed with exit code $($proc.ExitCode)"
            Write-Log "Attempting fallback uninstall using InstallSource"

            $installSource = $appInfo.InstallSource

            if ($installSource -and (Test-Path $installSource)) {

                Write-Log "InstallSource found: $installSource"

                $msiFile = Get-ChildItem -Path $installSource -Filter *.msi -ErrorAction SilentlyContinue |
                Select-Object -First 1

                if ($msiFile) {

                    Write-Log "Found MSI in InstallSource: $($msiFile.FullName)"

                    $_fallbackArgs = "/X `"$($msiFile.FullName)`" /qn /norestart REBOOT=ReallySuppress /l*v `"$logFile`""
                    Write-Log "Fallback arguments: $_fallbackArgs"

                    $fallbackProc = Start-Process msiexec.exe `
                        -ArgumentList $_fallbackArgs `
                        -Wait -PassThru

                    Write-Log "Fallback exit code: $($fallbackProc.ExitCode)"

                    if ($fallbackProc.ExitCode -eq 0) {
                        Write-Log "Fallback MSI uninstall succeeded"
                        return
                    }
                    else {
                        Write-Log "Fallback MSI uninstall failed"
                        throw "MSI_UNINSTALL_FAILED_FALLBACK"
                    }
                }
                else {
                    Write-Log "No MSI file found in InstallSource"
                    throw "MSI_INSTALLSOURCE_NO_MSI_FOUND"
                }
            }
            else {
                Write-Log "InstallSource missing or invalid"
                throw "MSI_INSTALLSOURCE_NOT_AVAILABLE"
            }
        }

        return
    }

    # ------------------------------------------------------------
    # EXE
    # ------------------------------------------------------------
    if ($UninstallString -match '^[\"'']?([A-Z]:\\.*?\.exe)') {

        $exePath = $matches[1]
        $existing_Args = $UninstallString.Replace($exePath, "").Trim()
        $silent_Args = @()
        $installerType = "Unknown"

        if ( $UninstallString -match '\\setup\.exe' -and (
                $UninstallString -match 'removeonly' -or
                $UninstallString -match 'InstallShield'
            )) {
            $installerType = "InstallShield"
            if ($existing_Args -notmatch '/s') {
                $silent_Args += "/s"
                $silent_Args += "/v`"/qn`""
            }
        }
        elseif ($UninstallString -match '\\uninstall\.exe' -and
            $UninstallString -notmatch 'unins\d+\.exe') {
            $installerType = "NSIS"
            if ($existing_Args -notmatch '/S') {
                $silent_Args += "/S"
            }
        }
        elseif ($UninstallString -match 'unins\d+\.exe') {
            $installerType = "Inno Setup"
            if ($existing_Args -notmatch 'VERYSILENT') {
                $silent_Args += "/VERYSILENT"
                $silent_Args += "/SUPPRESSMSGBOXES"
                $silent_Args += "/NORESTART"
                $silent_Args += "/LOG=`"$logFile`""
            }
        }
        else {
            if ($existing_Args -notmatch '/quiet|/silent|/s') {
                $silent_Args += "/s"
            }
        }

        $final_Args = @()
        if ($existing_Args) { $final_Args += $existing_Args }
        $final_Args += $silent_Args

        Write-Log "Installer type: $installerType"
        Write-Log "Executable: $exePath"
        Write-Log "Arguments: $($final_Args -join ' ')"

        try {
            $proc = Start-Process -FilePath $exePath `
                -ArgumentList $final_Args `
                -NoNewWindow -Wait -PassThru

            Write-Log "Exit code: $($proc.ExitCode)"
            if ($proc.ExitCode -ne 0) {
                throw "EXE_UNINSTALL_FAILED"
            }
        }
        catch {
            Write-Log "ERROR: $_"
            throw "EXE_UNINSTALL_EXCEPTION"
        }
        return
    }

    Write-Log "Unrecognized uninstall string format"
    throw "UNSUPPORTED_UNINSTALL_STRING"
}

# -----------------------------------------------------------------------------------------
## == Main logic: detect target app and uninstall it regardless of version == ##
# -----------------------------------------------------------------------------------------

$targetApps = @(
    "$_AppName"
)

$appInfos = @(Get-AppInfo -targetApps $targetApps)

$formattedAppInfos = @()
foreach ($app in $appInfos) {
    $formattedAppInfos += [PSCustomObject]@{
        "TargetName"        = $app.TargetName
        "DisplayName"       = $app.DisplayName
        "DisplayVersion"    = $app.DisplayVersion
        "Publisher"         = $app.Publisher
        "UninstallString"   = $app.UninstallString
        "InstallSource"     = $app.InstallSource
        "RegistryPath"      = $app.RegistryPath
        "BundleCachePath"   = $app.BundleCachePath
        "BundleProviderKey" = $app.BundleProviderKey
    }
}

$formattedAppInfos | Format-List

switch ($appInfos.Count) {
    0 { Write-Host "Number of apps found: 0" }
    1 { Write-Host "Number of apps found: 1" }
    default { Write-Host "Number of apps found: $($appInfos.Count)" }
}

foreach ($app in $appInfos) {
    if ($app -is [PSCustomObject] -and $app.PSObject.Properties['DisplayName']) {
        Write-Host "Found: $($app.DisplayName) -- Version: $($app.DisplayVersion)"
        Write-Host "Uninstalling $($app.DisplayName)...`n"

        try {
            Uninstall-App -appInfo $app
        }
        catch {
            Write-Error $_
            exit 1
        }
    }
    else {
        Write-Warning "Unexpected object in appInfos: $($app | Out-String)`n"
        exit 1
    }
}


######################################################################
## :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::: ##
######################################################################


# ------------------------------------------------------------
## Stop Transcription if it strarted
# ------------------------------------------------------------

if ($transcriptStarted) {
    Stop-Transcript | Out-Null
}

## ::::::::::::::::::::::::::::::::::::::

write-output "Uninstall Process ended!"

exit 0
## :::::::::::: -- EOF -- ::::::::::::##

