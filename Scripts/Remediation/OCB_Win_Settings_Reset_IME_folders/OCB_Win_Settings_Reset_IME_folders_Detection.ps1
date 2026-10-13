<#
.SYNOPSIS
    Detect stuck Intune Management Extension downloads.

.DESCRIPTION
    Flags remediation if files exist AND are stale.

    Exit 1 = Stuck content detected
    Exit 0 = Healthy state
#>

$ErrorActionPreference = "SilentlyContinue"

$StaleMinutes = 60
$Now = Get-Date

$Paths = @(
    "C:\ProgramData\Microsoft\IntuneManagementExtension\Staging",
    "C:\Program Files (x86)\Microsoft Intune Management Extension\Content\Incoming",
    "C:\Program Files (x86)\Microsoft Intune Management Extension\Content\Staging"
)

$stuckDetected = $false

foreach ($Path in $Paths) {

    if (Test-Path $Path) {

        $files = Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue

        if ($files -and $files.Count -gt 0) {

            $latestFile = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1

            if (-not $latestFile) {
                Write-Output "No valid files found in $Path after scan"
                continue
            }

            $ageMinutes = ($Now - $latestFile.LastWriteTime).TotalMinutes

            Write-Output "Path: $Path"
            Write-Output "Latest file: $($latestFile.FullName)"
            Write-Output "Last modified: $($latestFile.LastWriteTime)"
            Write-Output "Age (minutes): $([int]$ageMinutes)"

            if ($ageMinutes -ge $StaleMinutes) {
                Write-Output "Stale content detected in $Path"
                $stuckDetected = $true
            }
            else {
                Write-Output "Active download detected"
            }
        }
        else {
            Write-Output "No files in $Path"
        }
    }
    else {
        Write-Output "Path not found: $Path"
    }
}

if ($stuckDetected) {
    Write-Output "Stuck IME download detected"
    exit 1
}
else {
    Write-Output "IME activity healthy"
    exit 0
}
