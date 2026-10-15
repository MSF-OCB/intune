#Requires -Version 5.1

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
    Windows Computer Naming Engine

.DESCRIPTION
   Determine and apply the correct Windows computer name using a deterministic decision pipeline.

.NOTES
   Architecture:

   1. Collect device facts
   2. Block unsupported device states
   3. Resolve authoritative asset identity
   4. Resolve network location
   5. Classify device type
   6. Generate candidate computer name
   7. Validate candidate
   8. Decide: RENAME / ALREADY_CORRECT / BLOCK
   9. Apply rename
  10. Persist pending state
  11. On subsequent run, confirm the rename

 Naming priority:

   Asset CSV
       ↓
   Autopilot / Device Type policy
       ↓
   Location (CIDR preferred, GeoIP fallback)
       ↓
   Deterministic hostname generation

 Important design principles:

   - Discovery functions discover facts.
   - Classification functions classify facts.
   - Naming functions generate names.
   - Validation functions validate names.
   - Rename function only applies an already-approved name.
   - No random hostname generation.
   - Ambiguous data does not result in an automatic rename.
   - Repeated execution is idempotent.

.Author
   Omar Assaf

.Version
    2026-10-15 Added improved idiom for detection.
    2026-09-04 Modified search for serial number in CSV to be more robust and avoid false negatives.
    2026-08-10 Added support for new Autopilot profiles and improved logging.
    2026-07-22 Improved logging and error handling for CSV download and parsing.

#>


###################################################################################################

$ErrorActionPreference = 'Stop'

# ============================================================
# Configuration
# ============================================================
$ScriptName = 'Rename_Device'
$script:Company = 'OCB'

[string]$script:MetadataBlobUrl = 'https://msfocbshare.blob.core.windows.net/ict-prod/Intune/Enroll/Helpers/MSFOCB_Project_Subnets.json'
[string]$script:CsvBlobUrl = 'https://msfocbshare.blob.core.windows.net/ict-sd/data/ComputerName.csv'
[string]$script:GeoUrl = 'https://ident.me/json'

$LogDirectory = 'C:\ProgramData\MSF\Logs\Intune\Scripts'
$script:LogFilePath = $null

$AutopilotProfilesForNaming = @(
    'OCB_AP_SD_ML',
    'OCB_AP_SD_UF'
)


$MsfOcbRegPathIntune = 'HKLM:\SOFTWARE\MSFOCB\Intune'
$MsfOcbRegKeyValueRename = 'IntuneDeviceRename'
#$MsfOcbRegDataRenameVer = '3'

$RegPathSysNameCurrent = "HKLM:\SYSTEM\CurrentControlSet\Control\Computername\ActiveComputername"
$RegPathSysNameNew = "HKLM:\SYSTEM\CurrentControlSet\Control\Computername\Computername"
$RegKeySysValueName = "Computername"

# ============================================================
# Logging
# ============================================================

function Initialize-LogFile {

    try {
        if (-not (Test-Path -LiteralPath $LogDirectory)) {
            New-Item `
                -Path $LogDirectory `
                -ItemType Directory `
                -Force `
                -ErrorAction Stop |
            Out-Null
        }

        $script:LogFilePath = Join-Path `
            -Path $LogDirectory `
            -ChildPath "$ScriptName.log"

        if (-not (Test-Path -LiteralPath $script:LogFilePath)) {
            New-Item `
                -Path $script:LogFilePath `
                -ItemType File `
                -Force `
                -ErrorAction Stop |
            Out-Null
        }
    }
    catch {
        throw "Failed to initialize log file: $($_.Exception.Message)"
    }
}


