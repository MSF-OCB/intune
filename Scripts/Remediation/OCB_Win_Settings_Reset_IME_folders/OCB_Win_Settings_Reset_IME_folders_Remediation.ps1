<#
.SYNOPSIS
    Intune Remediation: Reset IME folders with adaptive cleanup strategy.

.DESCRIPTION
    - Stops and disables IME service
    - Kills related processes
    - Fixes permissions
    - Attempts deletion with retry logic
    - Detects locked files
    - Falls back to reboot-time cleanup if needed
    - Logs all actions
#>

$ErrorActionPreference = "Stop"

# Paths to clean
$Paths = @(
    @{ Path = "C:\ProgramData\Microsoft\IntuneManagementExtension\Staging"; Name = "IME Staging" },
    @{ Path = "C:\Program Files (x86)\Microsoft Intune Management Extension\Content\Incoming"; Name = "IME Incoming" },
    @{ Path = "C:\Program Files (x86)\Microsoft Intune Management Extension\Content\Staging"; Name = "IME Content Staging" }
)

# Logging
$LogRoot = "C:\ProgramData\MSF\Logs\Remediation"
$LogFile = Join-Path $LogRoot "IME-Reset_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "$timestamp [$Level] $Message"
    Write-Output $line
    Add-Content -Path $LogFile -Value $line
}

Write-Log "IME remediation started"

$cleanupOk = $true
$rebootCleanupNeeded = $false

# Resolve system tools with fallback
$cmdPath     = "$env:SystemRoot\System32\cmd.exe"
$takeownPath = "$env:SystemRoot\System32\takeown.exe"
$icaclsPath  = "$env:SystemRoot\System32\icacls.exe"

if (!(Test-Path $cmdPath))     { $cmdPath     = "$env:windir\Sysnative\cmd.exe" }
if (!(Test-Path $takeownPath)) { $takeownPath = "$env:windir\Sysnative\takeown.exe" }
if (!(Test-Path $icaclsPath))  { $icaclsPath  = "$env:windir\Sysnative\icacls.exe" }

# OPTIONAL (even safer): validate tools exist
foreach ($tool in @($cmdPath, $takeownPath, $icaclsPath)) {
    if (!(Test-Path $tool)) {
        Write-Log "Required system tool not found: $tool" "ERROR"
        exit 1
    }
}

# Stop and disable IME
Write-Log "Stopping and disabling IME service"
Stop-Service IntuneManagementExtension -Force -ErrorAction SilentlyContinue
Set-Service IntuneManagementExtension -StartupType Disabled -ErrorAction SilentlyContinue

# Kill IME processes
Write-Log "Killing IME-related processes"
Get-Process | Where-Object {
    $_.Path -and $_.Path -like "*IntuneManagementExtension*"
} | Stop-Process -Force -ErrorAction SilentlyContinue

Start-Sleep -Seconds 15

# Main cleanup function
function Reset-Folder {
    param(
        [string]$Path,
        [string]$Name
    )

    Write-Log "Processing $Name : $Path"

    if (!(Test-Path $Path)) {
        Write-Log "$Name not found, skipping"
        return $true
    }

    try {
        # Fix permissions
        Write-Log "Fixing permissions on $Name"

        & $takeownPath /f "$Path" /r /d y | Out-Null
        & $icaclsPath "$Path" /grant "*S-1-5-18:(OI)(CI)F" /t /c | Out-Null

        # Retry deletion loop
        for ($i = 1; $i -le 5; $i++) {

            Write-Log "Attempt $i to delete $Name"

            & $cmdPath /c "rd /s /q `"$Path`""

            Start-Sleep -Seconds 5

            if (!(Test-Path $Path)) {
                Write-Log "$Name deleted successfully on attempt $i"
                return $true
            }
        }

        # LOCK detected → fallback to reboot deletion
        Write-Log "$Name is locked after retries, scheduling for reboot cleanup" "WARN"

        $script:rebootCleanupNeeded = $true

        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        $prop = Get-ItemProperty -Path $regPath -Name PendingFileRenameOperations -ErrorAction SilentlyContinue

        $newEntry = @("\??\$Path", "")

        if ($prop -and $prop.PendingFileRenameOperations) {
            $updated = $prop.PendingFileRenameOperations + $newEntry
        } else {
            $updated = $newEntry
        }

        Set-ItemProperty -Path $regPath -Name PendingFileRenameOperations -Value $updated

        Write-Log "$Name scheduled for deletion at next reboot"
        return $true
    }
    catch {
        Write-Log "Error processing $Name : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Execute cleanup
foreach ($item in $Paths) {
    if (-not (Reset-Folder -Path $item.Path -Name $item.Name)) {
        $cleanupOk = $false
    }
}

Start-Sleep -Seconds 5

# Re-enable IME service
Write-Log "Re-enabling IME service"
Set-Service IntuneManagementExtension -StartupType Automatic

# Start IME
if ($cleanupOk) {
    try {
        Write-Log "Starting IME service"
        Start-Service IntuneManagementExtension
        Write-Log "IME service started"

        if ($rebootCleanupNeeded) {
            Write-Log "Reboot required to complete cleanup" "WARN"
        }

        Write-Log "Remediation completed successfully"
        exit 0
    }
    catch {
        Write-Log "Failed to start IME service: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}
else {
    Write-Log "Cleanup failed" "ERROR"
    exit 1
}
