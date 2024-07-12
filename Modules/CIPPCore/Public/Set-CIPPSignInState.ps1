function Set-CIPPSignInState {
    [CmdletBinding()]
    param (
        $UserId,
        [bool]$AccountEnabled,
        $TenantFilter,
        $APIName = 'Disable User Sign-in',
        $ExecutingUser
    )

    try {
        $body = @{
            accountEnabled = [bool]$AccountEnabled
        }
        $body = ConvertTo-Json -InputObject $body -Compress -Depth 5
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserId)" -tenantid $TenantFilter -type PATCH -body $body -verbose
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Set account enabled state to $AccountEnabled for $UserId" -Sev 'Info' -tenant $TenantFilter
        return "Set account enabled state to $AccountEnabled for $UserId"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not disable sign in for $UserId. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Could not disable $UserId. Error: $($ErrorMessage.NormalizedError)"
    }
}

