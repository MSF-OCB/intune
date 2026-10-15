# ============================================================================
# MSF Azure PowerShell Script Orchestrator
#
# Downloads PowerShell scripts from Azure Blob Storage and executes them
# sequentially in isolated Windows PowerShell 5.1 processes.
#
# Features:
#   - Isolated child processes
#   - No function/variable collisions
#   - UTF-8 download
#   - Retry support
#   - Execution timeout
#   - Stop on first failed script
#   - Child exit-code validation
#   - Temporary script cleanup
#   - PowerShell 5.1 compatible
# ============================================================================

# ============================================================================
# CONFIGURATION
# ============================================================================

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ProgressPreference = 'SilentlyContinue'

$MaxAttempts = 2
$RetryDelaySec = 3
$DownloadTimeoutSec = 180
$ScriptTimeoutSec = 900

$ScriptUrls = @(
    'https://msfocbshare.blob.core.windows.net/ict-prod/Intune/Enroll/UF/Autopilot/Unifield_Onboarding_Autopilot.ps1',
    'https://msfocbshare.blob.core.windows.net/ict-prod/Intune/Enroll/Helpers/1-RenameComputerByIP.ps1',
    'https://msfocbshare.blob.core.windows.net/ict-prod/Intune/Enroll/Helpers/2-ActivateWinOEMKey.ps1'
)

# ============================================================================
# POWERSHELL 5.1
# ============================================================================

$PowerShellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

if (-not (Test-Path -LiteralPath $PowerShellExe)) {
    throw "Windows PowerShell 5.1 was not found: $PowerShellExe"
}

# ============================================================================
# ADMIN CHECK
# ============================================================================

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

if (-not $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )) {

    Write-Error 'This script must be run as Administrator.'
    exit 1
}

# ============================================================================
# LOGGING
# ============================================================================

function Get-TimeStamp {
    Get-Date -Format 'dd-MM-yyyy_HH:mm:ss.fff'
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $Colors = @{
        INFO    = 'Cyan'
        SUCCESS = 'Green'
        WARNING = 'Yellow'
        ERROR   = 'Red'
        DEBUG   = 'Gray'
    }

    $Color = $Colors[$Level]

    Write-Host (
        '[{0}] [{1}] {2}' -f
        (Get-TimeStamp),
        $Level,
        $Message
    ) -ForegroundColor $Color
}

# ============================================================================
# DOWNLOAD SCRIPT
# ============================================================================

