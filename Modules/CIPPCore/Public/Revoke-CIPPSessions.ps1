function Revoke-CIPPSessions {
    [CmdletBinding()]
    param (
        $ExecutingUser,
        $userid,
        $username,
        $APIName = 'Revoke Sessions',
        $TenantFilter
    )

    try {
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/invalidateAllRefreshTokens" -tenantid $TenantFilter -type POST -body '{}' -verbose
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Revoked sessions for $($username)" -Sev 'Info' -tenant $TenantFilter
        return "Success. All sessions by $username have been revoked"

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Failed to revoke sessions for $($username): $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Revoke Session Failed: $($ErrorMessage.NormalizedError)"
    }
}
