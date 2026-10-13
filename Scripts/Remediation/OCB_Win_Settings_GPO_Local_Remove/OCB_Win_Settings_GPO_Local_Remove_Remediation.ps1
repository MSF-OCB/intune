##################################################################
#  _____                                                   _____ 
# ( ___ )-------------------------------------------------( ___ )
#  |   |                                                   |   | 
#  |   |  █▀▀ █ █ █▀▄ █▀▀ █▀▄ █▀█ █▀▀ █ █  ▀█▀ █▀▀ █▀▀ █ █ |   | 
#  |   |  █    █  █▀▄ █▀▀ █▀▄ █▀█ █   █▀▄   █  █▀▀ █   █▀█ |   | 
#  |   |  ▀▀▀  ▀  ▀▀  ▀▀▀ ▀ ▀ ▀ ▀ ▀▀▀ ▀ ▀ ▀ ▀  ▀▀▀ ▀▀▀ ▀ ▀ |   | 
#  |___|                                                   |___| 
# (_____)-------------------------------------------------(_____)
#
##################################################################
# Authored by: Omar Assaf
# X: omar_assaf
# Please credit the author if you use this script
##################################################################


<#
.SYNOPSIS
    Remove local GPO artifacts from windows devices
.DESCRIPTION
    Safety checks:
    - Verifies Intune enrollment
    - Preserves Intune MDM policies
    - Logs all operations
#>


#Requires -RunAsAdministrator


# Logging
$LogPath = "C:\ProgramData\MSF\Logs\Intune\Remediation\GPO_Local_Remediate.log"
# Create file (and folders if needed) if it doesn't exist
if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType File -Force | Out-Null
}
function Write-Log {
    param($Message, $Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Write-Output $LogMessage
    Add-Content -Path $LogPath -Value $LogMessage -Force
}

Write-Log "=== Local GPO Cleanup Starting ===" "INFO"

#region Pre-flight Safety Checks

function Test-HybridJoinStatus {
    $JoinStatus = @{
        IsHybridJoined = $false
        IsAzureADJoined = $false
        IsDomainJoined = $false
        DomainName = $null
        TenantId = $null
    }
    
    # Check domain join
    try {
        $ComputerSystem = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
        if ($ComputerSystem.PartOfDomain) {
            $JoinStatus.IsDomainJoined = $true
            $JoinStatus.DomainName = $ComputerSystem.Domain
        }
    }
    catch {
        Write-Log "Could not check domain join: $_" "ERROR"
    }
    
    # Check Azure AD join
    try {
        $AzureADJoin = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo\*" -ErrorAction SilentlyContinue
        if ($AzureADJoin) {
            $JoinStatus.IsAzureADJoined = $true
            $JoinStatus.TenantId = $AzureADJoin.TenantId
        }
    }
    catch {
        Write-Log "Could not check Azure AD join: $_" "ERROR"
    }
    
    if ($JoinStatus.IsDomainJoined -and $JoinStatus.IsAzureADJoined) {
        $JoinStatus.IsHybridJoined = $true
    }
    
    return $JoinStatus
}

# Check 1: Verify hybrid join status
$JoinStatus = Test-HybridJoinStatus

Write-Log "Domain Joined: $($JoinStatus.IsDomainJoined) | Domain: $($JoinStatus.DomainName)" "INFO"
Write-Log "Azure AD Joined: $($JoinStatus.IsAzureADJoined) | Tenant: $($JoinStatus.TenantId)" "INFO"
Write-Log "Hybrid Joined: $($JoinStatus.IsHybridJoined)" "INFO"

# Check 2: Verify Intune enrollment
$IntuneEnrolled = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Enrollments\*" -ErrorAction SilentlyContinue | 
    Where-Object { $_.ProviderID -eq "MS DM Server" }

if ($IntuneEnrolled) {
    Write-Log "Intune enrollment verified." "SUCCESS"
}
else {
    Write-Log "Device not enrolled in Intune." "ERROR"
}

#endregion

#region File System Cleanup

Write-Log "--- Starting File System Cleanup ---" "INFO"

$FileSystemPaths = @(
    @{Path = "$env:windir\System32\GroupPolicy"; Desc = "Machine, User, Template, Cache GPO root"},
    @{Path = "$env:windir\System32\GroupPolicyUsers"; Desc = "User GPO cache"},
    @{Path = "C:\WINDOWS\security\Database\secedit.sdb"; Desc = "Secedit database"}
)

foreach ($Item in $FileSystemPaths) {
    if (Test-Path -Path $Item.Path) {
        try {
            Remove-Item -Path $Item.Path -Recurse -Force -ErrorAction Stop
            Write-Log "DELETED: $($Item.Desc) - $($Item.Path)" "SUCCESS"
        }
        catch {
            Write-Log "FAILED: $($Item.Desc) - $($Item.Path) - $_" "ERROR"
        }
    }
    else {
        Write-Log "NOT FOUND: $($Item.Desc) - $($Item.Path)" "INFO"
    }
}

#endregion

#region Registry Cleanup

Write-Log "--- Starting Registry Cleanup ---" "INFO"

$RegistryPaths = @(
    "HKLM:\Software\Policies\Microsoft\Windows",
    "HKLM:\Software\Microsoft\Policies",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies",
    "HKLM:\Software\Microsoft\WindowsSelfHost",
    "HKLM:\Software\WOW6432Node\Microsoft\Policies",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies",
    "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
)

# Protected paths - DO NOT DELETE
$ExcludedPatterns = @(
    "*\PolicyManager\*",
    "*\Enrollments\*",
    "*\Provisioning\*",
    #"*\OneDrive*",
    "*\SystemCertificates\*"
)

foreach ($RegPath in $RegistryPaths) {
    if (Test-Path $RegPath) {
        Write-Log "Processing: $RegPath" "INFO"
        
        try {
            $Children = Get-ChildItem -Path $RegPath -Recurse -ErrorAction SilentlyContinue
            $DeletedCount = 0
            $SkippedCount = 0
            
            foreach ($Child in $Children) {
                # Check exclusions
                $ShouldExclude = $false
                foreach ($Pattern in $ExcludedPatterns) {
                    if ($Child.PSPath -like $Pattern) {
                        $ShouldExclude = $true
                        $SkippedCount++
                        break
                    }
                }
                
                if (-not $ShouldExclude) {
                    try {
                        Remove-Item -Path $Child.PSPath -Recurse -Force -ErrorAction Stop
                        $DeletedCount++
                    }
                    catch [System.UnauthorizedAccessException] {
                        Write-Log "ACCESS DENIED (protected): $($Child.PSPath)" "WARN"
                    }
                    catch {
                        Write-Log "FAILED: $($Child.PSPath) - $_" "ERROR"
                    }
                }
            }
            
            Write-Log "Processed $RegPath - Deleted: $DeletedCount | Skipped: $SkippedCount" "INFO"
            
            # Remove parent if empty
            try {
                $Remaining = Get-ChildItem -Path $RegPath -ErrorAction SilentlyContinue
                if ($Remaining.Count -eq 0) {
                    Remove-Item -Path $RegPath -Force -ErrorAction Stop
                    Write-Log "REMOVED EMPTY: $RegPath" "SUCCESS"
                }
            }
            catch {
                Write-Log "Could not remove parent: $RegPath - $_" "WARN"
            }
        }
        catch {
            Write-Log "ERROR processing $RegPath - $_" "ERROR"
        }
    }
    else {
        Write-Log "NOT FOUND: $RegPath" "INFO"
    }
}

#endregion

#region Orphaned Artifacts Cleanup

Write-Log "--- Cleaning Orphaned Artifacts ---" "INFO"

$OrphanedPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\History",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\History"
)

