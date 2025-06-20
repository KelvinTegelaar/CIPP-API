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
        $Result = "Failed to revoke sessions for $($username). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        # TODO - needs to be changed to throw, but the rest of the functions using this cant handle anything but a return.
        return $Result
    }
}
