# Use windows capabilities to remove older QuickAssist
$WinVer = (Get-CimInstance Win32_OperatingSystem).version
If ($WinVer -lt "10.0.2"){
      $QuickAssistStat = Get-WindowsCapability -online -Name *QuickAssist*
      If ($QuickAssistStat.State -eq 'Installed') {
              Remove-WindowsCapability -Online -Name $QuickAssistStat.name -ErrorAction Continue
      }else {Write-Host "Quick assist is not installed." -ForegroundColor Cyan}
} else {Write-Host "`nYou are running Win 11, uninstalltion of Quick Assist will be via AppxPackages.`n" -ForegroundColor Cyan}