function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped colour-coded log line to the host.

    .DESCRIPTION
        Uses Write-Host exclusively -- this keeps output off the pipeline so it
        never pollutes function return values. Start-Transcript captures
        Write-Host in PS 5.1+ including Intune SYSTEM sessions.

    .PARAMETER Message
        Text to log.

    .PARAMETER Level
        Severity: Info, Success, Warning, Error, Debug. Defaults to Info.
    #>


    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info'
    )

    try {
        if (-not $script:LogFilePath) {
            Initialize-LogFile
        }

        $labelMap = @{
            Info    = 'INFO   '
            Success = 'SUCCESS'
            Warning = 'WARNING'
            Error   = 'ERROR  '
            Debug   = 'DEBUG  '
        }

        $colorMap = @{
            Info    = 'Gray'
            Success = 'Green'
            Warning = 'Yellow'
            Error   = 'Red'
            Debug   = 'Cyan'
        }

        $logLine = "[{0}] [{1}] {2}" -f `
        (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), `
            $labelMap[$Level], `
            $Message

        Write-Host $logLine -ForegroundColor $colorMap[$Level]

        $logLine |
        Out-File `
            -FilePath $script:LogFilePath `
            -Append `
            -NoClobber `
            -Force `
            -Encoding UTF8 `
            -ErrorAction Stop
    }
    catch {
        # Logging must never prevent the rename process.
    }
}

function Write-RenameRegistryVersion {
    <#
    .SYNOPSIS

    .DESCRIPTION
        
    .PARAMETER Message
        
    #>


    if (-not (Test-Path -Path $MsfOcbRegPathIntune)) {
        New-Item -Path $MsfOcbRegPathIntune -Force -ErrorAction Stop | Out-Null
    }
    # During Autopilot provisioning, Intune may not have created the registry key yet. If it doesn't exist, create it and set the version to 0.
    # If it does exist, increment the version by 1 on each subsequent run.
    $ExistingValue = Get-ItemProperty -Path $MsfOcbRegPathIntune -ErrorAction Stop
    if ($ExistingValue.PSObject.Properties.Name -contains $MsfOcbRegKeyValueRename) {
        [int]$MsfOcbRegDataRenameVer = [int]$ExistingValue.$MsfOcbRegKeyValueRename + 1
    }
    else {
        [int]$MsfOcbRegDataRenameVer = 0
    }
    New-ItemProperty `
        -Path $MsfOcbRegPathIntune `
        -Name $MsfOcbRegKeyValueRename `
        -Value $MsfOcbRegDataRenameVer `
        -PropertyType DWord `
        -Force `
        -ErrorAction Stop |
    Out-Null
    Write-Log "Intune registry key for naming had been updated to version: $MsfOcbRegDataRenameVer" -Level Success

}

# ============================================================
# IPv4 conversion
# ============================================================

function ConvertTo-UInt32 {
    <#
    .SYNOPSIS
        Converts a dotted-decimal IPv4 string to an unsigned 32-bit integer.

    .DESCRIPTION
        Required for bitwise subnet math in Test-IpInCidr.
        Validates each octet range before converting.

    .PARAMETER IPv4Address
        Dotted-decimal IPv4 string, e.g. "10.210.24.8".

    .OUTPUTS
        [uint32]

    .EXAMPLE
        ConvertTo-UInt32 '10.0.0.1'   # returns 167772161
    #>


    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}$')]
        [string]$IPv4Address
    )

    [string[]]$octets = $IPv4Address.Split('.')

    foreach ($octet in $octets) {

        [int]$value = [int]$octet

        if ($value -lt 0 -or $value -gt 255) {
            throw "Invalid IPv4 octet '$octet' in '$IPv4Address'."
        }
    }

    return [uint32](
        ([uint32]$octets[0] -shl 24) -bor
        ([uint32]$octets[1] -shl 16) -bor
        ([uint32]$octets[2] -shl 8) -bor
        ([uint32]$octets[3])
    )
}


# ============================================================
# CIDR parsing
# ============================================================

function Split-CIDR {
    <#
    .SYNOPSIS
        Splits a CIDR string into network address and prefix length.

    .DESCRIPTION
        Uses explicit named capture groups -- never relies on the automatic
        $Matches variable which can be corrupted by prior -match calls in scope.

    .PARAMETER CIDR
        CIDR string, e.g. "10.210.24.0/22".

    .OUTPUTS
        [hashtable] with keys: Network [string], Prefix [int]

    .EXAMPLE
        $p = Split-CIDR '10.210.24.0/22'
        $p.Network   # '10.210.24.0'
        $p.Prefix    # 22
    #>


    param(
        [Parameter(Mandatory)]
        [string]$CIDR
    )

    if ($CIDR -notmatch '^(?<network>[0-9]{1,3}(?:\.[0-9]{1,3}){3})\/(?<prefix>[0-9]{1,2})$') {
        throw "Malformed CIDR '$CIDR'."
    }

    [string]$network = $Matches['network']
    [int]$prefix = [int]$Matches['prefix']

    if ($prefix -lt 0 -or $prefix -gt 32) {
        throw "Invalid prefix '$prefix' in CIDR '$CIDR'."
    }

    return @{
        Network = $network
        Prefix  = $prefix
    }
}


# ============================================================
# Test IP against CIDR
# ============================================================

function Test-IpInCidr {
    <#
    .SYNOPSIS
        Tests whether an IPv4 address falls within a CIDR subnet.

    .DESCRIPTION
        Performs bitwise AND against the subnet mask derived from prefix length.
        Accepts a pre-parsed CIDR hashtable -- caller parses once, passes result
        here, avoiding redundant parsing.

    .PARAMETER IP
        IPv4 address to test.

    .PARAMETER ParsedCIDR
        Hashtable from Parse-CIDR: { Network [string], Prefix [int] }

    .OUTPUTS
        [bool]

    .EXAMPLE
        $p = Parse-CIDR '10.210.24.0/22'
        Test-IpInCidr -IP '10.210.24.8' -ParsedCIDR $p   # True
        Test-IpInCidr -IP '10.210.28.1' -ParsedCIDR $p   # False
    #>

    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}$')]
        [string]$IP,

        [Parameter(Mandatory)]
        [hashtable]$ParsedCIDR
    )

    [uint32]$ipInt = ConvertTo-UInt32 -IPv4Address $IP
    [uint32]$netInt = ConvertTo-UInt32 -IPv4Address $ParsedCIDR.Network

    if ($ParsedCIDR.Prefix -eq 0) {
        [uint32]$mask = 0
    }
    else {
        [uint32]$mask = [uint32](
            ([math]::Pow(2, 32) - 1) -bxor
            ([math]::Pow(2, (32 - $ParsedCIDR.Prefix)) - 1)
        )
    }

    return (($ipInt -band $mask) -eq ($netInt -band $mask))
}


# ============================================================
# Get primary IPv4
# ============================================================

function Get-PrimaryIPv4 {
    <#
    .SYNOPSIS
        Returns the primary physical IPv4 address of this machine.

    .DESCRIPTION
        Filters out virtual adapters, VPNs, tunnels, and non-office interfaces,
        then returns the IP on the lowest-metric qualifying physical adapter.
        Returns $null if nothing qualifies -- callers must handle this.

    .OUTPUTS
        MSFT_NetIPAddress CIM instance, or $null.

    .EXAMPLE
        $ip = Get-PrimaryIPv4
        if ($ip) { Write-Log "  Primary IPv4 Address: $($ip.IPAddress)" -Level Info }
    #>


    [string[]]$excludePatterns = @(
        'vEthernet'
        'Hyper-V'
        'VirtualBox'
        'Virtual'
        'VMware'
        'Docker'
        'Wintun'
        'TAP'
        'VPN'
        'PPP'
        'Fortinet'
        'Loopback'
        'Bluetooth'
        'PANGP'
        'Juniper'
        'Teredo'
        '6to4'
    )

    $excludeRegex = (
        $excludePatterns |
        ForEach-Object {
            [regex]::Escape($_)
        }
    ) -join '|'

    $candidate = Get-NetAdapter -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Status -eq 'Up' -and
        $_.Virtual -eq $false -and
        $_.InterfaceDescription -notmatch $excludeRegex
    } |
    Get-NetIPAddress `
        -AddressFamily IPv4 `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -notlike '169.254.*' -and
        $_.IPAddress -ne '127.0.0.1' -and
        $_.AddressState -notin @(
            'Deprecated',
            'Invalid',
            'Duplicate'
        ) -and
        $_.PrefixOrigin -ne 'WellKnown'
    } |
    Sort-Object InterfaceMetric |
    Select-Object -First 1

    # TEST OVERRIDE - return a fake IP and adapter for testing without network access. Remove or comment out for production.
    <#
    $candidate = @{
		IPAddress = '10.211.65.120'
	#	InterfaceIndex = '205'
	}
	#>

    return $candidate
}


# ============================================================
# Get office metadata
# ============================================================

function Get-OfficeMetadata {
    <#
    .SYNOPSIS
        Downloads the office project subnet JSON from Azure Blob Storage.

    .DESCRIPTION
        Fetches and deserializes the country/project CIDR map.
        Retries once on transient failure with a 3-second delay.
        Throws a terminating error on permanent failure.

    .PARAMETER BlobUrl
        Full URL to the JSON blob. Defaults to $script:MetadataBlobUrl.

    .OUTPUTS
        [object[]] -- array of country entries, each with .Country and .Projects[]

    .EXAMPLE
        $metadata = Get-OfficeMetadata
    #>


    param(
        [string]$BlobUrl = $script:MetadataBlobUrl
    )

    Write-Log 'Fetching office metadata.'

    [int]$maxAttempts = 2
    $response = $null

    for (
        [int]$attempt = 1
        $attempt -le $maxAttempts
        $attempt++
    ) {

        try {
            $response = Invoke-RestMethod `
                -Uri $BlobUrl `
                -Method Get `
                -TimeoutSec 30 `
                -ErrorAction Stop

            break
        }
        catch {

            if ($attempt -lt $maxAttempts) {

                Write-Log `
                    "Metadata attempt $attempt failed. Retrying in 3 seconds." `
                    -Level Warning

                Start-Sleep -Seconds 3
            }
            else {
                throw "Metadata download failed: $($_.Exception.Message)"
            }
        }
    }

    if (-not $response) {
        throw 'Metadata response was empty.'
    }

    [object[]]$metadata = $response

    Write-Log "Metadata loaded: $($metadata.Count) country/region entries."

    return $metadata
}



# ============================================================
# Get Autopilot profile
# ============================================================

function Get-AutopilotProfileName {

    $regPath = 'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotPolicyCache'
    $regName = 'PolicyJsonCache'

    try {

        $regValue = (
            Get-ItemProperty `
                -Path $regPath `
                -Name $regName `
                -ErrorAction Stop
        ).$regName

        if ([string]::IsNullOrWhiteSpace($regValue)) {
            return $null
        }

        $data = $regValue | ConvertFrom-Json -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($data.DeploymentProfileName)) {
            return $null
        }

        return $data.DeploymentProfileName
    }
    catch {
        return $null
    }
}



