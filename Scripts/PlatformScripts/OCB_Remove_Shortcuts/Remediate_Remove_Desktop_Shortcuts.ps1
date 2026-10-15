# Get all Users
$Users = Get-ChildItem -Path "C:\Users" -Exclude Public -Name
# Process all the Users
foreach ($User in $Users){
    Remove-Item -Path "C:\Users\$User\Desktop\MSF Documents.lnk" -Force > $null -ErrorAction Continue
    Remove-Item -Path "C:\Users\$User\Desktop\Private Documents.lnk" -Force > $null -ErrorAction Continue
    Remove-Item -Path "C:\Users\$User\Desktop\ICT Welcome Pack.pdf" -Force > $null -ErrorAction Continue
    Remove-Item -Path "C:\Users\$User\Desktop\HOWTO Setup MFA.pdf" -Force > $null -ErrorAction Continue
}
Write-Output "Remove shortcuts for default profile"
