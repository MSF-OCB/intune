<#
.SYNOPSIS
    Enterprise Silent Windows Update for Windows 11 24H2 / 25H2
    Per-update processing | Safe drivers by default | 3 forced passes
    
.DESCRIPTION
    Silently installs Windows updates with granular per-update logging.
    Processes each update individually for maximum visibility and control.
    
.PARAMETER InstallAll
    Install all updates including optional ones (definitions, tools, etc.)
    Default: $true
    
.PARAMETER SafeDrivers
    Block risky drivers (graphics, audio, OEM bloatware)
    Default: Enabled automatically when InstallAll is used
    
.PARAMETER IncludeFeatureUpdates
    Allow Windows feature updates (e.g., 24H2 -> 25H2)
    Default: $false
    
.PARAMETER LogPath
    Full path to log file
    Default: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
    
.EXAMPLE
    .\Autopilot_Update.ps1
    Installs all updates with safe driver filtering
    
.EXAMPLE
    .\Autopilot_Update.ps1 -InstallAll:$false
    Only installs critical/security/cumulative updates
    
.EXAMPLE
    .\Autopilot_Update.ps1 -SafeDrivers:$false
    Installs all drivers without filtering (risky)
#>

[CmdletBinding()]
param(
    [switch]$InstallAll = $true,
    [switch]$SafeDrivers,
    [switch]$IncludeFeatureUpdates = $false,
    [string]$LogPath = "C:\ProgramData\MSF\Logs\Intune\Scripts\OCB_WinUpdate_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
)

$script:ProcessedUpdates = @{}  # Track what we've already processed
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# === Auto-enable SafeDrivers when InstallAll is used ===
if ($InstallAll -and -not $PSBoundParameters.ContainsKey('SafeDrivers')) {
    $SafeDrivers = $true
}

if (-not (Test-Path -Path (Split-Path -Path $LogPath -Parent))) {
    New-Item -ItemType Directory -Path (Split-Path -Path $LogPath -Parent) -Force | Out-Null
}

#region Logging
function Write-OutputLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ConsoleColor]$Color = 'White',
        
        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Level = 'INFO'
    )
    
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $Line = "[$Timestamp] [$Level] $Message"
    Write-Host $Line -ForegroundColor $Color
    
    try {
        $Line | Out-File -FilePath $LogPath -Append -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log: $_"
    }
}
#endregion

#region Pre-Flight Checks
function Test-Prerequisites {
    # PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5 -or 
        ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
        Write-OutputLog "PowerShell 5.1+ required. Current: $($PSVersionTable.PSVersion)" Red 'ERROR'
        exit 1
    }
    
    # Administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if (-not $isAdmin) {
        Write-OutputLog "Script must run as Administrator" Red 'ERROR'
        exit 1
    }
    
    # Required services
    $requiredServices = @('wuauserv', 'BITS')
    foreach ($svcName in $requiredServices) {
        $svc = Get-Service $svcName -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-OutputLog "Required service not found: $svcName" Red 'ERROR'
            exit 1
        }
        
        if ($svc.Status -ne 'Running') {
            try {
                Write-OutputLog "Starting service: $svcName" Yellow 'WARN'
                Start-Service $svcName -ErrorAction Stop
                Write-OutputLog "Started service: $svcName" Green 'INFO'
            } catch {
                Write-OutputLog "FATAL: Cannot start $svcName - $($_.Exception.Message)" Red 'ERROR'
                exit 1
            }
        }
    }
}
#endregion

#region Driver Safety
# Curated block list (2025) - Graphics, Audio, OEM bloatware
$script:DriverBlockRegex = @(
    'intel.*(graphics|uhd|iris|arc)',
    'amd.*(radeon|ryzen.*graphics)',
    'nvidia.*(geforce|studio|quadro)',
    'realtek.*(audio|bluetooth|card.*reader)',
    'qualcomm.*atheros',
    'mediatek.*wi-?fi',
    'conexant',
    'nahimic',
    'sonic.*studio',
    'hp.*(audio|support|update)',
    'dell.*(update|command|digital.*delivery)',
    'lenovo.*(vantage|system.*update|companion)',
    'asus.*(armoury.*crate|ai.*suite|live.*update)',
    'msi.*center',
    'oem.*driver'
) -join '|'