# ============================================================
# Get CIDR matches
# ============================================================

function Get-CidrMatchesForIP {
    <#
    .SYNOPSIS
        Returns all CIDR entries from office metadata that contain the given IP.

    .DESCRIPTION
        Iterates every country/project entry. Each CIDR is parsed once and the
        parsed result is passed directly to Test-IpInCidr to avoid double-parsing.
        Malformed entries are skipped with a warning -- a single bad CIDR does not
        abort the scan. All matches are returned; caller picks the best one.

    .PARAMETER LocalIP
        IPv4 address to test.

    .PARAMETER OfficeMetadata
        Deserialized array from Get-OfficeMetadata.

    .OUTPUTS
        [PSCustomObject[]] -- zero or more matches. Each object has:
            Country        [string]
            ProjectCode    [string]
            NetworkAddress [string]
            PrefixLength   [int]    -- numeric, used for sort
            PrefixCidr     [string] -- display string e.g. "/22"

    .EXAMPLE
        $matches = Get-CidrMatchesForIP -LocalIP '10.210.24.8' -OfficeMetadata $metadata
    #>


    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}$')]
        [string]$LocalIP,

        [Parameter(Mandatory)]
        [object[]]$OfficeMetadata
    )

    $matchList = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($countryEntry in $OfficeMetadata) {

        if (-not $countryEntry.Country -or -not $countryEntry.Projects) {
            continue
        }

        [string]$countryCode = $countryEntry.Country

        foreach ($proj in $countryEntry.Projects) {

            [string]$cidr = $proj.IP_CIDR

            if ([string]::IsNullOrWhiteSpace($cidr)) {
                continue
            }

            try {
                [hashtable]$parsed = Split-CIDR -CIDR $cidr
            }
            catch {
                Write-Log `
                    "Skipping malformed CIDR '$cidr'." `
                    -Level Warning

                continue
            }

            try {
                [bool]$isMatch = Test-IpInCidr `
                    -IP $LocalIP `
                    -ParsedCIDR $parsed
            }
            catch {
                Write-Log `
                    "CIDR test failed for '$cidr'." `
                    -Level Warning

                continue
            }

            if ($isMatch) {

                $matchList.Add(
                    [PSCustomObject]@{
                        Country        = [string]$countryCode
                        ProjectCode    = [string]$proj.ProjectCode
                        NetworkAddress = [string]$parsed.Network
                        PrefixLength   = [int]$parsed.Prefix
                        PrefixCidr     = '/' + $parsed.Prefix
                    }
                )
            }
        }
    }

    return $matchList.ToArray()
}


