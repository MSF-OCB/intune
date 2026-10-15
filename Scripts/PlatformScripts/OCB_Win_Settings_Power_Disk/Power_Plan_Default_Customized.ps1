##################################################################
#  __\ / _  __ _  _  __      ___ __ __   
# /   Y |_)|_ |_)|_|/  |/     | |_ /  |_|
# \__ | |_)|__| \| |\__|\  o  | |__\__| |
##################################################################
#
# Power Settings Configurator
# Written by: Omar Assaf
# X: @omar_assaf
#
##################################################################

<#
.SYNOPSIS
    Applies power settings with proper GPO/Intune conflict detection.

.DESCRIPTION
    Fetches JSON configuration, detects policy-locked settings via
    multiple methods, applies only non-locked settings, and provides
    comprehensive logging and rollback capability.

.VERSION
    2.8 (Allow file sharing for CMTrace compatibility)
    2.7 (-- Improved logging reliability)
    2.6 (2023 Edition - Initial Release)
    2.5 (2022 Edition - Initial Release)
    2.0 (Initial Release)

.AUTHOR
    Omar Assaf

.NOTES
    Requires Administrator privileges.
    Tested on Windows 10 and Windows 11.
#>

#Requires -RunAsAdministrator

##################################################################
# Constants & Paths
##################################################################
$PowerSchemeBalanced = "381b4222-f694-41f0-9685-ff5bb260df2e"
$PowerRegPath        = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings'
$GpoPowerPath        = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings'
$PolicyDefault       = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Power"
$PolicyCurrent       = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\Power"

$MsfOcbRegPath = 'HKLM:\SOFTWARE\MSFOCB\Intune'
$MsfOcbRegKey  = "IntunePowerSettingsVersion"
$BackupRegKey  = "PowerSettingsBackup"

$LogDirectory = Join-Path $env:ProgramData "MSF\Logs\Intune\Scripts"
$LogPath      = Join-Path $LogDirectory "Power_config.log"

$PowerSettingsUrl = "https://msfocbshare.blob.core.windows.net/ict-prod/Intune/Win/Settings/Power/power_settings.json"

# Statistics
$script:AppliedCount = 0
$script:SkippedCount = 0
$script:FailedCount  = 0

##################################################################
# Ensure Log Directory Exists
##################################################################
if (!(Test-Path $LogDirectory)) {
    try {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
    catch {
        Write-Host "FATAL: Cannot create log directory - $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

##################################################################
# Logging Function with CMTrace-Safe File Writing
##################################################################
function Write-Log {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Message = "",
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp [$Level] $Message"

    # Always output to console
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }
    Write-Host $entry -ForegroundColor $color

    # Write to file with retry logic (CMTrace compatible)
    $maxRetries = 3
    $retryDelay = 50  # ms

    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            $fileStream = [System.IO.FileStream]::new(
                $LogPath,
                [System.IO.FileMode]::Append,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::ReadWrite
            )

            $streamWriter = [System.IO.StreamWriter]::new($fileStream)
            $streamWriter.WriteLine($entry)
            $streamWriter.Flush()
            $streamWriter.Close()
            $fileStream.Close()

            return  # Success
        }
        catch {
            if ($i -eq ($maxRetries - 1)) {
                Write-Host "Unable to write log after $maxRetries attempts: $_" -ForegroundColor Red
            }
            else {
                Start-Sleep -Milliseconds $retryDelay
            }
        }
    }
}

Write-Log "============================================================="
Write-Log "--- Starting Power Configuration Script ---"
Write-Log "============================================================="

##################################################################
# Privilege Validation
##################################################################
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Log "FATAL: Script must run with Administrator privileges." -Level "ERROR"
    exit 1
}

Write-Log "Privilege check: Running as Administrator" -Level "SUCCESS"

##################################################################
# Early Exit if Already Applied
##################################################################
$MsfOcbKeyStatus = (Get-ItemProperty -Path $MsfOcbRegPath -ErrorAction SilentlyContinue).$MsfOcbRegKey
if ($MsfOcbKeyStatus -eq 1) {
    Write-Log "Power settings already applied previously. Exiting." -Level "INFO"
    exit 0
}

