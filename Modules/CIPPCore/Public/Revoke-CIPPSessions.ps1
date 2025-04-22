function Revoke-CIPPSessions {
    [CmdletBinding()]
    param (
        $Headers,
        $UserID,
        $Username,
        $APIName = 'Revoke Sessions',
        $TenantFilter
    )

    try {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/invalidateAllRefreshTokens" -tenantid $TenantFilter -type POST -body '{}' -verbose
        Write-LogMessage -headers $Headers -API $APIName -message "Revoked sessions for $($username)" -Sev 'Info' -tenant $TenantFilter
        return "Success. All sessions by $username have been revoked"

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to revoke sessions for $($username): $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Revoke Session Failed: $($ErrorMessage.NormalizedError)"
    }
}