# ============================================================
# Resolve best CIDR
# ============================================================

function Resolve-BestCidrMatch {
    <#
    .SYNOPSIS
        Returns the most specific CIDR match from a collection.

    .DESCRIPTION
        Most specific = longest prefix (e.g. /28 beats /22).
        Sorts on the integer PrefixLength property -- no string manipulation needed.

    .PARAMETER CidrMatches
        Output from Get-CidrMatchesForIP.

    .OUTPUTS
        Single [PSCustomObject] or $null if input is empty.
    #>


    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$CidrMatches
    )

    if (-not $CidrMatches -or $CidrMatches.Count -eq 0) {
        return $null
    }

    return (
        $CidrMatches |
        Sort-Object PrefixLength -Descending |
        Select-Object -First 1
    )
}


# ============================================================
# Resolve site from IP
# ============================================================

function Invoke-IPSiteResolution {
    <#
    .SYNOPSIS
        Orchestrates IP detection, metadata fetch, CIDR matching, and best-match
        selection. Returns resolved site context or $null on any failure.

    .DESCRIPTION
        Step 1: Get-PrimaryIPv4       -- detect real physical adapter IP
        Step 2: Get-OfficeMetadata    -- fetch country/project CIDR map
        Step 3: Get-CidrMatchesForIP  -- find all matching CIDR entries
        Step 4: Resolve-BestCidrMatch -- select most specific match

        Each step is independently guarded. Failure returns $null with a clear
        log message rather than propagating an exception to the caller.

    .OUTPUTS
        [PSCustomObject] with properties:
            Country        [string]  e.g. "BE"
            ProjectCode    [string]  e.g. "HQ101"
            NetworkAddress [string]  e.g. "10.208.92.0"
            PrefixLength   [int]     e.g. 22
            PrefixCidr     [string]  e.g. "/22"
        Or $null on any failure.

    .EXAMPLE
        $site = Invoke-IPSiteResolution
        if ($site) { Write-Host "$($site.Country) / $($site.ProjectCode)" }
    #>

    # -- Step 1: Detect primary IPv4 -----------------------------------------
    Write-Log 'B-1: Detecting primary IPv4.'

    $ipInfo = Get-PrimaryIPv4

    if (-not $ipInfo) {

        Write-Log `
            'No valid IPv4 found on any physical adapter.' `
            -Level Warning

        return $null
    }

    [string]$localIP = $ipInfo.IPAddress

    Write-Log `
        "Primary IP: $localIP | Adapter: $($ipInfo.InterfaceAlias)"

    # -- Step 2: Load office metadata ----------------------------------------
    Write-Log 'B-2: Loading office metadata.'

    [object[]]$officeMetadata = $null

    try {
        $officeMetadata = Get-OfficeMetadata
    }
    catch {

        Write-Log `
            "Metadata load failed: $($_.Exception.Message)" `
            -Level Error

        return $null
    }

    # -- Step 3: Match IP against all CIDRs ----------------------------------
    Write-Log "B-3: Matching $localIP against $($officeMetadata.Count) metadata entries."


    [PSCustomObject[]]$foundMatches = @(
        Get-CidrMatchesForIP `
            -LocalIP $localIP `
            -OfficeMetadata $officeMetadata
    )

    if ($foundMatches.Count -eq 0) {

        Write-Log `
            "No CIDR match for '$localIP'." `
            -Level Warning

        return $null
    }

    Write-Log "$($foundMatches.Count) CIDR match(es) found."

    # -- Step 4: Select most specific match ----------------------------------
    Write-Log 'B-4: Resolving best CIDR match.'

    $best = Resolve-BestCidrMatch `
        -CidrMatches $foundMatches

    if (-not $best) {
        Write-Log 'Failed to resolve best CIDR match.' -Level Error
        return $null
    }

    Write-Log `
        "Site resolved: Country=$($best.Country) | Project=$($best.ProjectCode) | Network=$($best.NetworkAddress)$($best.PrefixCidr)" `
        -Level Success

    return $best
}