foreach ($Path in $OrphanedPaths) {
    if (Test-Path $Path) {
        try {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-Log "REMOVED: $Path" "SUCCESS"
        }
        catch {
            Write-Log "FAILED: $Path - $_" "ERROR"
        }
    }
}

#endregion

#region Post-Cleanup Actions

Write-Log "--- Running Post-Cleanup Actions ---" "INFO"

# Force gpupdate
try {
    $gpResult = & gpupdate.exe /force 2>&1 | Out-String
    Write-Log "gpupdate executed successfully" "SUCCESS"
    $regPath = 'HKLM:\SOFTWARE\MSFOCB\Intune\Remediation'
    New-Item -Path $regPath -Force | New-ItemProperty -Name 'LocalGroupPolicyCleaned' -Value 1 -PropertyType DWord -Force | Out-Null
}
catch {
    Write-Log "gpupdate failed: $_" "ERROR"
}

# Trigger Intune sync
Write-Log "Triggering Intune policy sync..." "INFO"

# Method 1: Scheduled task
try {
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*PushLaunch*" } | Start-ScheduledTask
    Write-Log "Intune sync triggered via scheduled task" "SUCCESS"
}
catch {
    Write-Log "Could not trigger via scheduled task: $_" "WARN"
}

# Method 2: IME
$IMEPath = "$env:ProgramFiles\Microsoft Intune Management Extension\Microsoft.Management.Services.IntuneWindowsAgent.exe"
if (Test-Path $IMEPath) {
    try {
        Start-Process -FilePath $IMEPath -ArgumentList "/sync" -NoNewWindow -Wait
        Write-Log "Intune sync triggered via IME" "SUCCESS"
    }
    catch {
        Write-Log "Could not trigger via IME: $_" "WARN"
    }
}

#endregion

#region Summary

Write-Log "=== Cleanup Complete ===" "INFO"
Write-Log "Log saved: $LogPath" "INFO"

# Check for critical errors
$LogContent = Get-Content $LogPath -Raw
$ErrorCount = ([regex]::Matches($LogContent, "\[ERROR\]")).Count

if ($ErrorCount -gt 0) {
    Write-Log "WARNING: $ErrorCount errors occurred. Review log file." "WARN"
}
else {
    Write-Log "Cleanup completed successfully" "SUCCESS"
}


#endregion
