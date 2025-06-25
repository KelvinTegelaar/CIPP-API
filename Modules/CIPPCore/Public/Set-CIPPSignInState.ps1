function Set-CIPPSignInState {
    [CmdletBinding()]
    param (
        $UserID,
        [bool]$AccountEnabled,
        $TenantFilter,
        $APIName = 'Disable User Sign-in',
        $Headers
    )

    try {
        $body = @{
            accountEnabled = [bool]$AccountEnabled
        }
        $body = ConvertTo-Json -InputObject $body -Compress -Depth 5
        $UserDetails = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)?`$select=onPremisesSyncEnabled" -noPagination $true -tenantid $TenantFilter -verbose
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)" -tenantid $TenantFilter -type PATCH -body $body -verbose
        Write-LogMessage -headers $Headers -API $APIName -message "Successfully set account enabled state to $AccountEnabled for $UserID" -Sev 'Info' -tenant $TenantFilter

        if ($UserDetails.onPremisesSyncEnabled -eq $true) {
            throw "WARNING: User $UserID is AD Sync enabled. Please enable/disable in the local AD."
        } else {
            return "Successfully set account enabled state to $AccountEnabled for $UserID"
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to set sign-in state for $UserID. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}