##################################################################
# Backup Current Power Settings
##################################################################
function Backup-CurrentPowerSettings {
    Write-Log "Creating backup of current power settings..."

    try {
        $backup = @{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Settings  = @()
        }

        $allSubgroups = Get-ChildItem -Path $PowerRegPath -ErrorAction Stop

        foreach ($subgroup in $allSubgroups) {
            $subgroupGuid = $subgroup.PSChildName
            $settings = Get-ChildItem -Path $subgroup.PSPath -ErrorAction SilentlyContinue

            foreach ($setting in $settings) {
                $settingGuid = $setting.PSChildName

                try {
                    $acValue = & powercfg -query $PowerSchemeBalanced $subgroupGuid $settingGuid 2>&1 |
                        Select-String "Current AC Power Setting Index:" |
                        ForEach-Object { ($_ -split ':')[1].Trim() }

                    $dcValue = & powercfg -query $PowerSchemeBalanced $subgroupGuid $settingGuid 2>&1 |
                        Select-String "Current DC Power Setting Index:" |
                        ForEach-Object { ($_ -split ':')[1].Trim() }

                    if ($acValue -or $dcValue) {
                        $backup.Settings += @{
                            SubgroupGUID = $subgroupGuid
                            SettingGUID  = $settingGuid
                            ACValue      = $acValue
                            DCValue      = $dcValue
                        }
                    }
                }
                catch {
                    continue
                }
            }
        }

        if (!(Test-Path $MsfOcbRegPath)) {
            New-Item -Path $MsfOcbRegPath -Force | Out-Null
        }

        $backupJson = $backup | ConvertTo-Json -Compress
        Set-ItemProperty -Path $MsfOcbRegPath -Name $BackupRegKey -Value $backupJson -Force

        Write-Log "Backup completed: $($backup.Settings.Count) settings stored" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Backup failed: $($_.Exception.Message)" -Level "WARNING"
        return $false
    }
}

##################################################################
# Detect Policy-Locked Settings (Multi-Method)
##################################################################
function Test-SettingLockedByPolicy {
    param(
        [string]$SubgroupGUID,
        [string]$SettingGUID
    )

    # Method 1: GPO registry paths (with/without braces)
    $gpoVariants = @(
        "$GpoPowerPath\$SubgroupGUID\$SettingGUID",
        "$GpoPowerPath\{$SubgroupGUID}\{$SettingGUID}",
        "$GpoPowerPath\$SubgroupGUID\{$SettingGUID}",
        "$GpoPowerPath\{$SubgroupGUID}\$SettingGUID"
    )

    foreach ($path in $gpoVariants) {
        if (Test-Path $path) {
            $acOverride = Get-ItemProperty -Path $path -Name "ACSettingIndex" -ErrorAction SilentlyContinue
            $dcOverride = Get-ItemProperty -Path $path -Name "DCSettingIndex" -ErrorAction SilentlyContinue

            if ($acOverride -or $dcOverride) {
                Write-Log "  └─ GPO lock detected at: $path" -Level "INFO"
                return $true
            }
        }
    }

    # Method 2: Intune MDM policy paths
    $mdmPaths = @(
        "$PolicyCurrent\$SettingGUID",
        "$PolicyDefault\$SettingGUID"
    )

    foreach ($path in $mdmPaths) {
        if (Test-Path $path) {
            Write-Log "  └─ Intune MDM lock detected at: $path" -Level "INFO"
            return $true
        }
    }

    return $false
}