# ============================================================
# Get Asset Tag from CSV
#
# IMPORTANT:
# This deliberately uses the same robust CSV handling approach
# as the known-good base script.
# ============================================================

function Get-AssetTag {

    param(
        [Parameter(Mandatory)]
        [string]$Serial
    )

    try {

        Write-Log 'A-1: Downloading asset list.'

        $response = Invoke-WebRequest `
            -Uri $script:CsvBlobUrl `
            -UseBasicParsing `
            -TimeoutSec 30 `
            -ErrorAction Stop


        # ----------------------------------------------------
        # Obtain raw bytes where possible.
        #
        # This avoids PowerShell 5.1 incorrectly interpreting
        # UTF-8/BOM CSV content before ConvertFrom-Csv sees it.
        # ----------------------------------------------------

        [string]$csvText = $null

        if ($response.RawContentStream) {

            try {
                $bytes = $response.RawContentStream.ToArray()

                if ($bytes -and $bytes.Count -gt 0) {

                    # UTF-8 BOM
                    if (
                        $bytes.Count -ge 3 -and
                        $bytes[0] -eq 0xEF -and
                        $bytes[1] -eq 0xBB -and
                        $bytes[2] -eq 0xBF
                    ) {
                        $csvText = [System.Text.Encoding]::UTF8.GetString(
                            $bytes,
                            3,
                            $bytes.Length - 3
                        )
                    }
                    else {
                        $csvText = [System.Text.Encoding]::UTF8.GetString($bytes)
                    }
                }
            }
            catch {
                $csvText = $null
            }
        }


        # Fallback for environments where RawContentStream is unavailable.
        if ([string]::IsNullOrWhiteSpace($csvText)) {
            $csvText = [string]$response.Content
        }


        if ([string]::IsNullOrWhiteSpace($csvText)) {
            Write-Log 'Asset list downloaded but was empty.' -Level Warning
            return $null
        }


        # Remove UTF-8 BOM if it survived decoding.
        $csvText = $csvText.TrimStart([char]0xFEFF)

        # Also handle the visible UTF-8 BOM representation sometimes
        # encountered when content was decoded incorrectly.
        if ($csvText.StartsWith('ï»¿')) {
            $csvText = $csvText.Substring(3)
        }


        # ----------------------------------------------------
        # Parse CSV
        # ----------------------------------------------------

        [PSCustomObject[]]$csv = @(
            $csvText | ConvertFrom-Csv
        )

        if (-not $csv -or $csv.Count -eq 0) {

            Write-Log `
                'Asset list contained no CSV records.' `
                -Level Warning

            return $null
        }

        Write-Log `
            "Asset list loaded: $($csv.Count) records."


        # ----------------------------------------------------
        # Validate expected columns
        # ----------------------------------------------------

        $firstRow = $csv | Select-Object -First 1

        if (
            -not ($firstRow.PSObject.Properties.Name -contains 'Serial') -or
            -not ($firstRow.PSObject.Properties.Name -contains 'AssetTag')
        ) {

            Write-Log `
                "CSV headers are not as expected. Found: $($firstRow.PSObject.Properties.Name -join ', ')" `
                -Level Error

            return $null
        }


        # ----------------------------------------------------
        # Exact serial comparison
        # ----------------------------------------------------

        $normalizedSerial = $Serial.Trim().ToUpper()

        [PSCustomObject[]]$matches = @(
            $csv |
            Where-Object {
                if ($null -eq $_.Serial) {
                    return $false
                }

                $csvSerial = $_.Serial.ToString().Trim().ToUpper()

                return ($csvSerial -eq $normalizedSerial)
            }
        )


        # ----------------------------------------------------
        # No match
        # ----------------------------------------------------

        if ($matches.Count -eq 0) {

            Write-Log `
                "No asset found for serial $normalizedSerial." `
                -Level Warning

            return $null
        }


        # ----------------------------------------------------
        # Multiple matches
        # ----------------------------------------------------

        if ($matches.Count -gt 1) {

            Write-Log `
                "WARNING: Found $($matches.Count) asset records for serial $normalizedSerial. Using first match." `
                -Level Warning
        }


        # ----------------------------------------------------
        # Validate AssetTag
        # ----------------------------------------------------

        $row = $matches[0]

        if ([string]::IsNullOrWhiteSpace($row.AssetTag)) {

            Write-Log `
                "Serial $normalizedSerial was found, but AssetTag is empty." `
                -Level Warning

            return $null
        }


        [string]$assetTag = $row.AssetTag.ToString().Trim().ToUpper()


        Write-Log `
            "Asset match confirmed: Serial=$normalizedSerial -> AssetTag=$assetTag" `
            -Level Success

        return $assetTag
    }
    catch {

        Write-Log `
            "Asset lookup failed: $($_.Exception.Message)" `
            -Level Error

        return $null
    }
}


# ============================================================
# MAIN
# ============================================================

Write-Log '============================================================'
Write-Log 'Starting Renaming Engine.'
Write-Log '============================================================'


# ------------------------------------------------------------
# Serial
# ------------------------------------------------------------

$Serial = (
    Get-CimInstance Win32_BIOS
).SerialNumber.Trim().ToUpper() -replace '\s+', ''

# To mock a seial that dont exist uncomment this
#$Serial = 'AAAAZZ999'

if ($Serial.Length -gt 9) {
    $SerialDisplay = $Serial.Substring($Serial.Length - 9)
}
else {
    $SerialDisplay = $Serial
}

Write-Log "Serial: $Serial"
Write-Log "Serial display suffix: $SerialDisplay"


# ------------------------------------------------------------
# Domain Join Check
# ------------------------------------------------------------

$computer = Get-CimInstance `
    -ClassName Win32_ComputerSystem `
    -ErrorAction SilentlyContinue

if ($computer.PartOfDomain) {

    Write-Log `
        'Device is domain joined. Rename cancelled.' -Level Warning
    exit 0
}


# ============================================================
# NAMING PRIORITY 1
# ASSET LIST
#
# THIS IS THE HIGHEST PRIORITY.
#
# No IP or GeoIP resolution is performed until this lookup
# has definitely failed to produce an AssetTag.
# ============================================================

[string]$name = $null
[string]$InventoryName = $null

Write-Log '============================================================'
Write-Log 'A: PRIORITY 1 - Checking asset list.'
Write-Log '============================================================'

$InventoryName = Get-AssetTag -Serial $Serial

if ($InventoryName) {

    # Asset list has absolute precedence.
    $name = $InventoryName

    Write-Log `
        "PRIORITY 1 SELECTED: Asset list name '$name'." -Level Success
}
else {
    Write-Log `
        'No asset-list match. Falling back to site/profile naming.' `
        -Level Warning
}


# ============================================================
# NAMING PRIORITY 2
# IP-BASED SITE RESOLUTION
# ONLY executed when Priority 1 produced no name.
# ============================================================

$siteContext = $null
$CountrySuffix = $null

if (-not $name) {

    Write-Log '============================================================'
    Write-Log 'B: PRIORITY 2 - Trying IP-based site resolution.'
    Write-Log '============================================================'

    $siteContext = Invoke-IPSiteResolution

    if ($siteContext) {

        if (
            [string]::IsNullOrWhiteSpace($siteContext.Country) -or
            [string]::IsNullOrWhiteSpace($siteContext.ProjectCode)
        ) {

            Write-Log `
                'Site context is missing Country or ProjectCode. Ignoring site result.' `
                -Level Warning

            $siteContext = $null
        }
        else {
            $CountrySuffix = $siteContext.Country.ToUpper()
            #Uncomment the following line if you want to use the site context for naming
            #Write-Log "Site context: Country=$CountrySuffix | Project=$($siteContext.ProjectCode)" -Level Success
        }
    }
}


# ============================================================
# NAMING PRIORITY 3
# GEOIP FALLBACK
# ONLY executed when asset and IP resolution failed.
# ============================================================

if (-not $name -and -not $siteContext) {

    Write-Log '============================================================'
    Write-Log 'C: PRIORITY 3 - Trying GeoIP fallback.'
    Write-Log '============================================================'

    try {

        $geoResponse = Invoke-RestMethod `
            -Uri $script:GeoUrl `
            -TimeoutSec 20 `
            -ErrorAction Stop

        [string]$geo = $geoResponse.cc

        if ([string]::IsNullOrWhiteSpace($geo)) {
            $geo = 'XX'
        }
        else {
            $geo = $geo.Trim().ToUpper()
        }

        $CountrySuffix = $geo

        Write-Log "GeoIP country: $CountrySuffix"
    }
    catch {
        $CountrySuffix = 'XX'
        Write-Log "GeoIP lookup failed. Using country XX." -Level Warning
    }
}


