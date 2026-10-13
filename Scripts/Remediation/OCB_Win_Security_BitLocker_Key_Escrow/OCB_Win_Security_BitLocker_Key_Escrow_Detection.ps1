##################################################################
#   _______     ______  ______ _____            _____ _  _________ ______ _____ _    _ 
#  / ____\ \   / /  _ \|  ____|  __ \     /\   / ____| |/ /__   __|  ____/ ____| |  | |
# | |     \ \_/ /| |_) | |__  | |__) |   /  \ | |    | ' /   | |  | |__ | |    | |__| |
# | |      \   / |  _ <|  __| |  _  /   / /\ \| |    |  <    | |  |  __|| |    |  __  |
# | |____   | |  | |_) | |____| | \ \  / ____ \ |____| . \ _ | |  | |___| |____| |  | |
#  \_____|  |_|  |____/|______|_|  \_\/_/    \_\_____|_|\_(_)|_|  |______\_____|_|  |_|
#
##################################################################
# Authored by: Omar Assaf
# X: omar_assaf
# Please credit the author if you use this script
##################################################################


<#
.SYNOPSIS
    Escrow BitLocker Recovery Password protectors to Microsoft Entra ID.
#>

$LogFolder = 'C:\ProgramData\MSF\Logs\Intune\Remediation'
$LogFile = Join-Path $LogFolder 'Bitlocker_escrow.log'

if (!(Test-Path $LogFolder)) { New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null }

if (Test-Path $LogFile) {
    if ((Get-Item $LogFile).Length -gt 1MB) {
        $Archive = "$LogFile.old"
        Remove-Item $Archive -Force -ErrorAction SilentlyContinue
        Rename-Item -Path $LogFile -NewName (Split-Path $Archive -Leaf)
    }
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',
        [switch]$NoTimestamp,
        [switch]$BlankLine
    )
    if ($BlankLine) { Add-Content $LogFile ''; return }
    if ($NoTimestamp) { Add-Content $LogFile $Message; return }
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content $LogFile "[$ts] [$Level] $Message"
}

try {
    Write-Log ('=' * 60) -NoTimestamp
    Write-Log 'Starting BitLocker Recovery Key Escrow'
    Write-Log ('-' * 60) -NoTimestamp

    if (-not ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem)) {
        throw 'This script must be run as SYSTEM.'
    }
    Write-Log 'Running as SYSTEM.'

    if (-not (Get-Command BackupToAAD-BitLockerKeyProtector -ErrorAction SilentlyContinue)) {
        throw 'BackupToAAD-BitLockerKeyProtector cmdlet is not available.'
    }
    Write-Log 'Verified BackupToAAD-BitLockerKeyProtector cmdlet.'

    $Volumes = Get-BitLockerVolume | Where-Object {
        $_.VolumeType -in @('OperatingSystem', 'FixedData') -and $_.ProtectionStatus -eq 'On'
    }

    if (-not $Volumes) {
        Write-Log 'No BitLocker-protected operating system or fixed data volumes found.' WARN
        Write-Output 'No BitLocker-protected operating system or fixed data volumes found.'
        exit 0
    }

    Write-Log "Found $($Volumes.Count) protected BitLocker volume(s)."
    $EscrowedCount = 0

    foreach ($Volume in $Volumes) {
        Write-Log -BlankLine
        Write-Log "Processing volume $($Volume.MountPoint)"

        $RecoveryProtectors = $Volume.KeyProtector | Where-Object KeyProtectorType -EQ 'RecoveryPassword'

        if (-not $RecoveryProtectors) {
            Write-Log 'No Recovery Password protector found. Skipping.' WARN
            Write-Output "[$($Volume.MountPoint)] No Recovery Password protector found. Skipping."
            continue
        }

        foreach ($Protector in $RecoveryProtectors) {
            BackupToAAD-BitLockerKeyProtector -MountPoint $Volume.MountPoint -KeyProtectorId $Protector.KeyProtectorId -ErrorAction Stop | Out-Null
            $EscrowedCount++
            Write-Log "Recovery key escrowed successfully for $($Volume.MountPoint)." SUCCESS
            Write-Output "[$($Volume.MountPoint)] Recovery Password protector escrowed."
        }
    }

    Write-Log 'Cleaning up old log files.' INFO
    Get-ChildItem -Path $LogFolder -File |
    Where-Object {
        $_.Name -like 'Script_Remediate_Bitlocker_Backup_*' -or
        $_.Name -like 'Script_Detect_Bitlocker_Backup_*'
    } |
    ForEach-Object {
        Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
    }
    Write-Log ('-' * 60) -NoTimestamp
    Write-Log 'Completed successfully.' SUCCESS
    Write-Log "Recovery Password protectors escrowed: $EscrowedCount"
    Write-Log ('=' * 60) -NoTimestamp
    Write-Output "Completed successfully. Recovery Password protectors escrowed: $EscrowedCount."
    exit 0
}
catch {
    Write-Log ('-' * 60) -NoTimestamp
    Write-Log $_.Exception.Message ERROR
    Write-Log 'Script failed.' ERROR
    Write-Log ('=' * 60) -NoTimestamp
    Write-Error $_.Exception.Message
    exit 1
}

