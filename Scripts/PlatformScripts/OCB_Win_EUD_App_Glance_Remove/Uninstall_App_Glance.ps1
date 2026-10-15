<#
.SYNOPSIS
    Ultra-short, bullet-proof Mirametrix Glance silent uninstaller
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# One-liner admin check that never fails
if ((whoami /groups /fo csv | ConvertFrom-Csv | Select-Object -Expand SID) -notcontains 'S-1-5-32-544') {
    Write-Error "Administrator rights required."
    exit 3
}

# Find uninstaller
$uninstaller = @(
    "$env:ProgramFiles\Mirametrix\Glance\bin\uninstall.exe"
    "${env:ProgramFiles(x86)}\Mirametrix\Glance\bin\uninstall.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $uninstaller) {
    Write-Host "Mirametrix Glance not installed."
    exit 0
}

Write-Host "Uninstalling: $uninstaller"

if ($PSCmdlet.ShouldProcess($uninstaller, "Silent uninstall")) {
    $p = Start-Process $uninstaller -ArgumentList '/S' -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -in 0,3010) {
        Write-Host "Success (exit code $($p.ExitCode))"
        exit 0
    } else {
        Write-Error "Failed (exit code $($p.ExitCode))"
        exit $p.ExitCode
    }
}