function Test-SafeDriver {
    param([Parameter(Mandatory)]$Update)
    
    if ($Update.Type -ne 'Driver') { return $true }
    
    $title = $Update.Title.ToLower()
    
    # Whitelist: Known-safe Microsoft drivers
    $safePatterns = @(
        'microsoft.*(hid|usb|storage|keyboard|mouse)',
        'surface.*driver',
        'windows hello',
        'windows.*update',
        'firmware.*update'
    )
    
    foreach ($pattern in $safePatterns) {
        if ($title -match $pattern) {
            Write-OutputLog "    [DRIVER SAFE] Microsoft/System: $($Update.Title)" DarkGray 'DEBUG'
            return $true
        }
    }
    
    # Blacklist: Block risky drivers
    if ($title -match $script:DriverBlockRegex) {
        Write-OutputLog "    [DRIVER BLOCKED] High-risk category: $($Update.Title)" Yellow 'WARN'
        return $false
    }
    
    # User override
    if (-not $SafeDrivers) {
        Write-OutputLog "    [DRIVER ALLOWED] SafeDrivers disabled: $($Update.Title)" DarkYellow 'WARN'
        return $true
    }
    
    # Default: Block unknown drivers
    Write-OutputLog "    [DRIVER BLOCKED] Unclassified driver: $($Update.Title)" Yellow 'WARN'
    return $false
}
#endregion

#region Update Classification
function Test-ImportantUpdate {
    param([Parameter(Mandatory)]$Update)
    
    $title = $Update.Title.ToLower()
    $categories = ($Update.Categories | ForEach-Object { $_.Name.ToLower() }) -join ' '
    
    # Critical/Security updates
    if ($categories -match 'critical|security') { return $true }
    
    # Cumulative/Servicing Stack updates
    if ($title -match 'cumulative|monthly.*roll|servicing.?stack|ssu') { return $true }
    
    return $false
}

function Get-UpdateClassification {
    param([Parameter(Mandatory)]$Update)
    
    if (Test-ImportantUpdate $Update) { return '[CRITICAL]' }
    if ($Update.Type -eq 'Driver') { return '[DRIVER]' }
    return '[OPTIONAL]'
}
#endregion

#region Update Processing
function Install-SingleUpdate {
    param(
        [Parameter(Mandatory)]$Update,
        [Parameter(Mandatory)]$Session
    )
    
    $classification = Get-UpdateClassification $Update
    $updateTitle = $Update.Title
    
    # Download phase
    Write-OutputLog "  $classification Downloading: $updateTitle" Yellow
    
    $downloadColl = New-Object -ComObject Microsoft.Update.UpdateColl
    $downloadColl.Add($Update) | Out-Null
    
    $downloader = $Session.CreateUpdateDownloader()
    $downloader.Updates = $downloadColl
    
    try {
        $downloadResult = $downloader.Download()
        
        if (-not $Update.IsDownloaded) {
            Write-OutputLog "    Download failed" Red 'ERROR'
            return $false
        }
        
        Write-OutputLog "    Download is complete" DarkGreen
        
    } catch {
        Write-OutputLog "    Download exception: $($_.Exception.Message)" Red 'ERROR'
        return $false
    } finally {
        if ($downloader) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($downloader) }
        if ($downloadColl) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($downloadColl) }
    }
    
    # Install phase
    # Commented this for clarity
    # Write-OutputLog "  $classification Installing: $updateTitle" Yellow
    
    $installColl = New-Object -ComObject Microsoft.Update.UpdateColl
    $installColl.Add($Update) | Out-Null
    
    $installer = $Session.CreateUpdateInstaller()
    $installer.Updates = $installColl
    
    try {
        $installResult = $installer.Install()
        
        $statusMap = @{
            0 = 'NotStarted'
            1 = 'InProgress'
            2 = 'Installation Succeeded'
            3 = 'SucceededWithErrors'
            4 = 'Failed'
            5 = 'Aborted'
        }
        
        $status = $statusMap[$installResult.ResultCode]
        $rebootMsg = if ($installResult.RebootRequired) { ' [REBOOT REQUIRED]' } else { '' }
        
        switch ($installResult.ResultCode) {
            2 { Write-OutputLog "    $status$rebootMsg" Green; return $true }
            3 { Write-OutputLog "    $status$rebootMsg" Yellow 'WARN'; return $true }
            default { Write-OutputLog "    $status" Red 'ERROR'; return $false }
        }
        
    } catch {
        Write-OutputLog "    Install exception: $($_.Exception.Message)" Red 'ERROR'
        return $false
    } finally {
        if ($installer) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($installer) }
        if ($installColl) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($installColl) }
    }
}

