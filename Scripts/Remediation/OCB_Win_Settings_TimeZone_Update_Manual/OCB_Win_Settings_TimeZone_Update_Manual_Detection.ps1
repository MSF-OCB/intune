# Detection script for tzautoupdate service startup type
$service = Get-Service -Name tzautoupdate -ErrorAction SilentlyContinue
if ($service -and $service.StartType -eq 'Disabled') {
    Write-Output "The TimeZone service is set to Manual."
    exit 0
} else {
    Write-Output "The TimeZone service is set to Automatic."
    exit 1
}
