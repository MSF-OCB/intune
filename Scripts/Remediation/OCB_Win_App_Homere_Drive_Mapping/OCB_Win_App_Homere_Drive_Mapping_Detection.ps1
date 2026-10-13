# Homere Mapping detection script for Intune

$HomereMappingVersion = "V7"
$NamePrefix = "Homere_Mapping"

$TaskName = "${NamePrefix}_${HomereMappingVersion}"
$TaskPath = "\MSFOCB\"

$ScriptFolder = "C:\Program Files (x86)\MSF\Homere"
$ScriptPath = Join-Path -Path $ScriptFolder -ChildPath "$TaskName.ps1"

# Check if the expected script exists
$ScriptExists = Test-Path -Path $ScriptPath

# Check if the scheduled task exists
$ScheduledTaskExists = $null -ne (Get-ScheduledTask `
        -TaskName $TaskName `
        -TaskPath $TaskPath `
        -ErrorAction SilentlyContinue)

# Check for unexpected Homere_Mapping files in the script folder
$UnexpectedFiles = Get-ChildItem `
    -Path $ScriptFolder `
    -File `
    -Filter "$NamePrefix*" `
    -ErrorAction SilentlyContinue |
Where-Object {
    $_.FullName -ne $ScriptPath
}

# Device is compliant only when:
# 1. Correct script exists
# 2. Correct scheduled task exists
# 3. No additional Homere_Mapping files exist
if ($ScriptExists -and $ScheduledTaskExists -and (-not $UnexpectedFiles)) {
    Write-Host "Homere mapping configuration is compliant."
    exit 0
}

Write-Host "Homere mapping configuration is not compliant."
exit 1
