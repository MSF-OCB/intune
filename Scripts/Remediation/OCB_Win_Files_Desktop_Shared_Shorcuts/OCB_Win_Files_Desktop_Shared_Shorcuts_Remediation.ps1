$Users = Get-ChildItem -Path "C:\Users" -Exclude "Public","All Users" -Name -Force -Attributes D
# Process all the Users
foreach ($User in $Users){
    $Files = @(
    "MSF Documents.lnk",
    "HOWTO Setup MFA.pdf",
    "ICT Welcome Pack.pdf",
    "Private Documents.lnk",
    "Microsoft*.lnk"
    )
        foreach ($File in $Files) {
            Remove-Item -Path "C:\Users\$User\Desktop\$File" -Force -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item -Path "C:\Users\$User\OneDrive - MSF\Desktop\$File" -Force -Confirm:$false -ErrorAction SilentlyContinue
        }
}

Write-Output "Removing shortcuts for all profiles is completed"
