## Remove local group policies for computers and users
## Remove Computer & User policy database
$Policy = @(
"$env:windir\System32\GroupPolicy",
"$env:windir\System32\GroupPolicyUsers",
"C:\WINDOWS\security\Database\secedit.sd",
"HKCU:Software\Microsoft\Windows\CurrentVersion\Policies\*\*",
"HKCU:Software\Microsoft\WindowsSelfHost\*",
"HKCU:Software\Policies\*",
"HKLM:Software\Policies\*",
"HKLM:Software\Microsoft\Policies\*",
"HKLM:Software\Microsoft\Windows\CurrentVersion\Policies\*",
"HKLM:Software\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate\*",
"HKLM:Software\Microsoft\WindowsSelfHost\*",
"HKLM:Software\WOW6432Node\Microsoft\Policies\*",
"HKLM:Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies\*",
"HKLM:Software\WOW6432Node\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate\*",
"HKLM:SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
)
ForEach ($Entry in $Policy) {
    Remove-Item -Path $Entry -Recurse -Force -ErrorAction SilentlyContinue
}
klist.exe purge
gpupdate /force
