function Revoke-CIPPSessions {
    [CmdletBinding()]
    param (
        $ExecutingUser,
        $userid,
        $username,
        $TenantFilter
    )

    try {
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/invalidateAllRefreshTokens" -tenantid $TenantFilter -type POST -body '{}'  -verbose
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API "Revoke Sessions"  -message "Revoked sessions for $($username)" -Sev "Info" -tenant $TenantFilter
        return "Success. All sessions by $username have been revoked"

    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API "Revoke Sessions"  -message "Revoked sessions for $($username)" -Sev "Info" -tenant $TenantFilter
        return "Revoke Session Failed: $($_.Exception.Message)" 
    }
}
