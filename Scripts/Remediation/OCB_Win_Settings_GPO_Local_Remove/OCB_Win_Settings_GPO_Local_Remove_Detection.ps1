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


#Requires -RunAsAdministrator

# Declare Microsoft Tenant ID for Autopilot detection
$Msftenant = "4d9dd1af-83ce-4e9b-b090-b0543ccc2b31"
$TenantId = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\AutoPilot" -ErrorAction SilentlyContinue ).CloudAssignedTenantId
if ($TenantId -eq $Msftenant) {
    Write-Log "Device is Autopilot. No remediation needed." "INFO"
    Exit 0
}

# Detection: Check if local GPO has been manually configured
$LocalGPOActive = $false
$Reasons = @()

# 1. PRIMARY CHECK: Registry.pol files (definitive proof gpedit.msc was used)
$MachinePol = "$env:windir\System32\GroupPolicy\Machine\Registry.pol"
$UserPol = "$env:windir\System32\GroupPolicy\User\Registry.pol"

if (Test-Path $MachinePol) {
    $FileSize = (Get-Item $MachinePol).Length
    if ($FileSize -gt 4) {  # Empty pol files are 4 bytes (header only)
        $Reasons += "Machine Registry.pol exists ($FileSize bytes)"
        $LocalGPOActive = $true
    }
}

if (Test-Path $UserPol) {
    $FileSize = (Get-Item $UserPol).Length
    if ($FileSize -gt 4) {
        $Reasons += "User Registry.pol exists ($FileSize bytes)"
        $LocalGPOActive = $true
    }
}

# 2. SECONDARY CHECK: gpt.ini version (indicates policies were set)
$GPTini = "$env:windir\System32\GroupPolicy\gpt.ini"
if (Test-Path $GPTini) {
    $Content = Get-Content $GPTini -Raw -ErrorAction SilentlyContinue
    # Version increments each time gpedit.msc applies changes
    if ($Content -match "Version=([1-9]\d*)") {
        $Version = $matches[1]
        $Reasons += "gpt.ini version: $Version (policies applied)"
        $LocalGPOActive = $true
    }
}

# 3. TERTIARY CHECK: Common manually-configured policy locations
$ManualPolicyPaths = @(
    "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate",
    "HKLM:SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3",
    "HKLM:\Software\Policies\Microsoft\Windows\Personalization" # Lock Screen policies
)

foreach ($Path in $ManualPolicyPaths) {
    if (Test-Path $Path) {
        $Properties = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
        # Check if it has actual policy values (not just the key existing)
        $PolicyValues = $Properties.PSObject.Properties | Where-Object { 
            $_.Name -notmatch "^PS" -and $_.Name -ne "" 
        }
        
        if ($PolicyValues.Count -gt 0) {
            $Reasons += "Manual policy found: $Path ($($PolicyValues.Count) settings)"
            $LocalGPOActive = $true
        }
    }
}

# Output and exit
if ($LocalGPOActive) {
    Write-Output "Local GPO manually configured - remediation needed:"
    $Reasons | ForEach-Object { Write-Output "  - $_" }
    Exit 1  # Trigger remediation
}
else {
    Write-Output "No manual local GPO configuration detected"
    Exit 0  # Compliant
}
