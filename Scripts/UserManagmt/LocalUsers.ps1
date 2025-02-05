# Define user names to check
$userNames = @("MSFAdmin", "HQAdmin")

foreach ($userName in $userNames) {
    # Check if the user exists
    $user = Get-LocalUser -Name $userName -ErrorAction SilentlyContinue

    if ($user) {
        Write-Host "User $userName found. Deleting..."
        Remove-LocalUser -Name $userName
        Write-Host "User $userName deleted successfully."
    } else {
        Write-Host "User $userName not found."
    }
}
if (-not (Get-LocalUser -Name "MSFAuto" -ErrorAction SilentlyContinue)) {
    New-LocalUser "MSFAuto" -Password (ConvertTo-SecureString "YOUR PASS CHANGE" -AsPlainText -Force) -FullName "MSFAuto" -PasswordNeverExpires:$true -Disabled:$false -AccountNeverExpires:$true
    Add-LocalGroupMember -Group "Administrators" -Member "MSFAuto"
} else {
    Write-Host "User MSFAuto already exists."
}
