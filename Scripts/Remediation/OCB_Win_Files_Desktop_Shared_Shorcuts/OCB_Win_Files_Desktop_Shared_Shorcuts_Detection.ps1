$Users = Get-ChildItem -Path "C:\Users" -Exclude "Public","All Users" -Name -Force -Attributes D
# Process all the Users
$AllProfilePaths = @()
foreach ($User in $Users){
    $Files = @(
    "MSF Documents.lnk",
    "HOWTO Setup MFA.pdf",
    "ICT Welcome Pack.pdf",
    "Private Documents.lnk",
    "Microsoft*.lnk"
    )
        foreach ($File in $Files) {
        $PathOutput = Test-Path "C:\Users\$User\Desktop\$File"
        $PathOutput1 = Test-Path "C:\Users\$User\OneDrive - MSF\Desktop\$File"
        $AllProfilePaths += $PathOutput
        $AllProfilePaths += $PathOutput1
        }
}
# evaluate if output contains traces of Old files
If ($AllProfilePaths -notcontains "true")
    {
    Write-Host "Good, No legacy ICT Files shortcuts exist on desktop."
    Exit 0
    }
Else
    {
    Write-Host "Warning: Legacy ICT desktop shortcuts exist."
    Exit 1  
    }