# ------------------------------------------------------------
# Autopilot Profile
# ------------------------------------------------------------

$AutopilotProfileName = Get-AutopilotProfileName
$UseAPNaming = $false
if (
    $AutopilotProfileName -in $AutopilotProfilesForNaming
) {
    Write-Log "Profile '$AutopilotProfileName' is configured for Project based naming."
    $UseAPNaming = $true
}


# ============================================================
# PROFILE-BASED NAMING
# Only runs if AssetTag did NOT produce a name.
# ============================================================

if (-not $name -and $UseAPNaming) {

    Write-Log '============================================================'
    Write-Log 'D: Applying Autopilot profile naming.'
    Write-Log '============================================================'

    switch -Exact ($AutopilotProfileName) {

        'OCB_AP_SD_ML' {

            if ($siteContext -and $siteContext.ProjectCode) {
                $name = "$($script:Company)-S-ML-$($siteContext.ProjectCode)".ToUpper()
                Write-Log "Mini-LAB name generated: $name"
            }
            elseif (-not $siteContext.ProjectCode) {
                $name = "$($script:Company)-S-ML-$($geo)$($serial.Substring($serial.Length - 3))".ToUpper()
                Write-Log "Mini-LAB name generated: $name"
            }
            else {
                Write-Log 'Mini-LAB requires a resolved project code. Rename cancelled.' -Level Warning
            }
        }

        'OCB_AP_SD_UF' {

            if ($siteContext -and $siteContext.ProjectCode) {
                $name = "$($script:Company)-S-UF-$($siteContext.ProjectCode)".ToUpper()
                Write-Log "UniField name generated: $name"
            }
            elseif (-not $siteContext.ProjectCode) {
                $name = "$($script:Company)-S-UF-$($geo)$($serial.Substring($serial.Length - 3))".ToUpper()
                Write-Log "UniField name generated: $name"
            }
            else {
                Write-Log 'UniField requires a resolved project code. Rename cancelled.' -Level Warning
            }
        }

        default {
            Write-Log "Unknown Autopilot profile '$AutopilotProfileName'. Rename cancelled." -Level Warning
        }
    }
}
elseif (-not $name -and -not $UseAPNaming) {
    if ($null -ne $siteContext -or $null -ne $geo) {
        $name = "$($script:Company)-$($CountrySuffix)$SerialDisplay".ToUpper()
        Write-Log "The name generated: $name"
    }
}