##################################################################
# Validate JSON Schema
##################################################################
function Test-PowerSettingsSchema {
    param($JsonObject)

    Write-Log "Validating JSON schema..."

    if (-not $JsonObject.PowerSettings) {
        Write-Log "Invalid JSON: Missing 'PowerSettings' property" -Level "ERROR"
        return $false
    }

    if (-not ($JsonObject.PowerSettings -is [Array])) {
        Write-Log "Invalid JSON: 'PowerSettings' is not an array" -Level "ERROR"
        return $false
    }

    $validationErrors = 0

    foreach ($subgroup in $JsonObject.PowerSettings) {
        if (-not $subgroup.SubgroupGUID) {
            Write-Log "Invalid subgroup: Missing SubgroupGUID" -Level "WARNING"
            $validationErrors++
            continue
        }

        if (-not $subgroup.Settings -or -not ($subgroup.Settings -is [Array])) {
            Write-Log "Invalid subgroup $($subgroup.SubgroupGUID): Missing or invalid Settings array" -Level "WARNING"
            $validationErrors++
            continue
        }

        foreach ($setting in $subgroup.Settings) {
            $required = @('SettingGUID', 'PowerName', 'ACValue', 'DCValue')
            $missing = $required | Where-Object { -not $setting.$_ -and $setting.$_ -ne 0 }

            if ($missing) {
                Write-Log "Invalid setting: Missing properties: $($missing -join ', ')" -Level "WARNING"
                $validationErrors++
            }
        }
    }

    if ($validationErrors -gt 0) {
        Write-Log "Schema validation completed with $validationErrors warnings" -Level "WARNING"
    }
    else {
        Write-Log "Schema validation passed" -Level "SUCCESS"
    }

    return $true
}

##################################################################
# Download JSON with Retry
##################################################################
function Get-JsonWithRetry {
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 2
    )

    for ($i = 1; $i -le $MaxRetries; $i++) {
        Write-Log "Fetching JSON (Attempt $i of $MaxRetries)..."

        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $result = Invoke-RestMethod -Uri $Url -UseBasicParsing -ErrorAction Stop
            return $result
        }
        catch {
            Write-Log "Attempt $i failed: $($_.Exception.Message)" -Level "WARNING"

            if ($i -lt $MaxRetries) {
                Write-Log "Retrying in $DelaySeconds seconds..."
                Start-Sleep -Seconds $DelaySeconds
            }
            else {
                Write-Log "All attempts to download JSON failed" -Level "ERROR"
                throw $_
            }
        }
    }
}