function Get-ScriptContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSec
    )

    Write-Log "Downloading: $Url" 'DEBUG'

    $Response = Invoke-WebRequest `
        -Uri $Url `
        -UseBasicParsing `
        -TimeoutSec $TimeoutSec `
        -Headers @{
        Accept       = 'text/plain, application/x-powershell, */*'
        'User-Agent' = 'MSF-Orchestrator/1.0'
    } `
        -ErrorAction Stop

    if ($null -ne $Response.RawContentStream -and
        $Response.RawContentStream.CanRead) {

        $MemoryStream = New-Object System.IO.MemoryStream

        try {
            $Response.RawContentStream.CopyTo($MemoryStream)

            return [System.Text.Encoding]::UTF8.GetString(
                $MemoryStream.ToArray()
            )
        }
        finally {
            $MemoryStream.Dispose()
        }
    }

    if ($null -ne $Response.Content) {
        return [string]$Response.Content
    }

    throw "No content was returned from $Url"
}

# ============================================================================
# EXECUTE CHILD SCRIPT
# ============================================================================

function Invoke-IsolatedPowerShell {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptContent,

        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSec
    )

    $TempDirectory = Join-Path $env:TEMP 'MSF-Orchestrator'

    if (-not (Test-Path -LiteralPath $TempDirectory)) {
        New-Item `
            -Path $TempDirectory `
            -ItemType Directory `
            -Force `
            -ErrorAction Stop | Out-Null
    }

    $TempScript = Join-Path $TempDirectory (
        'MSF-{0}-{1}.ps1' -f
        ([Guid]::NewGuid().ToString('N')),
        $ScriptName
    )

    $Process = $null

    try {

        # Write the downloaded script temporarily so that PowerShell 5.1
        # can execute it as a normal script file.
        [System.IO.File]::WriteAllText(
            $TempScript,
            $ScriptContent,
            (New-Object System.Text.UTF8Encoding($false))
        )

        $StartInfo = New-Object System.Diagnostics.ProcessStartInfo

        $StartInfo.FileName = $PowerShellExe

        $StartInfo.Arguments = (
            '-NoLogo -NoProfile -NonInteractive ' +
            '-ExecutionPolicy Bypass ' +
            '-File "{0}"' -f $TempScript
        )

        $StartInfo.UseShellExecute = $false
        $StartInfo.CreateNoWindow = $true
        $StartInfo.RedirectStandardOutput = $true
        $StartInfo.RedirectStandardError = $true

        $Process = New-Object System.Diagnostics.Process
        $Process.StartInfo = $StartInfo

        Write-Log "Starting: $ScriptName" 'DEBUG'

        if (-not $Process.Start()) {
            throw "Unable to start PowerShell for $ScriptName"
        }

        Write-Log "Child PID: $($Process.Id)" 'DEBUG'

        # Read both streams asynchronously to prevent pipe deadlocks.
        $StdOutTask = $Process.StandardOutput.ReadToEndAsync()
        $StdErrTask = $Process.StandardError.ReadToEndAsync()

        $TimeoutMilliseconds = $TimeoutSec * 1000

        if (-not $Process.WaitForExit($TimeoutMilliseconds)) {

            Write-Log `
                "Timeout after $TimeoutSec seconds: $ScriptName" `
                'ERROR'

            try {
                $Process.Kill()
            }
            catch {
                # Process may already have exited.
            }

            throw "Child process timed out: $ScriptName"
        }

        # Wait for asynchronous stream readers to finish.
        $StdOut = $StdOutTask.Result
        $StdErr = $StdErrTask.Result

        $ExitCode = $Process.ExitCode

        # --------------------------------------------------------------------
        # CHILD OUTPUT
        # --------------------------------------------------------------------

        if (-not [string]::IsNullOrWhiteSpace($StdOut)) {

            Write-Log "Output: $ScriptName" 'DEBUG'

            foreach ($Line in ($StdOut -split "`r?`n")) {

                if (-not [string]::IsNullOrWhiteSpace($Line)) {
                    Write-Host $Line
                }
            }
        }

        # --------------------------------------------------------------------
        # CHILD ERROR OUTPUT
        #
        # STDERR alone does NOT mean failure.
        # The exit code is the authoritative success/failure indicator.
        # --------------------------------------------------------------------

        if (-not [string]::IsNullOrWhiteSpace($StdErr)) {

            if ($ExitCode -ne 0) {

                Write-Log "Child STDERR: $ScriptName" 'ERROR'

                foreach ($Line in ($StdErr -split "`r?`n")) {

                    if (-not [string]::IsNullOrWhiteSpace($Line)) {
                        Write-Host $Line -ForegroundColor Red
                    }
                }

            }
            else {

                Write-Log `
                    "Child produced STDERR but exited successfully: $ScriptName" `
                    'DEBUG'
            }
        }

        Write-Log "Exit code: $ExitCode" 'DEBUG'

        if ($ExitCode -ne 0) {
            throw "Child script failed with exit code $ExitCode`: $ScriptName"
        }

        Write-Log "Completed: $ScriptName" 'SUCCESS'

        return $true
    }
    finally {

        if ($null -ne $Process) {

            try {
                $Process.Dispose()
            }
            catch {
                # Nothing else to do.
            }
        }

        if (Test-Path -LiteralPath $TempScript) {

            Remove-Item `
                -LiteralPath $TempScript `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================================
# DOWNLOAD + EXECUTE + RETRY
# ============================================================================

function Invoke-RemoteScriptWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [int]$MaxAttempts,

        [Parameter(Mandatory = $true)]
        [int]$RetryDelaySec,

        [Parameter(Mandatory = $true)]
        [int]$DownloadTimeoutSec,

        [Parameter(Mandatory = $true)]
        [int]$ScriptTimeoutSec
    )

    $ScriptName = Split-Path -Path $Url -Leaf

    Write-Log '------------------------------------------------------------' 'INFO'
    Write-Log "Processing: $ScriptName" 'INFO'

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {

        Write-Log `
            "Attempt $Attempt of ${MaxAttempts}: $ScriptName" `
            'INFO'

        try {

            # Download
            $ScriptContent = Get-ScriptContent `
                -Url $Url `
                -TimeoutSec $DownloadTimeoutSec

            if ([string]::IsNullOrWhiteSpace($ScriptContent)) {
                throw 'Downloaded script is empty.'
            }

            Write-Log `
                "Downloaded $($ScriptContent.Length) characters." `
                'DEBUG'

            # Execute
            $Result = Invoke-IsolatedPowerShell `
                -ScriptContent $ScriptContent `
                -ScriptName $ScriptName `
                -TimeoutSec $ScriptTimeoutSec

            if (-not $Result) {
                throw 'Child execution returned failure.'
            }

            Write-Log "OK: $ScriptName" 'SUCCESS'

            return $true
        }
        catch {

            $ErrorMessage = $_.Exception.Message

            Write-Log `
                "Attempt $Attempt failed: $ErrorMessage" `
                'ERROR'

            if ($Attempt -lt $MaxAttempts) {

                Write-Log `
                    "Retrying in $RetryDelaySec seconds..." `
                    'WARNING'

                Start-Sleep -Seconds $RetryDelaySec
            }
        }
    }

    Write-Log `
        "FAILED after $MaxAttempts attempts: $ScriptName" `
        'ERROR'

    return $false
}

# ============================================================================
# MAIN
# ============================================================================

Write-Log '============================================================' 'INFO'
Write-Log 'MSF Azure PowerShell Orchestrator Started' 'INFO'
Write-Log "PowerShell: $($PSVersionTable.PSVersion)" 'DEBUG'
Write-Log "Child PowerShell: $PowerShellExe" 'DEBUG'
Write-Log "Scripts: $($ScriptUrls.Count)" 'INFO'
Write-Log '============================================================' 'INFO'

try {

    foreach ($Url in $ScriptUrls) {

        $Success = Invoke-RemoteScriptWithRetry `
            -Url $Url `
            -MaxAttempts $MaxAttempts `
            -RetryDelaySec $RetryDelaySec `
            -DownloadTimeoutSec $DownloadTimeoutSec `
            -ScriptTimeoutSec $ScriptTimeoutSec

        if (-not $Success) {

            $FailedScript = Split-Path -Path $Url -Leaf

            throw "Execution stopped. Failed script: $FailedScript"
        }

        Write-Log 'Moving to next script...' 'INFO'
    }

    Write-Log '============================================================' 'SUCCESS'
    Write-Log 'ALL SCRIPTS COMPLETED SUCCESSFULLY' 'SUCCESS'
    Write-Log '============================================================' 'SUCCESS'

    exit 0
}
catch {

    Write-Log '============================================================' 'ERROR'
    Write-Log 'ORCHESTRATOR FAILED' 'ERROR'
    Write-Log "Error: $($_.Exception.Message)" 'ERROR'
    Write-Log '============================================================' 'ERROR'

    exit 1
}