# ============================================================
# FINAL VALIDATION
# ============================================================

Write-Log '============================================================'
Write-Log 'FINAL NAME VALIDATION'
Write-Log '============================================================'


# SKIP RENAME CONDITIONS

if ([string]::IsNullOrWhiteSpace($name) -and -not $UseAPNaming) {
    Write-Log 'No valid device name generated. Nothing to do.' -Level Warning
    exit 0
}

$name = $name.Trim().ToUpper()

if ($name.Length -gt 15) {
    Write-Log `
        "Generated name '$name' exceeds 15 characters ($($name.Length)/15). Rename cancelled." -Level Error
    exit 0
}

$OldSysName = $(Get-ItemProperty $RegPathSysNameCurrent -ErrorAction SilentlyContinue).$RegKeySysValueName
$NewSysName = $(Get-ItemProperty $RegPathSysNameNew -ErrorAction SilentlyContinue).$RegKeySysValueName

if (($env:COMPUTERNAME.ToUpper() -eq $name) -and ($NewSysName -eq $name) -and ($OldSysName -eq $name)) {
    Write-Log "Device is already named '$name'. Nothing to do." -Level Success
    Write-RenameRegistryVersion
    exit 0
}
elseif (($NewSysName -eq $name) -and ($OldSysName -ne $name)) {
    Write-Log "Device is already renamed to '$name' but not yet restarted. Nothing to do." -Level Success
    Write-RenameRegistryVersion
    exit 0
}


# ============================================================
# RENAME
# ============================================================

Write-Log "FINAL NAME: '$name' | Current: '$env:COMPUTERNAME' | Length: $($name.Length)/15" -Level Success

try {
    Rename-Computer -NewName $name -Force -ErrorAction Stop
    Write-Log "Rename successful. Device will become '$name' after restart." -Level Success
}
catch {
    if ($_.FullyQualifiedErrorId -like '*NewNameIsOldName*') {
        Write-Log "New name is the same as the old name." -Level Warning
        Set-ItemProperty -Path $RegPathSysNameCurrent -Name $RegKeySysValueName -Value $name -ErrorAction Stop
        Set-ItemProperty -Path $RegPathSysNameNew -Name $RegKeySysValueName -Value $name -ErrorAction Stop
    }
}
finally {
    Write-RenameRegistryVersion
    Write-Log '============================================================'
    Write-Log 'Script completed.'
    Write-Log '============================================================'
}