function Invoke-UpdatePass {
    param(
        [Parameter(Mandatory)]
        [int]$PassNumber,
        
        [Parameter(Mandatory)]
        $Session
    )
    
    Write-OutputLog "=== PASS $PassNumber of 3 ===" Magenta
    
    # Search for updates
    $searcher = $Session.CreateUpdateSearcher()
    $searcher.ServerSelection = 2  # Microsoft Update (not WSUS)
    
    try {
        $searchResult = $searcher.Search("IsInstalled=0 and IsHidden=0")
        $updates = $searchResult.Updates
        
        if ($updates.Count -eq 0) {
            Write-OutputLog "No updates found in Pass $PassNumber" Gray
            return $false
        }
        
        Write-OutputLog "Found $($updates.Count) available update(s)" Green
        
    } catch {
        Write-OutputLog "Search failed: $($_.Exception.Message)" Red 'ERROR'
        throw
    } finally {
        if ($searcher) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($searcher) }
    }
    
    # Filter and process updates
    $processedCount = 0
    $successCount = 0
    
    foreach ($update in $updates) {
        # Skip already-processed updates
        $updateID = $update.Identity.UpdateID
        if ($script:ProcessedUpdates.ContainsKey($updateID)) {
            Write-OutputLog "  [SKIPPED] Already processed: $($update.Title)" DarkGray
            continue
        }
    
        # Accept EULA
        if (-not $update.EulaAccepted) {
            try { $update.AcceptEula() } catch { }
        }
    
        # Filter: Feature Updates
        $isFeatureUpdate = ($update.Categories | Where-Object { $_.Name -match 'Feature|Upgrade' }) -or 
        ($update.Title -match 'Feature update|to Windows')
    
        if ($isFeatureUpdate -and -not $IncludeFeatureUpdates) {
            Write-OutputLog "  [SKIPPED] Feature update blocked: $($update.Title)" DarkGray
            continue
        }
    
        # Filter: Driver Safety
        if ($update.Type -eq 'Driver' -and -not (Test-SafeDriver $update)) {
            continue
        }
    
        # Filter: Importance
        $isImportant = Test-ImportantUpdate $update
        if (-not $isImportant -and -not $InstallAll) {
            Write-OutputLog "  [SKIPPED] Optional update (use -InstallAll): $($update.Title)" DarkGray
            continue
        }
    
        # Process update
        $processedCount++
        if (Install-SingleUpdate -Update $update -Session $Session) {
            $script:ProcessedUpdates[$updateID] = $true
            $successCount++
        }
    }
    
    Write-OutputLog "Pass $PassNumber complete: $successCount of $processedCount updates installed successfully" Cyan
    return ($processedCount -gt 0)
}
#endregion

#region Main Execution
try {
    Write-OutputLog "========================================" Cyan
    Write-OutputLog "Windows Update - Enterprise Automation" Cyan
    Write-OutputLog "========================================" Cyan
    Write-OutputLog "Version: 2.0 (Per-Update Processing)" Gray
    Write-OutputLog "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" Gray
    Write-OutputLog "Log: $LogPath" Gray
    Write-OutputLog "---" White
    
    # Configuration summary
    Write-OutputLog "Configuration:" Yellow
    Write-OutputLog "  InstallAll: $InstallAll" Gray
    Write-OutputLog "  SafeDrivers: $SafeDrivers" Gray
    Write-OutputLog "  IncludeFeatureUpdates: $IncludeFeatureUpdates" Gray
    Write-OutputLog "---" White
    
    # Pre-flight checks
    Test-Prerequisites
    Write-OutputLog "Pre-flight checks passed" Green
    Write-OutputLog "---" White
    
    # Initialize COM session
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = "Enterprise WUA - Per-Update v2.0"
    
    # Execute 3 passes
    $anyUpdatesFound = $false
    
    for ($pass = 1; $pass -le 3; $pass++) {
        $foundUpdates = Invoke-UpdatePass -PassNumber $pass -Session $session
        if ($foundUpdates) { $anyUpdatesFound = $true }
        
        if ($pass -lt 3) {
            Write-OutputLog "Waiting 15 seconds for Windows Update to refresh state..." Gray
            Start-Sleep -Seconds 15
            Write-OutputLog "---" White
        }
    }
    
    # Summary
    Write-OutputLog "---" White
    Write-OutputLog "========================================" Green
    Write-OutputLog "ALL 3 PASSES COMPLETED" Green
    Write-OutputLog "========================================" Green
    
    if ($anyUpdatesFound) {
        Write-OutputLog "Updates were processed - check individual results above" Yellow
    } else {
        Write-OutputLog "No updates were required" Green
    }
    
    Write-OutputLog "Log saved: $LogPath" Gray
    
} catch {
    Write-OutputLog "FATAL ERROR: $($_.Exception.Message)" Red 'ERROR'
    Write-OutputLog "Stack Trace: $($_.ScriptStackTrace)" Red 'ERROR'
    exit 1
    
} finally {
    # Cleanup COM objects
    if ($session) {
        try {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($session)
        } catch { }
    }
    
    # Force garbage collection
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
#endregion
