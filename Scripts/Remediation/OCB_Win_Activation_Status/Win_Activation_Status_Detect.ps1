$ErrorActionPreference = 'Stop'

$LogFolder = 'C:\ProgramData\MSF\Logs'
$LogFile = Join-Path $LogFolder 'WindowsLicenseAssessment.log'

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )

    if (-not (Test-Path $LogFolder)) {
        New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$timestamp [$Level] $Message" | Set-Content -Path $LogFile -Encoding utf8
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $edition = $os.Caption

    $licenses = Get-CimInstance -ClassName SoftwareLicensingProduct | Where-Object {
        $_.PartialProductKey -and
        $_.ApplicationID -eq '55c92734-d682-4d71-983e-d6ec3f16059f' -and
        $_.Name -match 'Windows'
    }

    if (-not $licenses) {
        $result = [PSCustomObject]@{
            Status        = 'Unknown'
            Edition       = $edition
            Channel       = 'Unknown'
            LicenseStatus = 'Unknown'
            Description   = ''
            Message       = 'No Windows licensing product found.'
        }

        Write-Log -Level 'WARN' -Message "Status='$($result.Status)'; Edition='$($result.Edition)'; Channel='$($result.Channel)'; LicenseStatus='$($result.LicenseStatus)'; Message='$($result.Message)'"
        Write-Output ($result | ConvertTo-Json -Compress)
        exit 1
    }

    $license = $licenses | Sort-Object -Property LicenseStatus -Descending | Select-Object -First 1
    $description = [string]$license.Description
    $licenseStatusCode = [int]$license.LicenseStatus

    $licenseStatusText = switch ($licenseStatusCode) {
        0 { 'Unlicensed' }
        1 { 'Licensed' }
        2 { 'OOBGrace' }
        3 { 'OOTGrace' }
        4 { 'NonGenuineGrace' }
        5 { 'Notification' }
        6 { 'ExtendedGrace' }
        default { "Unknown_$licenseStatusCode" }
    }

    $channel = 'Unknown'
    if ($description -match 'VOLUME_KMSCLIENT') {
        $channel = 'KMS'
    }
    elseif ($description -match 'VOLUME_MAK') {
        $channel = 'MAK'
    }
    elseif ($description -match 'OEM_DM|OEM') {
        $channel = 'OEM'
    }
    elseif ($description -match 'RETAIL') {
        $channel = 'Retail'
    }
    elseif ($description -match 'TIMEBASED_SUB|SUBSCRIPTION') {
        $channel = 'Subscription'
    }

    $status = 'Unknown'
    $message = 'Unable to clearly determine activation scenario.'

    if ($channel -eq 'KMS' -and $licenseStatusCode -eq 1) {
        $status = 'KMS_Activated'
        $message = 'Machine is configured for KMS and activation is successful.'
    }
    elseif ($channel -eq 'KMS' -and $licenseStatusCode -ne 1) {
        $status = 'KMS_NotActivated'
        $message = 'Machine is configured for KMS but activation is not successful.'
    }
    elseif ($channel -in @('OEM', 'Retail', 'Subscription', 'MAK') -and $licenseStatusCode -eq 1) {
        $status = 'OK'
        $message = 'Machine is properly activated without KMS dependency.'
    }
    elseif ($channel -in @('OEM', 'Retail', 'Subscription', 'MAK') -and $licenseStatusCode -ne 1) {
        $status = 'NonKMS_NotActivated'
        $message = 'Machine is not using KMS and is not properly activated.'
    }

    $result = [PSCustomObject]@{
        Status        = $status
        Edition       = $edition
        Channel       = $channel
        LicenseStatus = $licenseStatusText
        Description   = $description
        Message       = $message
    }

    Write-Log -Message "Status='$($result.Status)'; Edition='$($result.Edition)'; Channel='$($result.Channel)'; LicenseStatus='$($result.LicenseStatus)'; Message='$($result.Message)'"

    Write-Output ($result | ConvertTo-Json -Compress)

    if ($status -in @('OK', 'KMS_Activated')) {
        exit 0
    }
    else {
        exit 1
    }
}
catch {
    $result = [PSCustomObject]@{
        Status        = 'Error'
        Edition       = 'Unknown'
        Channel       = 'Unknown'
        LicenseStatus = 'Unknown'
        Description   = ''
        Message       = $_.Exception.Message
    }

    Write-Log -Level 'ERROR' -Message "Status='$($result.Status)'; Message='$($result.Message)'"
    Write-Output ($result | ConvertTo-Json -Compress)
    exit 1
}