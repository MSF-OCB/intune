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


#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
$regPath = 'HKLM:\SOFTWARE\MSFOCB\Intune'
$MsfRegKeyValue = 'IntuneDeviceRename'
$MsfRenameVer = '3'

Try {
    Start-Transcript "C:\ProgramData\MSF\Logs\Intune\Scripts\RenameComputer.log" -Force -ErrorAction Stop > $null
}
catch {
    Start-Transcript "C:\ProgramData\MSF\Logs\Intune\Scripts\RenameComputer.log" -Force > $null
}

# Check if device was already renamed
$RenameStatus = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue ).$MsfRegKeyValue
if ($RenameStatus -eq $MsfRenameVer) {
    Write-Host "Device is already renamed. No further action needed."
    Stop-Transcript
    Exit 0
}


# Configuration
$config = @{
    Company   = 'OCB'
    MaxLength = 15
    CsvUrl    = 'https://msfocbshare.blob.core.windows.net/ict-sd/data/ComputerName.csv'
    JsonUrl   = 'https://msfocbshare.blob.core.windows.net/ict-prod/Intune/Enroll/Helpers/MSFOCB_Project_Subnets.json'
    GeoUrl    = 'https://ident.me/json'
}


function Write-Status($msg, $color = 'Cyan') {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" -ForegroundColor $color
}

function ConvertTo-UInt32([string]$ip) {
    $bytes = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
    [Array]::Reverse($bytes)
    [BitConverter]::ToUInt32($bytes, 0)
}

function Test-IPInCIDR([string]$ip, [string]$cidr) {
    if ($cidr -notmatch '^(.+)/(\d{1,2})$') { return $false }
    
    $network = $matches[1]
    $prefix = [int]$matches[2]
    $ipInt = ConvertTo-UInt32 $ip
    $netInt = ConvertTo-UInt32 $network
    $mask = if ($prefix -eq 0) { 0 } else { [uint32]([Math]::Pow(2, 32) - 1) - [uint32]([Math]::Pow(2, (32 - $prefix)) - 1) }
    
    (($ipInt -band $mask) -eq ($netInt -band $mask))
}

try {
    # Get serial number
    $SerialOem = (Get-CimInstance Win32_BIOS).SerialNumber.Trim()
    Write-Status "Serial: $SerialOem"
    if ($SerialOem.Length -gt 9 -or $SerialOem -match '\s') {
        $SerialName = (($SerialOem -replace ' ', '')[-9..-1] -join '').ToUpper()
        Write-Status "Truncated Serial: $SerialName" -color Yellow
    }
    else {
        $SerialName = $SerialOem
    }

    $name = $null
    
    # Priority 1: Asset Tag
    try {
        $response = Invoke-WebRequest $config.CsvUrl -UseBasicParsing -TimeoutSec 20
        # Handle BOM for PowerShell 5.1 & 7+
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $csvText = [Text.Encoding]::UTF8.GetString($response.Content, $true)
        }
        else {
            $csvText = [Text.Encoding]::UTF8.GetString($response.Content)
            if ($csvText.StartsWith("ï»¿")) { $csvText = $csvText.Substring(3) }
        }
        $csv = $csvText | ConvertFrom-Csv
        # Find row by serial
        $row = $csv | Where-Object { $_.Serial.ToString().Trim() -ieq $SerialOem } | Select-Object -First 1
        if ($row.AssetTag) {
            $name = $row.AssetTag.ToString().Trim().ToUpper()
            Write-Status "Asset tag found: $name" -color Green
        }
        else {
            Write-Status "No asset tag found for serial in the CSV" -color Yellow
        }
    }
    catch {
        Write-Status "Asset lookup failed: $_" -color Yellow
    }
    
    # Priority 2: CIDR Match
    if (-not $name) {
        try {
            $ip = (Get-NetIPAddress -AddressFamily IPv4 | 
                Where-Object { 
                    $_.IPAddress -ne '127.0.0.1' -and 
                    $_.IPAddress -notlike '169.254.*' -and 
                    $_.AddressState -eq 'Preferred' -and
                    $_.InterfaceAlias -notmatch 'vEthernet|VirtualBox|Hyper-V|Docker|VPN|Tunnel|Loopback|Bluetooth'
                } | 
                Sort-Object InterfaceMetric | 
                Select-Object -First 1).IPAddress
            
            Write-Status "Local IP: $ip"
            
            $json = Invoke-RestMethod $config.JsonUrl -UseBasicParsing -TimeoutSec 10
            $matches = @()
            
            foreach ($country in $json) {
                foreach ($proj in $country.Projects) {
                    if (Test-IPInCIDR $ip $proj.IP_CIDR) {
                        $proj.IP_CIDR -match '/(\d+)$' | Out-Null
                        $matches += @{
                            Country = $country.Country
                            Project = $proj.ProjectCode
                            Prefix  = [int]$matches[1]
                        }
                    }
                }
            }
            
            if ($matches.Count -gt 0) {
                $best = $matches | Sort-Object Prefix -Descending | Select-Object -First 1
                $name = "$($config.Company)-$($best.Country)$SerialName".ToUpper()
                Write-Status "CIDR match: $($best.Country)/$($best.Project)" -color Green
            } else {
                Write-Status "No CIDR match found" -color Yellow
            }
        }
        catch {
            Write-Status "CIDR lookup failed: $_" -color Yellow
        }
    }
    
    # Priority 3: GeoIP Fallback
    if (-not $name) {
        try {
            $geo = (Invoke-RestMethod $config.GeoUrl -UseBasicParsing -TimeoutSec 20).cc
            <#
            if ($geo -ieq 'BE'){
                $geo = 'XX'
                Write-Status "GeoIP country: BE, XX will replace it" -color Cyan
            }
            #>
        }
        catch {
            $geo = 'XX'
            Write-Status "GeoIP failed, using XX" -color Yellow
        }

        $name = "$($config.Company)-$geo$SerialName".ToUpper()
        Write-Status "Fallback mode, Country: $geo" -color Yellow
    }
    
    # Apply name
    if ($env:COMPUTERNAME -eq $name) {
        Write-Status "Name already correct: $name" -color Green
        New-Item -Path $regPath -Force | New-ItemProperty -Name $MsfRegKeyValue -Value $MsfRenameVer -PropertyType DWord -Force | Out-Null
    }
    elseif ($DryRun) {
        Write-Status "[DRY RUN] Would rename: $env:COMPUTERNAME -> $name" -color Magenta
    }
    else {
        Rename-Computer -NewName $name -Force
        Write-Status "Renamed to: $name [RESTART REQUIRED]" -color Green
        New-Item -Path $regPath -Force | New-ItemProperty -Name $MsfRegKeyValue -Value $MsfRenameVer -PropertyType DWord -Force | Out-Null
    }
    Stop-Transcript
    exit 0
}
catch {
    Write-Status "FATAL: $_" -color Red
    Stop-Transcript
    exit 1
}