##################################################################
# Download & Validate Configuration
##################################################################
try {
    $PowerSettingsConfig = Get-JsonWithRetry -Url $PowerSettingsUrl
    Write-Log "Successfully downloaded JSON configuration" -Level "SUCCESS"

    if (-not (Test-PowerSettingsSchema -JsonObject $PowerSettingsConfig)) {
        Write-Log "JSON schema validation failed - aborting" -Level "ERROR"
        exit 1
    }
}
catch {
    Write-Log "FATAL: Cannot fetch or validate JSON: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

##################################################################
# Create Backup
##################################################################
$backupSuccess = Backup-CurrentPowerSettings
if (-not $backupSuccess) {
    Write-Log "Continuing without backup (non-fatal)" -Level "WARNING"
}

##################################################################
# Restore Balanced Scheme & Activate
##################################################################
try {
    Write-Log "Restoring default power schemes..."
    $null = & powercfg.exe /restoredefaultschemes 2>&1

    Write-Log "Activating Balanced power scheme..."
    $null = & powercfg.exe /setactive $PowerSchemeBalanced 2>&1

    Write-Log "Balanced Power Scheme restored and activated" -Level "SUCCESS"
}
catch {
    Write-Log "Failed to activate Balanced scheme: $($_.Exception.Message)" -Level "ERROR"
}

##################################################################
# Apply Individual Power Setting
##################################################################
function Set-PowerSetting {
    param(
        [string]$SubgroupGUID,
        [string]$SettingGUID,
        [string]$PowerName,
        [int]$ACValue,
        [int]$DCValue
    )

    Write-Log "Processing: $PowerName"

    if (Test-SettingLockedByPolicy -SubgroupGUID $SubgroupGUID -SettingGUID $SettingGUID) {
        Write-Log "  └─ SKIPPED: Locked by Group Policy or Intune" -Level "WARNING"
        $script:SkippedCount++
        return
    }

    try {
        $acOutput = & powercfg /setacvalueindex $PowerSchemeBalanced $SubgroupGUID $SettingGUID $ACValue 2>&1
        $acBlocked = $acOutput | Where-Object { $_ -match "Group policy override|access.*denied" }

        $dcOutput = & powercfg /setdcvalueindex $PowerSchemeBalanced $SubgroupGUID $SettingGUID $DCValue 2>&1
        $dcBlocked = $dcOutput | Where-Object { $_ -match "Group policy override|access.*denied" }

        if ($acBlocked -or $dcBlocked) {
            Write-Log "  └─ SKIPPED: Runtime policy block detected" -Level "WARNING"
            if ($acBlocked) { Write-Log "     AC Error: $acBlocked" -Level "INFO" }
            if ($dcBlocked) { Write-Log "     DC Error: $dcBlocked" -Level "INFO" }
            $script:SkippedCount++
            return
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Log "  └─ FAILED: powercfg returned exit code $LASTEXITCODE" -Level "ERROR"
            $script:FailedCount++
            return
        }

        # Make visible in UI
        $settingPath = Join-Path (Join-Path $PowerRegPath $SubgroupGUID) $SettingGUID

        if (Test-Path $settingPath) {
            try {
                Set-ItemProperty -Path $settingPath -Name "Attributes" -Value 2 -Force -ErrorAction Stop
            }
            catch {
                Write-Log "  └─ Warning: Could not set Attributes flag: $($_.Exception.Message)" -Level "WARNING"
            }
        }
        else {
            Write-Log "  └─ Warning: Setting registry path not found: $settingPath" -Level "WARNING"
        }

        Write-Log "  └─ SUCCESS: AC=$ACValue | DC=$DCValue" -Level "SUCCESS"
        $script:AppliedCount++
    }
    catch {
        Write-Log "  └─ ERROR: $($_.Exception.Message)" -Level "ERROR"
        $script:FailedCount++
    }
}

##################################################################
# Apply All Settings from JSON
##################################################################
Write-Log "============================================================="
Write-Log "Beginning power settings application..."
Write-Log "============================================================="

$totalSettings = 0
foreach ($subgroup in $PowerSettingsConfig.PowerSettings) {
    $totalSettings += $subgroup.Settings.Count
}

Write-Log "Total settings to process: $totalSettings"

foreach ($subgroup in $PowerSettingsConfig.PowerSettings) {
    Write-Log ""
    Write-Log "--- Subgroup: $($subgroup.SubgroupGUID) ---"

    foreach ($setting in $subgroup.Settings) {
        Set-PowerSetting `
            -SubgroupGUID $subgroup.SubgroupGUID `
            -SettingGUID  $setting.SettingGUID `
            -PowerName    $setting.PowerName `
            -ACValue      $setting.ACValue `
            -DCValue      $setting.DCValue
    }
}

##################################################################
# Commit Changes
##################################################################
Write-Log ""
Write-Log "Committing power settings changes..."
try {
    $null = & powercfg /setactive $PowerSchemeBalanced 2>&1
    Write-Log "Power scheme changes committed" -Level "SUCCESS"
}
catch {
    Write-Log "Warning: Could not commit changes: $($_.Exception.Message)" -Level "WARNING"
}

##################################################################
# Summary
##################################################################
Write-Log ""
Write-Log "============================================================="
Write-Log "--- Execution Summary ---"
Write-Log "============================================================="
Write-Log "Total Settings: $totalSettings"
Write-Log "Applied:        $script:AppliedCount" -Level "SUCCESS"
Write-Log "Skipped:        $script:SkippedCount" -Level "WARNING"
Write-Log "Failed:         $script:FailedCount" -Level "ERROR"
Write-Log "============================================================="

##################################################################
# Mark as Completed
##################################################################
try {
    if (!(Test-Path $MsfOcbRegPath)) {
        New-Item -Path $MsfOcbRegPath -Force | Out-Null
    }

    Set-ItemProperty -Path $MsfOcbRegPath -Name $MsfOcbRegKey -Value 1 -Force
    Write-Log "Configuration completion flag recorded" -Level "SUCCESS"
}
catch {
    Write-Log "Unable to write registry completion flag: $($_.Exception.Message)" -Level "ERROR"
}

Write-Log ""
Write-Log "--- Completed Power Configuration Script ---"
Write-Log "============================================================="

# Final exit code
if ($script:FailedCount -gt 0) {
    exit 1
}
else {
    exit 0
}
