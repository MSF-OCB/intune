# Function to check if device was provisioned via Autopilot
function Test-AutopilotProvisioning {
    try {
        $autoPilot = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo" -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# Check Autopilot provisioning
if (Test-AutopilotProvisioning) {
    Write-Output "Device is provisioned via Autopilot. No further checks needed."
    exit 0
}

# Define registry path for PassportForWork
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork"

# Check PassportForWork registry key and values
if (Test-Path $regPath) {
    $enabled = Get-ItemProperty -Path $regPath -Name "Enabled" -ErrorAction SilentlyContinue
    $disablePostLogon = Get-ItemProperty -Path $regPath -Name "DisablePostLogonProvisioning" -ErrorAction SilentlyContinue

    if ($enabled -eq 0 -and $disablePostLogon -eq 1) {
        Write-Output "PassportForWork policy is correctly configured on a non-Autopilot device."
        exit 0
    } else {
        Write-Output "PassportForWork policy is present but values are incorrect on a non-Autopilot device."
        exit 1
    }
} else {
    Write-Output "PassportForWork policy registry key does not exist on a non-Autopilot device."
    exit 1
}

